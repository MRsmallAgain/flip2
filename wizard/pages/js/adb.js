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

// Chrome device picker: TCL adb PIDs + generic ADB interface (not preloader 0e8d:2000).
var WEBUSB_PICK_FILTERS = [
  { vendorId: 0x1bbb, productId: 0x0167 },
  { vendorId: 0x1bbb, productId: 0x0c01 },
  { classCode: 255, subclassCode: 66, protocolCode: 1 }
];

function pickTclAdbDevice(list) {
  list = (list || []).filter(function (d) { return d.vendorId === 0x1bbb; });
  // Prefer adb-only PID (0c01) over MTP+adb composite (0167).
  var adbOnly = list.filter(function (d) { return d.productId === 0x0c01; });
  if (adbOnly.length >= 1) return adbOnly[0];
  var adbPids = [0x0167, 0x0c01];
  var adb = list.filter(function (d) { return adbPids.indexOf(d.productId) >= 0; });
  if (adb.length >= 1) return adb[0];
  list = list.filter(function (d) { return d.productId !== 0x2000; });
  if (list.length === 1) return list[0];
  return null;
}

function adbCmdName(cmd) {
  var b = new Uint8Array(4);
  new DataView(b.buffer).setUint32(0, cmd, true);
  return String.fromCharCode(b[0], b[1], b[2], b[3]);
}

