// Minimal ADB client over WebUSB. Talks to the classic ADB interface
// (class 0xFF / subclass 0x42 / protocol 1, bulk endpoints) so no hardcoded
// PID is needed — the phone exposes it on 1bbb:0167 and 1bbb:0c01 alike.
//
// Framing: 24-byte little-endian header
//   cmd | arg0 | arg1 | data_length | data_checksum (byte sum) | magic (cmd^0xFFFFFFFF)
// Streams are flow-controlled: one OKAY from the peer grants one WRTE.

// wire tags are little-endian uint32s: 'CNXN' = bytes 43 4E 58 4E = 0x4e584e43
var A_CNXN = 0x4e584e43, A_AUTH = 0x48545541, A_OPEN = 0x4e45504f,
    A_OKAY = 0x59414b4f, A_CLSE = 0x45534c43, A_WRTE = 0x45545257;

function str2ab(s) {
  var out = new Uint8Array(s.length);
  for (var i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 255;
  return out;
}

function concatArrays(arrs) {
  var total = 0, i;
  for (i = 0; i < arrs.length; i++) total += arrs[i].length;
  var out = new Uint8Array(total), off = 0;
  for (i = 0; i < arrs.length; i++) { out.set(arrs[i], off); off += arrs[i].length; }
  return out;
}

var ADB = {
  device: null, out: null, inp: null, _ifNum: null,
  maxData: 256 * 1024,
  streams: {}, nextId: 1,
  tokensSeen: 0, pubSent: false,
  connectResolve: null,
  log: function () {},          // main.js replaces this

  pick: function () {
    var self = this;
    return navigator.usb.requestDevice({ filters: [
      { classCode: 255, subclassCode: 66, protocolCode: 1 }
    ]}).then(function (d) { self.device = d; return d; });
  },

  findAdbIface: function () {
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
    throw new Error('no ADB interface on this device');
  },

  connect: function () {
    var self = this;
    this.tokensSeen = 0; this.pubSent = false;
    this.streams = {}; this.nextId = 1; this._acc = [];
    return this.device.open().then(function () {
      if (self.device.configuration === null) return self.device.selectConfiguration(1);
    }).then(function () {
      self._ifNum = self.findAdbIface();
      return self.device.claimInterface(self._ifNum, false);
    }).then(function () {
      var iface = self.device.configuration.interfaces;
      for (var i = 0; i < iface.length; i++) {
        if (iface[i].interfaceNumber !== self._ifNum) continue;
        var eps = iface[i].alternates[0].endpoints;
        for (var e = 0; e < eps.length; e++) {
          if (eps[e].type === 'bulk') {
            if (eps[e].direction === 'out') self.out = eps[e].endpointNumber;
            else self.inp = eps[e].endpointNumber;
          }
        }
      }
      if (self.out === null || self.inp === null) throw new Error('no bulk endpoints on the ADB interface');
      self.log('Claimed ADB interface, sending CNXN…');
      return self._send(A_CNXN, 0x01000001, self.maxData, str2ab('host::\0'));
    }).then(function () {
      self._readLoop();
      return self._waitConnected();
    });
  },

  _waitConnected: function () {
    var self = this;
    return new Promise(function (resolve, reject) {
      self.connectResolve = { resolve: resolve, reject: reject };
    });
  },

  _send: function (cmd, arg0, arg1, data) {
    var self = this;
    var dv = new DataView(new ArrayBuffer(24));
    var sum = 0, i;
    if (data) for (i = 0; i < data.length; i++) sum += data[i];
    dv.setUint32(0, cmd, true);
    dv.setUint32(4, arg0, true);
    dv.setUint32(8, arg1, true);
    dv.setUint32(12, data ? data.length : 0, true);
    dv.setUint32(16, sum >>> 0, true);
    dv.setUint32(20, (cmd ^ 0xFFFFFFFF) >>> 0, true);
    var p = this.device.transferOut(this.out, new Uint8Array(dv.buffer));
    if (data && data.length) {
      p = p.then(function () { return self.device.transferOut(self.out, data); });
    }
    return p;
  },

  _readLoop: function () {
    var self = this;
      return this.device.transferIn(this.inp, 65536).then(function (res) {
      if (res.status === 'ok' && res.data.byteLength > 0) {
        self._ingest(new Uint8Array(res.data.buffer, res.data.byteOffset, res.data.byteLength));
      }
      if (res.status === 'ok') return self._readLoop();
      self.log('FAIL: USB read status ' + res.status);
    }).catch(function (e) {
      self.log('FAIL: USB read error: ' + e.message);
    });
  },

  // Reassembles ADB packets from arbitrary USB transfer sizes. A packet is
  // 24-byte header plus data_length payload bytes; dispatch only when complete.
  _ingest: function (chunk) {
    if (!this._acc) this._acc = [];
    if (chunk && chunk.length) this._acc.push(chunk);
    while (true) {
      var total = 0, i;
      for (i = 0; i < this._acc.length; i++) total += this._acc[i].length;
      if (total < 24) return;
      // first 24 bytes -> header (may span chunks)
      var head = new Uint8Array(24), filled = 0, idx = 0;
      while (filled < 24) {
        var take = Math.min(24 - filled, this._acc[idx].length);
        head.set(this._acc[idx].subarray(0, take), filled);
        if (take === this._acc[idx].length) idx++; else this._acc[idx] = this._acc[idx].subarray(take);
        filled += take;
      }
      if (idx === this._acc.length) this._acc = []; else this._acc = this._acc.slice(idx);
      var dv = new DataView(head.buffer);
      var cmd = dv.getUint32(0, true);
      var arg0 = dv.getUint32(4, true), arg1 = dv.getUint32(8, true);
      var dlen = dv.getUint32(12, true);
      var magic = dv.getUint32(20, true);
      if (((cmd ^ 0xFFFFFFFF) >>> 0) !== magic) throw new Error('bad ADB magic');
      total = 0;
      for (i = 0; i < this._acc.length; i++) total += this._acc[i].length;
      if (total < dlen) { this._acc.unshift(head); return; }  // wait for the rest
      var payload = new Uint8Array(dlen), have = 0;
      while (have < dlen) {
        var c = this._acc.shift();
        var t = Math.min(dlen - have, c.length);
        payload.set(c.subarray(0, t), have);
        if (t < c.length) this._acc.unshift(c.subarray(t));
        have += t;
      }
      this._dispatch(cmd, arg0, arg1, payload);
    }
  },

  _dispatch: function (cmd, arg0, arg1, data) {
    var self = this;
    if (cmd === A_CNXN) {
      this.maxData = Math.min(arg1, 256 * 1024);
      this.log('Connected. adbd max data ' + arg1 + ' bytes.');
      if (this.connectResolve) { var r = this.connectResolve; this.connectResolve = null; r.resolve(); }
      return;
    }
    if (cmd === A_AUTH) {
      if (arg0 !== 1) { this.log('FAIL: unexpected AUTH type ' + arg0); return; }
      this.tokensSeen++;
      var token = data;
      ADBKEY.sign(token).then(function (sig) {
        return self._send(A_AUTH, 2, 0, new Uint8Array(sig));
      });
      if (this.tokensSeen === 1) {
        this.log('Phone sent an auth token — signing with the saved key…');
      } else if (!this.pubSent) {
        // signature was rejected: offer the public key, phone shows the prompt
        this.pubSent = true;
        this._send(A_AUTH, 3, 0, str2ab(ADBKEY.pubB64 + '\0'));
        this.log('Key not on the phone yet — sent the public key.');
        this.log('On the phone, accept the USB debugging prompt (tick "always allow").');
      }
      return;
    }
    if (cmd === A_CLSE && arg1 === 0) return; // adbd closing a dead stream
    var st = this.streams[arg1];
    if (!st) return;
    if (cmd === A_OKAY) {
      st.remoteId = arg0;
      st.credits = (st.credits || 0) + 1;
      if (st._writeWaiter) { var ww = st._writeWaiter; st._writeWaiter = null; ww(); }
      if (st.openWait) { st.openWait(); st.openWait = null; }
    } else if (cmd === A_WRTE) {
      st._buf.push(data);
      if (st.ondata) st.ondata(data);
      if (st._waiter) { var w = st._waiter; st._waiter = null; w(); }
      this._send(A_OKAY, st.id, st.remoteId, null);
    } else if (cmd === A_CLSE) {
      st.closed = true;
      if (st._waiter) { var w2 = st._waiter; st._waiter = null; w2(); }
      if (st.onclose) st.onclose();
    }
  },

  open: function (service) {
    var self = this;
    var id = this.nextId++;
    var st = {
      id: id, remoteId: 0, closed: false,
      credits: 0,                      // only the open OKAY grants a credit
      _buf: [], _waiter: null, _writeWaiter: null,
      ondata: null, onclose: null,
      read: function (n) {
        var self2 = this;
        var have = 0;
        this._buf.forEach(function (c) { have += c.length; });
        if (have < n) {
          if (this.closed) return Promise.reject(new Error('stream closed with ' + have + ' of ' + n + ' bytes pending'));
          return new Promise(function (resolve) {
            self2._waiter = function () { resolve(self2.read(n)); };
          });
        }
        var out = new Uint8Array(n), off = 0;
        while (off < n) {
          var c = self2._buf[0];
          var t = Math.min(n - off, c.length);
          out.set(c.subarray(0, t), off);
          if (t === c.length) self2._buf.shift(); else self2._buf[0] = c.subarray(t);
          off += t;
        }
        return Promise.resolve(out);
      },
      write: function (data) {
        var self2 = this;
        if (this.credits <= 0 && !this.closed) {
          return new Promise(function (resolve) {
            self2._writeWaiter = function () { resolve(self2.write(data)); };
          });
        }
        this.credits--;
        return self._send(A_WRTE, this.id, this.remoteId, data);
      },
      close: function () {
        this.closed = true;
        return self._send(A_CLSE, this.id, this.remoteId, null);
      }
    };
    this.streams[id] = st;
    return this._send(A_OPEN, id, 0, str2ab(service + '\0')).then(function () {
      return new Promise(function (resolve, reject) {
        var t = setTimeout(function () {
          delete self.streams[id];
          reject(new Error('timed out opening ' + service));
        }, 10000);
        st.openWait = function () { clearTimeout(t); resolve(st); };
      });
    });
  },

  // shell: resolves when the remote closes; every line goes to onLine.
  shell: function (cmd, onLine) {
    var self = this;
    return this.open('shell:' + cmd).then(function (st) {
      return new Promise(function (resolve) {
        var carry = '';
        st.ondata = function (chunk) {
          carry += new TextDecoder().decode(chunk);
          var nl;
          while ((nl = carry.indexOf('\n')) >= 0) {
            var line = carry.slice(0, nl); carry = carry.slice(nl + 1);
            if (onLine) onLine(line);
          }
        };
        st.onclose = function () {
          if (carry.length && onLine) onLine(carry);
          resolve();
        };
      });
    });
  },

  _syncFrame: function (id, data) {
    // id: 4-char string ('SEND' or 'DATA'), data: Uint8Array
    var b = str2ab(id);
    var out = new Uint8Array(8 + data.length);
    out[0] = b[0]; out[1] = b[1]; out[2] = b[2]; out[3] = b[3];
    new DataView(out.buffer).setUint32(4, data.length, true);
    out.set(data, 8);
    return out;
  },

  pushFile: function (remotePath, mode, data, onProgress) {
    var self = this;
    var mtime = Math.floor(Date.now() / 1000);
    // Stall watchdog: every completed write re-arms a 45 s timer; if a
    // transfer wedges or a write credit never arrives, reject with a clear
    // error instead of hanging the install step forever.
    var wTimer = null, wReject = null;
    var wFail = new Promise(function (resolve, reject) { wReject = reject; });
    var arm = function () {
      if (wTimer) clearTimeout(wTimer);
      wTimer = setTimeout(function () {
        wReject(new Error('sync stalled: no USB progress for 45 s'));
      }, 45000);
    };
    var disarm = function () { if (wTimer) clearTimeout(wTimer); wTimer = null; };
    arm();
    return Promise.race([this.open('sync:'), wFail]).then(function (st) {
      arm();
      var name = str2ab(remotePath + ',' + mode);
      var seq = st.write(self._syncFrame('SEND', name));
      var chunk = Math.min(64 * 1024, self.maxData), off = 0;
      while (off < data.length) {
        (function (start) {
          seq = seq.then(function () {
            arm();
            if (onProgress) onProgress(start, data.length);
            return st.write(self._syncFrame('DATA', data.subarray(start, start + chunk)));
          });
        })(off);
        off += chunk;
      }
      seq = seq.then(function () {
        arm();
        var out = new Uint8Array(8);
        out[0] = 0x44; out[1] = 0x4f; out[2] = 0x4e; out[3] = 0x45; // DONE
        new DataView(out.buffer).setUint32(4, mtime, true);
        return st.write(out);
      });
      var work = seq.then(function () { return self._syncStatus(st); })
        .then(function (res) { return st.close().then(function () { return res; }); });
      // The watchdog must cover the whole write chain, not just open(): a
      // stalled write credit otherwise hangs the push forever with no error.
      return Promise.race([work, wFail]);
    }).then(function (res) { disarm(); return res; },
            function (e) { disarm(); throw e; });
  },

  _syncStatus: function (st) {
    var self = this;
    return st.read(4).then(function (idb) {
      var id = String.fromCharCode(idb[0], idb[1], idb[2], idb[3]);
      if (id === 'OKAY') return 'OKAY';
      if (id === 'FAIL') {
        return st.read(4).then(function (lb) {
          var n = new DataView(lb.buffer, lb.byteOffset, 4).getUint32(0, true);
          return st.read(n).then(function (msg) {
            throw new Error('sync FAIL: ' + new TextDecoder().decode(msg));
          });
        });
      }
      throw new Error('unexpected sync status ' + id);
    });
  }
};
