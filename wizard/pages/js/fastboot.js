// Fastboot client over WebUSB, for the erase-gated rooting slice only.
// After the bootrom handshake the phone re-enumerates in fastboot mode;
// the user picks it here by interface signature (0xff/0x42/0x01, like adb),
// so no PID is hardcoded.
//
// Protocol: ASCII command string, then responses of 4-byte tag + payload:
//   INFO<text>   progress line — keep reading
//   OKAY         command finished
//   FAIL<reason> command failed
//   DATA<8-byte big-endian n>  device agreed to receive n bytes;
//                the host sends the raw payload, then reads again
//
// Constraint by construction: flashBoot() is the ONLY flash path and the
// partition name 'boot' never appears as a parameter. super, vbmeta,
// system, product and the preloader are unreachable from this module.

// The fastboot gadget advertises class ff / subclass 42. The protocol byte is
// not stable across builds: this phone reports 03, while other gadgets use 01.
// Match the class and subclass only — the PID already tells us it is fastboot.
var FASTBOOT = {
  device: null, out: null, inp: null,
  log: function () {},          // main.js replaces this

  // Reuse a phone the user already granted this session. WebUSB does not
  // expose a device's interfaces until it is opened, so an interface check
  // here can never match a granted-but-closed phone; the page then falls back
  // to a chooser dialog that blocks the retry. Match on the vendor instead,
  // which is readable before opening, and only ask when nothing is granted.
  // The preloader is the one MediaTek device that must never be used here, so
  // exclude it when both it and the fastboot device are already granted.
  pick: function () {
    var self = this;
    return navigator.usb.getDevices().then(function (list) {
      var granted = (list || []).filter(function (d) { return d.vendorId === 0x0e8d; });
      if (granted.length > 1) {
        granted = granted.filter(function (d) { return d.productId !== 0x2000; });
      }
      if (granted.length === 1) { self.device = granted[0]; return granted[0]; }
      return navigator.usb.requestDevice({ filters: [
        { classCode: 255, subclassCode: 66 }
      ]}).then(function (d) { self.device = d; return d; });
    });
  },

  findIface: function () {
    var cfgs = this.device.configurations;
    for (var c = 0; c < cfgs.length; c++) {
      var ifaces = cfgs[c].interfaces;
      for (var i = 0; i < ifaces.length; i++) {
        var alt = ifaces[i].alternates[0];
        if (alt.interfaceClass === 255 && alt.interfaceSubclass === 66) {
          return ifaces[i].interfaceNumber;
        }
      }
    }
    throw new Error('no fastboot interface on this device');
  },

  // One error for the state that needs a power cycle, so the page can
  // recognise it wherever it comes out of this module.
  _stopped: function () {
    var e = new Error('the phone stopped answering. Nothing was written to it. ' +
      'Unplug it, pull the battery, put it back, and start again from the power-cycle step.');
    e.stopped = true;
    return e;
  },

  // USB calls against a bootloader that stopped reading never settle: a close
  // waits on its pending transfer, an open waits on a device that is not
  // listening, and a bulk write waits for a receiver that never drains. Any one
  // of those leaves the page sitting on "connecting…" with no message. Race the
  // whole handshake against one timer so that state reports itself instead.
  CONNECT_TIMEOUT_MS: 30000,

  connect: function () {
    var self = this;
    var timer = null;
    // A failed attempt can leave this handle open with a transfer still
    // pending. Closing first cancels that transfer and lets a retry start
    // from a known state instead of failing with "already open".
    var handshake = this.device.close().catch(function () {}).then(function () {
      return self.device.open();
    }).then(function () {
      if (self.device.configuration === null) return self.device.selectConfiguration(1);
    }).then(function () {
      self._ifNum = self.findIface();
      return self.device.claimInterface(self._ifNum, false);
    }).then(function () {
      var ifaces = self.device.configuration.interfaces;
      for (var i = 0; i < ifaces.length; i++) {
        if (ifaces[i].interfaceNumber !== self._ifNum) continue;
        var eps = ifaces[i].alternates[0].endpoints;
        for (var e = 0; e < eps.length; e++) {
          if (eps[e].type === 'bulk') {
            if (eps[e].direction === 'out') self.out = eps[e].endpointNumber;
            else self.inp = eps[e].endpointNumber;
          }
        }
      }
      if (self.out === null || self.inp === null) throw new Error('no bulk endpoints on the fastboot interface');
      self.log('Claimed fastboot interface.');
      return self.command('getvar:version', null, null);
    });

    // After a timeout the page has already moved on, but this promise can still
    // reject when the stale transfer is torn down. Swallow that here so it does
    // not surface as an uncaught rejection; the race below still reports the
    // original failure.
    handshake.catch(function () {});

    var timeout = new Promise(function (_, reject) {
      timer = setTimeout(function () { reject(self._stopped()); }, self.CONNECT_TIMEOUT_MS);
    });

    return Promise.race([handshake, timeout]).then(function (v) {
      clearTimeout(timer);
      return v;
    }, function (e) {
      clearTimeout(timer);
      throw e;
    });
  },

  // A bootloader left waiting for a payload it never received stops answering
  // commands entirely, and a plain read then blocks forever with no message.
  // This timeout turns that silent hang into an error the page can explain.
  READ_TIMEOUT_MS: 30000,

  _read: function () {
    var self = this;
    var timer = null;
    var pending = this.device.transferIn(this.inp, 512).then(function (res) {
      if (res.status !== 'ok') throw new Error('USB read status ' + res.status);
      return new Uint8Array(res.data.buffer, res.data.byteOffset, res.data.byteLength);
    });
    var timeout = new Promise(function (_, reject) {
      timer = setTimeout(function () { reject(self._stopped()); }, self.READ_TIMEOUT_MS);
    });
    return Promise.race([pending, timeout]).then(function (v) {
      clearTimeout(timer);
      return v;
    }, function (e) {
      clearTimeout(timer);
      throw e;
    });
  },

  // One response packet. The DATA size is normally an 8-byte big-endian
  // integer, but this phone's bootloader speaks the older protocol and sends
  // the size as 8 ASCII hex digits instead ("DATA01800000"). Both forms are 8
  // bytes long, so tell them apart by content: eight printable hex characters
  // can only be the ASCII form. Reading that form as an integer yields a
  // nonsense size, and the transfer is refused before a byte is written.
  _resp: function () {
    return this._read().then(function (b) {
      if (b.length < 4) throw new Error('short fastboot response');
      var id = String.fromCharCode(b[0], b[1], b[2], b[3]);
      var dv = new DataView(b.buffer, b.byteOffset, b.length);
      var text = '';
      for (var i = 4; i < b.length; i++) text += String.fromCharCode(b[i]);
      var size = 0;
      if (id === 'DATA' && b.length >= 12) {
        var allHex = true;
        for (var h = 4; h < 12; h++) {
          var c = b[h];
          var hex = (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66);
          if (!hex) { allHex = false; break; }
        }
        size = allHex
          ? parseInt(text.slice(0, 8), 16)
          : dv.getUint32(4, false) * 4294967296 + dv.getUint32(8, false);
      }
      return { id: id, text: text, size: size };
    });
  },

  // Sends the command string, then consumes responses until OKAY/FAIL.
  // data (optional) is only sent after the device answers DATA, and only
  // if its declared size matches exactly. onInfo gets INFO lines,
  // onProgress gets (sentBytes, total) during the DATA phase.
  command: function (cmd, data, onInfo, onProgress) {
    var self = this;
    return this.device.transferOut(this.out, str2ab(cmd)).then(function () {
      return self._loop(data, onInfo, onProgress);
    });
  },

  _loop: function (data, onInfo, onProgress) {
    var self = this;
    return this._resp().then(function (r) {
      if (r.id === 'INFO') {
        if (onInfo) onInfo(r.text);
        return self._loop(data, onInfo, onProgress);
      }
      if (r.id === 'OKAY') return r.text || 'OKAY';
      if (r.id === 'FAIL') throw new Error('fastboot FAIL: ' + r.text);
      if (r.id === 'DATA') {
        if (!data) throw new Error('unexpected DATA response of ' + r.size + ' bytes');
        if (r.size !== data.length) throw new Error('DATA size mismatch: the phone wants ' +
          r.size + ' bytes but the image is ' + data.length + '. Nothing was written, but the ' +
          'phone is now waiting for that payload and will ignore commands until it is ' +
          'power-cycled.');
        return self._sendData(data, onProgress).then(function () {
          return self._loop(null, onInfo, onProgress);
        });
      }
      throw new Error('unexpected fastboot response ' + r.id);
    });
  },

  // getvar replies are not consistent across boots: some builds put the value
  // in an INFO line and send a bare OKAY, others put it straight in the OKAY
  // payload. Collect INFO lines, fall back to the OKAY text, and strip the
  // leading "name: " either way. A bare OKAY means the value was empty.
  getvar: function (name) {
    var parts = [];
    return this.command('getvar:' + name, null, function (line) { parts.push(String(line)); })
      .then(function (okay) {
        var text = parts.length ? parts.join('') : String(okay || '');
        if (/^OKAY$/i.test(text.trim())) text = '';
        var cut = text.indexOf(':');
        return (cut >= 0 ? text.slice(cut + 1) : text).trim();
      });
  },

  _sendData: function (data, onProgress) {
    var self = this, chunk = 64 * 1024, seq = Promise.resolve();
    for (var off = 0; off < data.length; off += chunk) {
      (function (start) {
        seq = seq.then(function () {
          if (onProgress) onProgress(start, data.length);
          return self.device.transferOut(self.out, data.subarray(start, Math.min(start + chunk, data.length)));
        });
      })(off);
    }
    return seq;
  },

  unlock: function (onInfo) {
    // Blocks on the device until the physical confirm on the keypad;
    // INFO lines stream the prompt while it waits.
    return this.command('flashing unlock', null, onInfo, null);
  },

  // download: declares the size, the DATA phase carries the payload,
  // then flash: writes it to boot. Two commands, one partition, no options.
  flashBoot: function (img, onInfo, onProgress) {
    var self = this;
    var hex = img.length.toString(16).toUpperCase();
    while (hex.length < 8) hex = '0' + hex;
    this.log('download:' + hex + ' (' + img.length + ' bytes)');
    return this.command('download:' + hex, img, onInfo, onProgress)
      .then(function () { return self.command('flash:boot', null, onInfo, null); });
  },

  reboot: function () {
    var self = this;
    return this.command('reboot', null, null, null).catch(function (e) {
      if (/^fastboot FAIL/.test(e.message)) throw e;
      // otherwise the phone dropped off the bus as it rebooted — that IS success
      self.log('device left fastboot (' + e.message + ')');
    });
  }
};