var ADB = {
  device: null, out: null, inp: null, _ifNum: null,
  maxData: 256 * 1024,
  streams: {}, nextId: 1,
  tokensSeen: 0, pubSent: false,
  connectResolve: null,
  connectPendingAuth: false,
  authChain: null,
  _sendChain: null,             // tail of the serialized USB write queue
  _adbAlt: 0,
  log: function () {},          // main.js replaces this

  pickFromGranted: function () {
    var self = this;
    return navigator.usb.getDevices().then(function (list) {
      var d = pickTclAdbDevice(list);
      if (d) {
        self.device = d;
        return d;
      }
      var err = new Error('no granted WebUSB device');
      err.noGranted = true;
      throw err;
    });
  },

  pick: function () {
    var self = this;
    return navigator.usb.getDevices().then(function (list) {
      var d = pickTclAdbDevice(list);
      if (d) {
        self.device = d;
        return d;
      }
      return navigator.usb.requestDevice({ filters: WEBUSB_PICK_FILTERS }).then(function (dev) {
        self.device = dev;
        self.log('Picked USB ' + dev.vendorId.toString(16) + ':' + dev.productId.toString(16));
        return dev;
      });
    });
  },

  findAdbIface: function () {
    var cfgs = this.device.configurations;
    var self = this;
    for (var c = 0; c < cfgs.length; c++) {
      var ifaces = cfgs[c].interfaces;
      for (var i = 0; i < ifaces.length; i++) {
        var alts = ifaces[i].alternates;
        for (var a = 0; a < alts.length; a++) {
          var alt = alts[a];
          if (alt.interfaceClass === 255 && alt.interfaceSubclass === 66 && alt.interfaceProtocol === 1) {
            self._adbAlt = a;
            return ifaces[i].interfaceNumber;
          }
        }
      }
    }
    throw new Error('no ADB interface on this device');
  },

  CONNECT_TIMEOUT_MS: 55000,

  connect: function () {
    var self = this;
    this.tokensSeen = 0; this.pubSent = false;
    this.connectPendingAuth = false;
    this.authChain = null;
    this._loggedUsbIn = false;
    this.streams = {}; this.nextId = 1; this._acc = [];
    this._sendChain = null;
    this.out = null; this.inp = null;
    var handshake = this.device.close().catch(function () {}).then(function () {
      return self.device.open();
    }).then(function () {
      if (self.device.configuration === null) return self.device.selectConfiguration(1);
    }).then(function () {
      self._ifNum = self.findAdbIface();
      self.log('ADB interface if=' + self._ifNum + ' alt=' + self._adbAlt);
      return self.device.claimInterface(self._ifNum, false);
    }).then(function () {
      var altP = Promise.resolve();
      if (self._adbAlt > 0) {
        altP = self.device.selectAlternateInterface(self._ifNum, self._adbAlt);
      }
      return altP;
    }).then(function () {
      var iface = self.device.configuration.interfaces;
      self.out = null;
      self.inp = null;
      for (var i = 0; i < iface.length; i++) {
        if (iface[i].interfaceNumber !== self._ifNum) continue;
        var altIdx = self._adbAlt;
        if (altIdx >= iface[i].alternates.length) altIdx = 0;
        var eps = iface[i].alternates[altIdx].endpoints;
        for (var e = 0; e < eps.length; e++) {
          if (eps[e].type === 'bulk') {
            if (eps[e].direction === 'out') self.out = eps[e].endpointNumber;
            else self.inp = eps[e].endpointNumber;
          }
        }
      }
      if (self.out === null || self.inp === null) {
        throw new Error('no bulk endpoints on the ADB interface');
      }
      self.log('Bulk in=ep' + self.inp + ' out=ep' + self.out + ' — listen, then CNXN…');
      self._readLoop();
      return self._send(A_CNXN, 0x01000001, self.maxData, str2ab('host::\0'));
    }).then(function () {
      return self._waitConnected();
    });
    var timedOut = new Promise(function (_, reject) {
      setTimeout(function () {
        reject(new Error('timed out opening USB — try adb kill-server, replug, accept debugging on the phone'));
      }, self.CONNECT_TIMEOUT_MS);
    });
    return Promise.race([handshake, timedOut]).catch(function (e) {
      self._failConnect(e);
      throw e;
    });
  },

  _waitConnected: function () {
    var self = this;
    return new Promise(function (resolve, reject) {
      var t = setTimeout(function () {
        if (!self.connectResolve) return;
        self.connectResolve = null;
        reject(new Error('timed out waiting for ADB — accept the USB debugging prompt on the phone'));
      }, 45000);
      self.connectResolve = {
        resolve: function () { clearTimeout(t); resolve(); },
        reject: function (e) { clearTimeout(t); reject(e); }
      };
    });
  },

  // One transferOut pair at a time, each with its own deadline. A fire-and-
  // forget OKAY must never interleave with a half-written data frame, and a
  // halted endpoint must fail instead of hanging the whole send queue.
  _usbOut: function (buf, ms) {
    var p = this.device.transferOut(this.out, buf);
    return new Promise(function (resolve, reject) {
      var done = false;
      var t = setTimeout(function () {
        if (done) return;
        done = true;
        reject(new Error('USB write stalled for ' + (ms || 15000) + ' ms'));
      }, ms || 15000);
      p.then(function (r) {
        if (done) return;
        done = true;
        clearTimeout(t);
        resolve(r);
      }, function (e) {
        if (done) return;
        done = true;
        clearTimeout(t);
        reject(e);
      });
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
    var head = new Uint8Array(dv.buffer);
    var prev = this._sendChain || Promise.resolve();
    var next = prev.catch(function () {}).then(function () {
      return self._usbOut(head).then(function () {
        if (data && data.length) return self._usbOut(data);
      });
    });
    this._sendChain = next;
    return next;
  },

  _failConnect: function (err) {
    if (this.connectResolve) {
      var r = this.connectResolve;
      this.connectResolve = null;
      r.reject(err instanceof Error ? err : new Error(String(err)));
    }
  },

  _readLoop: function () {
    var self = this;
    return this.device.transferIn(this.inp, 65536).then(function (res) {
      if (res.status === 'ok' && res.data.byteLength > 0) {
        if (self.connectResolve && !self._loggedUsbIn) {
          self._loggedUsbIn = true;
          self.log('USB data from phone (' + res.data.byteLength + ' bytes) — adbd is talking.');
        }
        self._ingest(new Uint8Array(res.data.buffer, res.data.byteOffset, res.data.byteLength));
      }
      if (res.status === 'ok') return self._readLoop();
      self.log('FAIL: USB read status ' + res.status);
      self._failConnect(new Error('USB read failed (' + res.status + ') — unplug and try Connect phone again'));
    }).catch(function (e) {
      self.log('FAIL: USB read error: ' + e.message);
      self._failConnect(e);
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
      if (((cmd ^ 0xFFFFFFFF) >>> 0) !== magic) {
        this.log('FAIL: bad ADB magic on ' + adbCmdName(cmd));
        this._acc = [];
        return;
      }
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

  _sendPubkeyAndPrompt: function () {
    var self = this;
    if (self.pubSent) return Promise.resolve();
    self.pubSent = true;
    return self._send(A_AUTH, 3, 0, str2ab(ADBKEY.pubB64 + '\0')).then(function () {
      self.log('Sent RSA public key.');
      self.log('>>> Unlock the phone. Tap Allow on USB debugging (Always allow helps).');
      if (typeof window.flip2OnAdbAuthPrompt === 'function') {
        window.flip2OnAdbAuthPrompt();
      }
    });
  },

  _dispatch: function (cmd, arg0, arg1, data) {
    var self = this;
    if (cmd === A_CNXN) {
      this.log('← ' + adbCmdName(cmd) + ' a0=' + arg0 + ' a1=' + arg1 +
        (data && data.length ? ' data=' + data.length : ''));
    } else if (cmd === A_AUTH && arg0 === 1) {
      if (this.tokensSeen < 2) {
        this.log('← AUTH token (signing…) a1=' + arg1 +
          (data && data.length ? ' data=' + data.length : ''));
      }
    }
    if (cmd === A_CNXN) {
      this.maxData = Math.min(arg1, 256 * 1024);
      this.log('Connected. adbd max data ' + arg1 + ' bytes.');
      if (this.connectResolve) {
        var r = this.connectResolve;
        this.connectResolve = null;
        r.resolve();
      }
      return;
    }
    if (cmd === A_AUTH) {
      this.connectPendingAuth = true;
      if (arg0 !== 1) {
        this.log('FAIL: unexpected AUTH type ' + arg0 + ' (expected token=1)');
        return;
      }
      this.tokensSeen++;
      var token = data;
      var nth = this.tokensSeen;
      if (self.pubSent && nth >= 4) {
        self.log('Waiting for you to tap Allow on the phone (adbd still challenging…)…');
        return;
      }
      if (!self.pubSent && nth > 3) {
        if (nth === 4) {
          self.log('FAIL: AUTH loop before public key was accepted.');
          self.log('Try: Get ready → New browser ADB key, phone Revoke USB authorizations, replug, Connect.');
          self._failConnect(new Error('AUTH loop — use New browser ADB key + Revoke on phone'));
        }
        return;
      }
      var prev = this.authChain || Promise.resolve();
      this.authChain = prev.then(function () {
        if (nth === 1) {
          self.log('Signing with saved browser key…');
        } else if (nth === 2 && !self.pubSent) {
          self.log('Second token — sending public key if needed…');
        } else if (self.pubSent) {
          self.log('Signing (waiting for Allow on phone)…');
        }
        return ADBKEY.sign(token);
      }).then(function (sig) {
        return self._send(A_AUTH, 2, 0, new Uint8Array(sig));
      }).then(function () {
        if (nth === 1) {
          self.log('Sent signature; waiting for adbd…');
          return;
        }
        if (nth >= 2 && !self.pubSent) {
          return self._sendPubkeyAndPrompt();
        }
      }).catch(function (e) {
        self.log('FAIL: auth sign/send: ' + (e && e.message ? e.message : e));
        self._failConnect(e instanceof Error ? e : new Error(String(e)));
      });
      return;
    }
    if (cmd === A_CLSE && arg1 === 0) return; // adbd closing a dead stream
    var st = this.streams[arg1];
    if (!st) {
      if (this.connectResolve && (cmd === A_OKAY || cmd === A_CLSE)) {
        this.log('← ' + adbCmdName(cmd) + ' (handshake)');
      }
      return;
    }
    if (cmd === A_OKAY) {
      st.remoteId = arg0;
      st.credits = (st.credits || 0) + 1;
      st.openFail = null;            // opened: a later CLSE is a normal close
      if (st._writeWaiter) { var ww = st._writeWaiter; st._writeWaiter = null; ww(); }
      if (st.openWait) { st.openWait(); st.openWait = null; }
    } else if (cmd === A_WRTE) {
      st._buf.push(data);
      if (st.ondata) st.ondata(data);
      if (st._waiter) { var w = st._waiter; st._waiter = null; w(); }
      this._send(A_OKAY, st.id, st.remoteId, null);
    } else if (cmd === A_CLSE) {
      // A close before the OKAY means adbd refused the service; surface it now
      // instead of letting open() sit out its whole timeout.
      if (st.openFail && st.openWait) {
        var of = st.openFail;
        st.openFail = null;
        st.openWait = null;
        of('adbd closed ' + st.service + ' before it opened — service refused');
        return;
      }
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
    st.service = service;
    // openWait is installed before A_OPEN: adbd can answer OKAY before the
    // send even resolves, and a missed OKAY used to burn the whole timeout.
    return new Promise(function (resolve, reject) {
      var openMs = service === 'sync:' ? 20000 : 15000;
      var t = setTimeout(function () {
        delete self.streams[id];
        reject(new Error('timed out opening ' + service));
      }, openMs);
      st.openWait = function () { clearTimeout(t); resolve(st); };
      // adbd refuses a service with CLSE and no OKAY; report that as the reason
      // instead of waiting out the timeout and blaming the transport.
      st.openFail = function (msg) {
        clearTimeout(t);
        delete self.streams[id];
        reject(new Error(msg));
      };
      self._send(A_OPEN, id, 0, str2ab(service + '\0')).catch(function (e) {
        if (st.openFail) st.openFail('USB write failed opening ' + service + ': ' + ((e && e.message) || e));
      });
    });
  },

  // A stalled bulk endpoint makes every later transfer hang. Clearing the halt
  // is what lets a retry start over instead of reproducing the stall.
  clearStall: function () {
    var self = this;
    if (!self.device) return Promise.resolve();
    var ps = [];
    if (self.out != null) ps.push(self.device.clearHalt('out', self.out).catch(function () {}));
    if (self.inp != null) ps.push(self.device.clearHalt('in', self.inp).catch(function () {}));
    return Promise.all(ps);
  },

  // shell: streams every line to onLine and resolves when the remote closes.
  // opts.settleOn(line) ends the command on a marker line: the pty can outlive
  // the script (install.sh backgrounds the FlipMouse supervisor), and adbd then
  // never sends the close, so waiting for it hangs the caller forever.
  // opts.idleTimeoutMs turns a wedged shell into a prompt, readable failure.
  shell: function (cmd, onLine, opts) {
    var self = this;
    var settle = opts && typeof opts.settleOn === 'function' ? opts.settleOn : null;
    var idleMs = opts && opts.idleTimeoutMs ? opts.idleTimeoutMs : 0;
    return this.open('shell:' + cmd).then(function (st) {
      return new Promise(function (resolve) {
        var carry = '';
        var settled = false;
        var idleTimer = null;
        function finish() {
          if (settled) return;
          settled = true;
          if (idleTimer) { clearTimeout(idleTimer); idleTimer = null; }
          resolve();
          // Release the pty ourselves. adbd keeps it open until every child
          // holding it exits, which for a backgrounded daemon is never. The
          // CLSE write can fail if the device is already gone; that must not
          // surface as an unhandled rejection after we have resolved.
          if (!st.closed) {
            try {
              var p = st.close();
              if (p && typeof p.catch === 'function') p.catch(function () {});
            } catch (e) { /* already closed */ }
          }
        }
        function emit(line) {
          if (onLine) onLine(line);
          if (settle && settle(line)) finish();
        }
        // Device shells are ptys, so lines end \r\n. A trailing CR would make
        // an anchored match like /^DONE: install complete$/ never fire.
        function drain(final) {
          var nl;
          while (!settled && (nl = carry.indexOf('\n')) >= 0) {
            emit(carry.slice(0, nl).replace(/\r$/, ''));
            carry = carry.slice(nl + 1);
          }
          if (final && !settled && carry.length) {
            var tail = carry.replace(/\r$/, '');
            carry = '';
            emit(tail);
          }
        }
        function armIdle() {
          if (!idleMs || settled) return;
          if (idleTimer) clearTimeout(idleTimer);
          idleTimer = setTimeout(function () {
            if (onLine) onLine('(no output for ' + Math.round(idleMs / 1000) + ' s — giving up on this shell)');
            finish();
          }, idleMs);
        }
        st.ondata = function (chunk) {
          if (settled) return;
          armIdle();
          carry += new TextDecoder().decode(chunk);
          drain(false);
        };
        st.onclose = function () {
          drain(true);
          finish();
        };
        armIdle();
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
    var tries = 3;
    function attempt(n) {
      return self._pushFileOnce(remotePath, mode, data, onProgress).catch(function (e) {
        var msg = (e && e.message) || String(e);
        var transport = /timed out opening sync|before it opened|USB write stalled|sync stalled/i.test(msg);
        if (n > 1 && transport) {
          self.log('push ' + remotePath.split('/').pop() + ': ' + msg);
          self.log('clearing USB stall — retry ' + (tries - n + 2) + '/' + tries + '…');
          return self.clearStall()
            .then(function () { return new Promise(function (r) { setTimeout(r, 1200); }); })
            .then(function () { return attempt(n - 1); });
        }
        throw e;
      });
    }
    return attempt(tries);
  },

  _pushFileOnce: function (remotePath, mode, data, onProgress) {
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
