// Web Serial port of autobooter-linux.py: watch for the MediaTek preloader
// (0e8d:2000), send the boot sequence at 115200 baud.
//
// A reply is success only when it is exactly one of:
//   8 bytes READYTOO
//   a prefix of READY + the boot sequence's last four characters, reversed
//     (FASTBOOT -> READYTOOB)
//   the 18-byte READYREADYTOOBTSAF returned by FASTBOOT on 2026-10-27
// Any other non-empty reply is a HARD STOP (the script's exit 99). Nothing
// flashes, and that reply must not be retried into unlock. An empty reply or
// a missing port keeps polling, 100 ms apart. A missed window never flashes
// anything; the user removes/reinserts the battery (or taps power) again.

var BOOTROM = {
  MTK_VID: 0x0e8d, MTK_PID: 0x2000,
  log: function () {},          // main.js replaces this

  _confirm: function (bootseq) {
    // python: b"READY" + bytes(bootseq[:-4:-1], "ascii")
    return 'READY' + bootseq.slice(-4).split('').reverse().join('');
  },

  // Prefix match is only the computed confirm. The other two successes are
  // exact FASTBOOT strings, so a shorter or longer reply still hard-stops.
  _accepted: function (text, bootseq) {
    var confirm = this._confirm(bootseq);
    if (text.substring(0, confirm.length) === confirm) return true;
    if (bootseq === 'FASTBOOT' && text === 'READYTOO') return true;
    if (bootseq === 'FASTBOOT' && text === 'READYREADYTOOBTSAF') return true;
    return false;
  },

  grantedPort: function () {
    return navigator.serial.getPorts().then(function (ports) {
      for (var i = 0; i < ports.length; i++) {
        var info = ports[i].getInfo();
        if (info.usbVendorId === BOOTROM.MTK_VID && info.usbProductId === BOOTROM.MTK_PID) {
          return ports[i];
        }
      }
      return null;
    });
  },

  requestPort: function () {
    // Chrome's chooser updates live: when the battery is pulled/reinserted
    // and the preloader enumerates, it appears in the open chooser and the
    // user clicks it inside the one-second window.
    return navigator.serial.requestPort({ filters: [
      { usbVendorId: BOOTROM.MTK_VID, usbProductId: BOOTROM.MTK_PID }
    ]});
  },

  // One handshake attempt, mirroring try_port(). Returns 'ok', 'empty',
  // or { hard: replyText } for the exit-99 case.
  tryPort: async function (port, bootseq) {
    try {
      await port.open({ baudRate: 115200 });
    } catch (e) {
      return 'empty';   // device not present / gone: the script's OSError path
    }
    try {
      var writer = port.writable.getWriter();
      await writer.write(new TextEncoder().encode(bootseq));
      writer.releaseLock();
      var reader = port.readable.getReader();
      var got = new Uint8Array(0);
      var deadline = Date.now() + 500;   // python timeout=0.5
      // 18 bytes is the live FASTBOOT reply. Stopping at 8 sees only READYREA.
      while (got.length < 18 && Date.now() < deadline) {
        var left = Math.max(deadline - Date.now(), 1);
        var timer = null;
        var res = await Promise.race([
          reader.read(),
          new Promise(function (r) { timer = setTimeout(function () { r({ timeout: true }); }, left); })
        ]);
        clearTimeout(timer);
        if (res.timeout) break;
        if (res.done) break;
        if (res.value && res.value.length) {
          var merged = new Uint8Array(got.length + res.value.length);
          merged.set(got, 0); merged.set(res.value, got.length);
          got = merged;
        }
      }
      try { await reader.cancel(); } catch (e2) {}
      try { reader.releaseLock(); } catch (e3) {}
      var text = '';
      for (var i = 0; i < got.length; i++) text += String.fromCharCode(got[i]);
      await port.close();
      if (this._accepted(text, bootseq)) return 'ok';
      if (text.length > 0) return { hard: text };
      return 'empty';
    } catch (e) {
      try { await port.close(); } catch (e2) {}
      return 'empty';
    }
  },

  // Runs until success, hard stop, or the 2-minute timeout. Resolves with
  // the serial port (kept only for symmetry — the fastboot step re-picks
  // the phone over WebUSB after it re-enumerates).
  boot: async function (bootseq) {
    var confirm = this._confirm(bootseq);
    this.log('Have USB attached, then remove/reinsert battery or tap power.');
    this.log('Waiting for MTK preloader (0e8d:2000)…');
    var port = await this.grantedPort();
    var deadline = Date.now() + 120000;
    while (Date.now() < deadline) {
      if (!port) {
        this.log('When the phone appears in the chooser, click "MediaTek USB Port (0e8d:2000)".');
        port = await this.requestPort();   // chooser stays open and updates live
      }
      var r = await this.tryPort(port, bootseq);
      if (r === 'ok') {
        this.log('Entered fastboot mode.');
        return port;
      }
      if (r && r.hard) {
        throw new Error('HARD STOP: preloader answered "' + r.hard +
          '" instead of READYTOO, a ' + confirm + ' prefix, or READYREADYTOOBTSAF.' +
          ' Nothing was flashed. Do not retry until you know why the phone answered.');
      }
      this.log('.');                        // missed window: keep polling
      await new Promise(function (res) { setTimeout(res, 100); });
      var g = await this.grantedPort();
      if (g) port = g;
    }
    throw new Error('Timed out waiting for the preloader. Try again: remove/reinsert' +
      ' the battery (or tap power) right after starting this step.');
  }
};
