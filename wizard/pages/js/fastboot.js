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

var FASTBOOT = {
  device: null, out: null, inp: null,
  log: function () {},          // main.js replaces this

  pick: function () {
    var self = this;
    return navigator.usb.requestDevice({ filters: [
      { classCode: 255, subclassCode: 66, protocolCode: 1 }
    ]}).then(function (d) { self.device = d; return d; });
  },

  findIface: function () {
    var cfgs = this.device.configurations;
    for (var c = 0; c < cfgs.length; c++) {
      var ifaces = cfgs[c].interfaces;
      for (var i = 0; i < ifaces.length; i++) {
        var alt = ifaces[i].alternates[0];
        if (alt.interfaceClass === 255 && alt.interfaceSubclass === 66 && alt.interfaceProtocol === 1) {
          return ifaces[i].interfaceNumber;
        }
      }
    }
    throw new Error('no fastboot interface on this device');
  },

  connect: function () {
    var self = this;
    return this.device.open().then(function () {
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
  },

  _read: function () {
    var self = this;
    return this.device.transferIn(this.inp, 512).then(function (res) {
      if (res.status !== 'ok') throw new Error('USB read status ' + res.status);
      return new Uint8Array(res.data.buffer, res.data.byteOffset, res.data.byteLength);
    });
  },

  // One response packet. DATA size is an 8-byte big-endian integer.
  _resp: function () {
    return this._read().then(function (b) {
      if (b.length < 4) throw new Error('short fastboot response');
      var id = String.fromCharCode(b[0], b[1], b[2], b[3]);
      var dv = new DataView(b.buffer, b.byteOffset, b.length);
      var text = '';
      for (var i = 4; i < b.length; i++) text += String.fromCharCode(b[i]);
      var size = 0;
      if (id === 'DATA' && b.length >= 12) {
        size = dv.getUint32(4, false) * 4294967296 + dv.getUint32(8, false);
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
        if (r.size !== data.length) throw new Error('DATA size mismatch: device wants ' +
          r.size + ' bytes, image is ' + data.length);
        return self._sendData(data, onProgress).then(function () {
          return self._loop(null, onInfo, onProgress);
        });
      }
      throw new Error('unexpected fastboot response ' + r.id);
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
