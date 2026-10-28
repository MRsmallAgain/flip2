// Page wiring: step navigation, credit gate, download verification,
// udev text, USB connect, install/verify buttons, erase-gated rooting slice.
// Every module below is loaded by index.html before this one:
//   CATALOG/loadCatalog/sha256Hex, ADBKEY, ADB, PIPE, BOOTROM.

var ORDER = ['credit', 'download', 'udev', 'usb', 'install', 'verify'];
var REACHED = { credit: true };
var VERIFIED = {};            // catalog id -> ArrayBuffer of a hash-checked file
var INSTALL_SH = null;        // text of ../device/install.sh
var VERIFY_SH = null;         // text of ../device/verify.sh

function $(id) { return document.getElementById(id); }

function showStep(name) {
  var i = ORDER.indexOf(name), n;
  if (i >= 0) REACHED[name] = true;
  for (n = 0; n < ORDER.length; n++) {
    var el = $('step-' + ORDER[n]);
    if (el) el.classList.toggle('on', ORDER[n] === name);
  }
  var spans = document.querySelectorAll('#steps span[data-step]');
  for (n = 0; n < spans.length; n++) {
    var step = spans[n].getAttribute('data-step');
    var idx = ORDER.indexOf(step);
    spans[n].classList.toggle('on', step === name);
    spans[n].classList.toggle('done', idx >= 0 && idx < i);
  }
  // Slices outside the numbered step bar (rooting, return to factory) are
  // opened by id. Showing one must close the other, or two bodies stack.
  ['root', 'factory'].forEach(function (extra) {
    var el = $('step-' + extra);
    if (!el) return;
    if (name === extra) {
      el.hidden = false;
      el.classList.add('on');
    } else {
      el.classList.remove('on');
    }
  });
  window.scrollTo(0, 0);
}

function setStatus(id, text, cls) {
  var el = $(id);
  if (!el) return;
  el.textContent = text;
  el.className = 'status' + (cls ? ' ' + cls : '');
}

// Appends lines to a <pre class=log> and keeps the latest lines visible.
function makeLog(id) {
  var pre = $(id);
  return function (line) {
    pre.classList.remove('hidden');
    pre.textContent += line + '\n';
    pre.scrollTop = pre.scrollHeight;
  };
}

// ADB-internal messages go to every visible log sink; pipeline events are
// logged separately by the handlers, so nothing is lost when a step changes.
function adbLog(line) {
  ['usb-log', 'inst-log', 'ver-log', 'boot-log'].forEach(function (id) {
    var pre = $(id);
    if (pre && !pre.classList.contains('hidden')) {
      pre.textContent += line + '\n';
      pre.scrollTop = pre.scrollHeight;
    }
  });
}

// --- 1 · credit gate --------------------------------------------------------

function buildCreditTable() {
  var tbody = $('credit-table').tBodies[0];
  CATALOG.list.forEach(function (f) {
    var tr = document.createElement('tr');
    var td0 = document.createElement('td');
    td0.appendChild(document.createTextNode(f.file));
    var td1 = document.createElement('td');
    td1.textContent = f.author;
    var td2 = document.createElement('td');
    td2.textContent = f.license;
    var td3 = document.createElement('td');
    var a = document.createElement('a');
    a.href = f.url;
    a.textContent = f.upstream;
    a.target = '_blank';
    a.rel = 'noreferrer';
    td3.appendChild(a);
    tr.appendChild(td0); tr.appendChild(td1); tr.appendChild(td2); tr.appendChild(td3);
    tbody.appendChild(tr);
  });
}

function initGate() {
  var input = $('gate-input'), btn = $('gate-btn');
  input.addEventListener('input', function () {
    btn.disabled = input.value.trim().toLowerCase() !== 'yes';
  });
  btn.addEventListener('click', function () {
    setStatus('gate-msg', 'Downloads allowed. Go to Files.', 'ok');
    showStep('download');
  });
}

// --- 2 · downloads -----------------------------------------------------------

function fmtSize(n) {
  if (n >= 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + ' MiB';
  return Math.round(n / 1024) + ' KiB';
}

function buildDownloadTable() {
  var tbody = $('dl-table').tBodies[0];
  CATALOG.list.forEach(function (f) {
    var tr = document.createElement('tr');
    var td0 = document.createElement('td'); td0.textContent = f.file;
    var td1 = document.createElement('td'); td1.textContent = fmtSize(f.size);
    var td2 = document.createElement('td'); td2.textContent = f.author;
    var td3 = document.createElement('td');
    if (window.FLIP2_NATIVE && window.FLIP2_NATIVE.downloadFile) {
      // In the app, fetch it here: the old external link did nothing useful.
      var b = document.createElement('button');
      b.className = 'small ghost';
      b.textContent = 'get here';
      b.addEventListener('click', function () { fetchOne(f.id, b); });
      td3.appendChild(b);
    } else {
      var a = document.createElement('a');
      a.href = f.url; a.textContent = 'download'; a.target = '_blank'; a.rel = 'noreferrer';
      td3.appendChild(a);
    }
    var td4 = document.createElement('td'); td4.textContent = '—';
    td4.setAttribute('data-status', f.id);
    tr.appendChild(td0); tr.appendChild(td1); tr.appendChild(td2); tr.appendChild(td3); tr.appendChild(td4);
    tbody.appendChild(tr);
  });
}

function setRow(id, text, cls) {
  var td = document.querySelector('[data-status="' + id + '"]');
  if (!td) return;
  td.textContent = text;
  td.className = cls || '';
}

function badLine(msg) {
  var div = document.createElement('div');
  div.textContent = 'BAD: ' + msg;
  div.className = 'bad';
  $('dl-results').appendChild(div);
}

function refreshDownloadGate() {
  var missing = CATALOG.list.filter(function (f) { return !VERIFIED[f.id]; });
  if (missing.length === 0) {
    setStatus('dl-msg', 'All ' + CATALOG.list.length + ' files verified.', 'ok');
    $('dl-next').disabled = false;
  } else {
    setStatus('dl-msg', missing.length + ' of ' + CATALOG.list.length +
      ' still needed: ' + missing.map(function (f) { return f.file; }).join(', '), 'wait');
    $('dl-next').disabled = true;
  }
  return missing;
}

// A candidate the companion handed over — already on disk, or fetched here.
// It is kept only if its bytes hash to the pinned value for that catalog id.
function acceptBytes(id, bytes) {
  var f = CATALOG.byId[id];
  if (!f) return Promise.resolve({ ok: false, msg: id + ' is not in the catalog' });
  var view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  return sha256Hex(view).then(function (hex) {
    if (hex !== f.sha256) {
      return { ok: false, msg: f.file + ': SHA-256 does not match the pinned value' };
    }
    if (view.byteLength !== f.size) {
      return { ok: false, msg: f.file + ': ' + view.byteLength + ' bytes, expected ' + f.size };
    }
    VERIFIED[id] = view.buffer.slice(view.byteOffset, view.byteOffset + view.byteLength);
    return { ok: true, msg: f.file };
  });
}

function cleanErr(e) {
  var m = (e && e.message) || String(e);
  return m.replace(/^Error invoking remote method '[^']+': (Error: )?/, '');
}

function fetchOne(id, btn) {
  if (btn) btn.disabled = true;
  if (!VERIFIED[id]) setRow(id, 'fetching…', '');
  return window.FLIP2_NATIVE.downloadFile(id).then(function (r) {
    return acceptBytes(id, r.bytes);
  }).then(function (res) {
    setRow(id, res.ok ? 'verified' : 'FAILED', res.ok ? 'ok' : 'bad');
    if (!res.ok) badLine(res.msg);
    refreshDownloadGate();
    return res;
  }).catch(function (e) {
    setRow(id, 'FAILED', 'bad');
    badLine(id + ': ' + cleanErr(e));
    refreshDownloadGate();
    return { ok: false, msg: cleanErr(e) };
  }).then(function (res) {
    if (btn) btn.disabled = false;
    return res;
  });
}

// Two folders can hold the same file name and only one be the right build, so
// every candidate is hashed in turn; a stale copy must not hide a good one.
// Report failure only when none of the copies matches the pin.
function tryCandidates(id, list) {
  var i = 0;
  function next() {
    if (VERIFIED[id]) return Promise.resolve({ ok: true });
    if (i >= list.length) {
      return Promise.resolve({
        ok: false,
        msg: id + ': ' + list.length + ' local cop' + (list.length === 1 ? 'y' : 'ies') +
          ' found, none matched the pinned SHA-256',
      });
    }
    var n = i++;
    return window.FLIP2_NATIVE.readLocal(id, n).then(function (r) {
      return acceptBytes(id, r.bytes);
    }).catch(function (e) {
      return { ok: false, msg: cleanErr(e) };
    }).then(function (res) {
      return res.ok ? res : next();
    });
  }
  return next();
}

function useLocalFiles() {
  var btn = $('dl-local-btn');
  btn.disabled = true;
  setStatus('dl-msg', 'looking for copies already on this PC…', 'wait');
  return window.FLIP2_NATIVE.localFiles().then(function (found) {
    var ids = CATALOG.list.map(function (f) { return f.id; })
      .filter(function (id) { return found[id] && found[id].length && !VERIFIED[id]; });
    if (!ids.length) {
      setStatus('dl-msg', 'No new copies found on this PC. Use Download all here, or choose files you downloaded.', 'wait');
      return;
    }
    setStatus('dl-msg', 'checking ' + ids.length + ' file(s) already here…', 'wait');
    var seq = Promise.resolve();
    ids.forEach(function (id) {
      seq = seq.then(function () {
        return tryCandidates(id, found[id]).then(function (res) {
          setRow(id, res.ok ? 'verified' : 'FAILED', res.ok ? 'ok' : 'bad');
          if (!res.ok) badLine(res.msg);
        });
      });
    });
    return seq.then(refreshDownloadGate);
  }).catch(function (e) {
    setStatus('dl-msg', 'could not read the local copies: ' + cleanErr(e), 'bad');
  }).then(function () { btn.disabled = false; });
}

function downloadAll() {
  var btn = $('dl-fetch-btn');
  btn.disabled = true;
  var todo = CATALOG.list.filter(function (f) { return !VERIFIED[f.id]; })
    .map(function (f) { return f.id; });
  if (!todo.length) {
    refreshDownloadGate();
    btn.disabled = false;
    return;
  }
  var done = 0;
  var seq = Promise.resolve();
  todo.forEach(function (id) {
    seq = seq.then(function () {
      setStatus('dl-msg', 'downloading ' + (done + 1) + ' of ' + todo.length + '…', 'wait');
      return fetchOne(id, null);
    }).then(function () { done += 1; });
  });
  seq.then(function () {
    var missing = refreshDownloadGate();
    if (missing.length) {
      setStatus('dl-msg', missing.length + ' could not be downloaded. A server may be down — try again, or choose files you got another way.', 'bad');
    }
  }).then(function () { btn.disabled = false; });
}

function checkDownloads(picked) {
  var seq = Promise.resolve();
  var results = [];
  picked.forEach(function (file) {
    seq = seq.then(function () {
      return file.arrayBuffer().then(function (buf) {
        return sha256Hex(buf).then(function (hex) {
          var match = null;
          for (var i = 0; i < CATALOG.list.length; i++) {
            if (CATALOG.list[i].sha256 === hex) { match = CATALOG.list[i]; break; }
          }
          if (match) {
            if (buf.byteLength !== match.size) {
              results.push({ id: match.id, ok: false, msg: match.file +
                ': hash matches but size is ' + buf.byteLength + ' B, expected ' + match.size });
              return;
            }
            VERIFIED[match.id] = buf;
            results.push({ id: match.id, ok: true, msg: match.file });
          } else {
            results.push({ id: null, ok: false, msg: file.name + ' — no catalog entry has this SHA-256' });
          }
        });
      });
    });
  });
  return seq.then(function () {
    results.forEach(function (r) {
      if (r.id) setRow(r.id, r.ok ? 'verified' : 'FAILED', r.ok ? 'ok' : 'bad');
      if (!r.ok) badLine(r.msg);
    });
    refreshDownloadGate();
  }).catch(function (e) {
    setStatus('dl-msg', 'could not read a picked file: ' + e.message, 'bad');
  });
}

function initDownloads() {
  buildDownloadTable();
  // Companion only: these bypass the browser download detour entirely.
  if (window.FLIP2_NATIVE && window.FLIP2_NATIVE.localFiles) {
    $('dl-local-btn').classList.remove('hidden');
    $('dl-fetch-btn').classList.remove('hidden');
    $('dl-local-btn').addEventListener('click', useLocalFiles);
    $('dl-fetch-btn').addEventListener('click', downloadAll);
    // Probe quietly so the user sees what is already here instead of
    // wondering whether the button will find anything.
    window.FLIP2_NATIVE.localFiles().then(function (found) {
      var n = CATALOG.list.filter(function (f) { return found[f.id]; }).length;
      if (n > 0 && !Object.keys(VERIFIED).length) {
        setStatus('dl-msg', n + ' of ' + CATALOG.list.length +
          ' files are already on this PC. Press "Use files already on this PC".', 'wait');
      }
    }).catch(function () {});
  }
  $('dl-pick-btn').addEventListener('click', function () { $('dl-pick').click(); });
  $('dl-pick').addEventListener('change', function () {
    var files = Array.prototype.slice.call(this.files);
    this.value = '';
    if (!files.length) return;
    setStatus('dl-msg', 'checking ' + files.length + ' file(s)…', 'wait');
    checkDownloads(files);
  });
  $('dl-next').addEventListener('click', function () { showStep('udev'); });
}

// --- 3 · udev -----------------------------------------------------------------

function initUdev() {
  fetch('../51-android-flip2-adb.rules').then(function (r) {
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return r.text();
  }).then(function (text) {
    $('udev-file').textContent = text;
  }).catch(function (e) {
    $('udev-file').textContent = 'could not load the rules file: ' + e.message;
  });
  $('udev-done').addEventListener('click', function () { showStep('usb'); });
  // Companion app only: one-click install via the shell (pkexec). Hidden in
  // a plain browser, where FLIP2_NATIVE does not exist.
  if (window.FLIP2_NATIVE) {
    var nbtn = $('udev-native'), nmsg = $('udev-native-msg');
    nbtn.classList.remove('hidden');
    nbtn.addEventListener('click', function () {
      nbtn.disabled = true;
      nmsg.textContent = 'waiting for the password prompt…';
      nmsg.className = 'status wait';
      window.FLIP2_NATIVE.udevStatus().then(function (st) {
        if (st.installed) return { ok: true, message: 'Rules are already in place.' };
        return window.FLIP2_NATIVE.installUdev();
      }).then(function (r) {
        nmsg.textContent = r.message;
        nmsg.className = 'status ' + (r.ok ? 'ok' : 'bad');
      }).catch(function (e) {
        nmsg.textContent = e.message;
        nmsg.className = 'status bad';
      }).then(function () { nbtn.disabled = false; });
    });
  }
}

// --- 4 · connect ----------------------------------------------------------------

// The phone's USB interface is exclusive: when another adb server already holds
// it, claiming fails with a bare DOMException that names a browser API and says
// nothing a person can act on. Say which process to stop instead.
function usbError(e) {
  var m = (e && e.message) || String(e);
  if (/claimInterface/i.test(m) || /Unable to claim/i.test(m)) {
    return 'Another program is using the phone: the adb server on this computer. ' +
      'Run "adb kill-server" in a terminal, replug the phone, and press Pick phone again.';
  }
  return m;
}

function initUsb() {
  $('usb-btn').addEventListener('click', function () {
    if (!navigator.usb) {
      setStatus('usb-msg', 'This browser has no WebUSB. Use Chrome on Linux.', 'bad');
      return;
    }
    setStatus('usb-msg', 'picking…', 'wait');
    ADBKEY.load().then(function () {
      return ADB.pick();
    }).then(function () {
      $('usb-log').classList.remove('hidden');
      ADB.log = adbLog;
      return ADB.connect();
    }).then(function () {
      setStatus('usb-msg', 'Connected over ADB.', 'ok');
      $('usb-next').disabled = false;
    }).catch(function (e) {
      setStatus('usb-msg', usbError(e), 'bad');
    });
  });
  $('usb-next').addEventListener('click', function () { showStep('install'); });
}

// --- 5 · install ------------------------------------------------------------------

function initInstall() {
  $('inst-btn').addEventListener('click', function () {
    var files = {};
    ['installer-full', 'tagdrawer', 'forkgram', 'intertune', 'bouncy',
      'materialfiles', 'whisper-tiny', 'vosk-en', 'vosk-uk'].forEach(function (id) {
      if (VERIFIED[id]) files[id] = new Uint8Array(VERIFIED[id]);
    });
    this.disabled = true;
    setStatus('inst-msg', 'building push set…', 'wait');
    var log = makeLog('inst-log');
    var pushSet;
    try {
      pushSet = PIPE.buildPushSet(files);
    } catch (e) {
      setStatus('inst-msg', e.message, 'bad');
      $('inst-retry').classList.remove('hidden');
      return;
    }
    setStatus('inst-msg', 'pushing ' + Object.keys(pushSet).length + ' files…', 'wait');
    PIPE.pushAndInstall(pushSet, INSTALL_SH, log).then(function () {
      return PIPE.cleanup(log);
    }).then(function () {
      setStatus('inst-msg', 'Install complete.', 'ok');
      $('inst-next').disabled = false;
    }).catch(function (e) {
      setStatus('inst-msg', e.message, 'bad');
      $('inst-retry').classList.remove('hidden');
    });
  });
  $('inst-retry').addEventListener('click', function () {
    this.classList.add('hidden');
    setStatus('inst-msg', '', '');
    $('inst-btn').disabled = false;
  });
  $('inst-next').addEventListener('click', function () { showStep('verify'); });
}

// --- 6 · verify ---------------------------------------------------------------------

function initVerify() {
  function runVerify() {
    $('ver-btn').disabled = true;
    $('ver-recheck').classList.add('hidden');
    setStatus('ver-msg', 'running verify.sh…', 'wait');
    var log = makeLog('ver-log');
    PIPE.verify(VERIFY_SH, log).then(function () {
      setStatus('ver-msg', 'All checks passed.', 'ok');
    }).catch(function (e) {
      setStatus('ver-msg', e.message, 'bad');
      $('ver-recheck').classList.remove('hidden');
    }).then(function () {
      $('ver-btn').disabled = false;
    });
  }
  $('ver-btn').addEventListener('click', runVerify);
  $('ver-recheck').addEventListener('click', runVerify);
}

// --- rooting slice (erase-gated, not on the step bar) ----------------------------------

// Plain-language view of the mode the phone is in, from the companion's
// read-only USB scan. The same 120 s window BOOTROM.boot waits for.
var WATCH_MS = 120000;

// A transfer that stopped halfway leaves the bootloader waiting for a payload
// that will never arrive. It still shows up on USB exactly like a healthy one,
// so the only way to tell is that it stops answering. Nothing was written, and
// only a power cycle clears it.
var silentWake = false;

var PHONE_VIEW = {
  android:  { box: 'live',   cls: 'ok',   label: 'Android is running',
              hint: 'Nothing to do yet. Take the battery out and put it back in.' },
  absent:   { box: 'live',   cls: 'wait', label: 'phone is off USB',
              hint: 'Expected for a moment right after the battery comes out. This is the good sign.' },
  preloader:{ box: 'caught', cls: 'ok',   label: 'startup mode caught',
              hint: 'Keep the cable in — the wizard is taking over now.' },
  fastboot: { box: 'caught', cls: 'ok',   label: 'flashing mode',
              hint: 'The hard part is done. Continue below.' },
  bootrom:  { box: 'bad',    cls: 'bad',  label: 'wrong startup mode',
              hint: 'Do not continue. Unplug the cable, put the battery back, and start over.' },
  stuck:    { box: 'bad',    cls: 'bad',  label: 'not responding normally',
              hint: 'Hold the power button for about 10 seconds until it restarts, then let Android come up.' },
  conflict: { box: 'bad',    cls: 'bad',  label: 'two phone modes at once',
              hint: 'Unplug any other phone, then wait for this panel to settle.' },
  unknown:  { box: 'bad',    cls: 'bad',  label: 'cannot read USB',
              hint: 'The companion could not list USB devices.' }
};

// What to tell someone when the phone is not in a state the wizard can use.
// Each entry is a numbered list of physical actions; the panel replaces itself
// the moment the phone answers, so nobody has to know what to look for.
var WAKE = {
  stuck: {
    title: 'Wake the phone first',
    hint: 'The phone is in a mode nothing can use. This takes about a minute.',
    steps: [
      'Hold the phone\u2019s power button down for about 10 seconds, until the screen goes dark.',
      'Let go, then wait for the home screen to come back.',
      'Leave the USB cable plugged in. This panel changes on its own when the phone is ready.'
    ]
  },
  bootrom: {
    title: 'Phone is in the wrong mode',
    hint: 'Nothing was written to the phone. Get it back to Android before continuing.',
    steps: [
      'Unplug the USB cable.',
      'Hold the power button for about 10 seconds, until the screen goes dark.',
      'Plug the cable back in and wait for the home screen. This panel changes on its own.'
    ]
  },
  silent: {
    title: 'The phone stopped answering',
    hint: 'Nothing was written to the phone. A power cycle gets it back — then start the catch step again.',
    steps: [
      'Unplug the USB cable.',
      'Take the battery out, wait a moment, and put it back in.',
      'Leave the cable out until the phone has finished starting normally.',
      'Plug the cable back in and wait for this panel to say the phone is running Android.',
      'Then press Start watching again and repeat the catch step.'
    ]
  },
  conflict: {
    title: 'Two phones on USB',
    hint: 'The wizard cannot tell which device to use.',
    steps: [
      'Unplug every other phone or USB device.',
      'Leave this Flip 2\u2019s cable plugged in. This panel changes on its own.'
    ]
  },
  unknown: {
    title: 'Cannot see the phone',
    hint: 'The companion could not read the USB device list.',
    steps: [
      'Unplug the phone and plug it back in.',
      'If this does not clear, restart the Companion app.'
    ]
  }
};

var watching = false;
// Which wake card is on screen. The state poller runs once a second, and
// rebuilding the list every tick would fight the user's scroll and flash the
// panel; only rewrite it when the card actually changes.
var wakeShown = null;

// Only one stage of the rooting step is ever on screen. Showing catch, flash
// and finish together was the reason it was hard to know what to read.
var stageName = null;

// One place decides which part of the rooting step is on screen: the current
// stage, unless a wake card is up. Splitting this out means a wake card can
// take over from any stage and hand control straight back when it clears,
// instead of leaving two panels side by side to compete for attention.
function renderStage() {
  var woken = !$('wake-box').classList.contains('hidden');
  var name = stageName || 'catch';
  $('stage-catch').classList.toggle('hidden', woken || name !== 'catch');
  $('stage-flash').classList.toggle('hidden', woken || name !== 'flash');
  $('after-box').classList.toggle('hidden', woken || name !== 'done');
  // Reloading the page clears VERIFIED, so someone can arrive at the install
  // stage with nothing checked and only find out when the button refuses. Say
  // it up front instead, pointing back at the file step that sets it.
  $('fb-need').classList.toggle('hidden', name !== 'flash' || !!VERIFIED['neutron']);
}

function setStage(name) {
  stageName = name;
  renderStage();
}

function showWake(mode) {
  var w = WAKE[mode];
  $('wake-box').classList.remove('hidden');
  renderStage();
  // Listening cannot succeed from here, so do not offer the button.
  $('boot-btn').disabled = true;
  if (wakeShown === mode) return;
  wakeShown = mode;
  $('wake-title').textContent = w.title;
  $('wake-title').className = 'status bad';
  $('wake-hint').textContent = w.hint;
  var ol = $('wake-steps');
  ol.textContent = '';
  w.steps.forEach(function (text) {
    var li = document.createElement('li');
    li.textContent = text;
    ol.appendChild(li);
  });
}

function hideWake() {
  $('wake-box').classList.add('hidden');
  wakeShown = null;
  renderStage();
  $('boot-btn').disabled = watching;
}

// The phone passes through Android, off-USB, preloader and fastboot in about a
// second during the handover, and each of those used to repaint the status line
// on its own tick. Hold a mode for a moment before publishing it so the label
// on screen is still true when someone reads it.
var MODE_SETTLE_MS = 900;
var shownMode = null, pendingMode = null, pendingSince = 0;

function showPhoneState(state) {
  var mode = (state && state.mode) || 'unknown';
  var now = Date.now();
  if (mode !== pendingMode) { pendingMode = mode; pendingSince = now; }
  if (mode !== shownMode && now - pendingSince < MODE_SETTLE_MS) return;
  if (mode === shownMode) return;
  shownMode = mode;

  // Leaving fastboot means the power cycle happened, so the next fastboot is a
  // fresh one. Clear the flag rather than keeping it for the rest of the session.
  if (mode !== 'fastboot') silentWake = false;

  // Once the phone has been caught, stage 2 has its own status line and this
  // panel is off screen. Do not narrate USB modes for a stage nobody can see.
  if (stageName === 'flash' || stageName === 'done') return;

  var view = PHONE_VIEW[mode] || PHONE_VIEW.unknown;
  var box = $('now-box');
  box.className = 'now' + (view.box ? ' ' + view.box : '');
  setStatus('phone-now', view.label, view.cls);
  $('phone-hint').textContent = view.hint;
  // A wedged bootloader is still on USB looking exactly like a healthy one; the
  // only difference is that it stopped answering. Once a command has timed out,
  // show the power-cycle card instead of telling anyone it is ready to flash.
  if (silentWake && mode === 'fastboot') {
    showWake('silent');
    return;
  }
  if (WAKE[mode]) showWake(mode); else hideWake();
  if (mode === 'fastboot') showFastbootSection();
}

// The preloader repeats READY while it hands over, so the confirm read can
// finish on a reply the page rejects even though the phone has already jumped
// to flashing mode. USB is the authority: if the phone is in fastboot, open
// the next stage and retire any stale listening error instead of stranding the
// user on it.
function showFastbootSection() {
  if (stageName === 'flash' || stageName === 'done') return;
  watching = false;
  stopWatchClock(true);
  setStage('flash');
  setStatus('boot-msg', 'The phone is in flashing mode.', 'ok');
  // Whatever went wrong before the power cycle no longer describes this phone.
  setStatus('fb-msg', '', '');
  $('boot-btn').disabled = true;
}

function pollPhoneState() {
  if (!window.FLIP2_NATIVE || !window.FLIP2_NATIVE.phoneState) {
    setStatus('phone-now', 'not visible in a plain browser', 'wait');
    $('phone-hint').textContent = 'Open this page in the Flip 2 Companion app to see the live phone state.';
    hideWake();
    return;
  }
  window.FLIP2_NATIVE.phoneState().then(showPhoneState).catch(function () {
    setStatus('phone-now', 'cannot read USB', 'bad');
    hideWake();
  });
}

var watchTimer = null;
var phonePoller = null;

function startWatchClock() {
  var started = Date.now();
  stopWatchClock();
  var bar = $('boot-bar'), count = $('boot-count');
  bar.classList.remove('run');
  bar.style.width = '0%';
  count.classList.remove('hidden');
  watchTimer = setInterval(function () {
    var left = Math.max(WATCH_MS - (Date.now() - started), 0);
    bar.style.width = Math.round((WATCH_MS - left) / WATCH_MS * 100) + '%';
    count.textContent = 'Listening for the phone — ' + Math.ceil(left / 1000) +
      ' s left. ' + (left > 0 ? 'Take the battery out and put it back in now.' : '');
  }, 200);
}

function stopWatchClock(caught) {
  if (watchTimer) { clearInterval(watchTimer); watchTimer = null; }
  var bar = $('boot-bar'), count = $('boot-count');
  if (caught) {
    bar.classList.add('run');
    bar.style.width = '100%';
    count.textContent = 'Caught it.';
  } else {
    count.textContent = '';
    count.classList.add('hidden');
    bar.style.width = '0%';
  }
}

function initRoot() {
  $('root-link').addEventListener('click', function (ev) {
    ev.preventDefault();
    showStep('root');
    pollPhoneState();
  });
  $('erase-input').addEventListener('input', function () {
    $('root-open').disabled = this.value.trim() !== 'erase';
  });
  $('root-open').addEventListener('click', function () {
    $('root-body').classList.remove('hidden');
    $('wake-box').classList.add('hidden');
    $('boot-btn').disabled = false;
    // A fresh run starts at stage 1 with clean status lines. Anything left over
    // from an earlier attempt — a red failure, a "Caught it" from last time —
    // describes a phone that is no longer where it was.
    stageName = null;
    wakeShown = null;
    shownMode = null;
    pendingMode = null;
    silentWake = false;
    watching = false;
    setStatus('boot-msg', '', '');
    setStatus('fb-msg', '', '');
    setStatus('phone-now', 'checking…', '');
    $('phone-hint').textContent = '';
    $('boot-count').textContent = '';
    $('boot-count').classList.add('hidden');
    $('boot-bar').classList.remove('run');
    $('boot-bar').style.width = '0%';
    $('boot-log').textContent = '';
    $('boot-log').classList.add('hidden');
    $('fb-log').textContent = '';
    $('fb-log').classList.add('hidden');
    setStage('catch');
    pollPhoneState();
    if (!phonePoller) phonePoller = setInterval(pollPhoneState, 1000);
  });
  $('boot-btn').addEventListener('click', function () {
    if (!navigator.serial) {
      setStatus('boot-msg', 'This browser cannot talk to USB serial. Use the Companion app.', 'bad');
      return;
    }
    watching = true;
    this.disabled = true;
    setStatus('boot-msg', 'listening…', 'wait');
    startWatchClock();
    BOOTROM.log = makeLog('boot-log');
    BOOTROM.boot('FASTBOOT').then(function () {
      watching = false;
      stopWatchClock(true);
      setStatus('boot-msg', 'Caught the phone. It is in flashing mode.', 'ok');
      setStage('flash');
    }).catch(function (e) {
      watching = false;
      stopWatchClock(false);
      $('boot-log').classList.remove('hidden');
      $('boot-log').textContent += e.message + '\n';
      if (e.message.indexOf('HARD STOP') === 0) {
        setStatus('boot-msg', 'Stopped: the phone answered unexpectedly. Nothing was written. Do not retry.', 'bad');
        return;
      }
      setStatus('boot-msg', 'Did not catch it. Try again — take the battery out and put it back in.', 'bad');
      $('boot-btn').disabled = false;
    });
  });
}

// --- fastboot (erase-gated slice, step 2 after the bootrom handshake) ---

function initFastboot() {
  var log = makeLog('fb-log');
  FASTBOOT.log = log;
  function stage(name) {
    ['fb-pick', 'fb-unlock', 'fb-flash', 'fb-reboot'].forEach(function (id) {
      $(id).disabled = true;
    });
    $(name).disabled = false;
  }
  $('fb-pick').addEventListener('click', function () {
    if (!navigator.usb) {
      setStatus('fb-msg', 'This browser has no WebUSB. Use Chrome on Linux.', 'bad');
      return;
    }
    setStatus('fb-msg', 'connecting…', 'wait');
    FASTBOOT.pick().then(function () {
      return FASTBOOT.connect();
    }).then(function () {
      // Read the phone's identity and lock state before offering any write.
      // The serial is shown, never assumed, so a second phone on the bus cannot
      // be flashed by mistake.
      return FASTBOOT.getvar('serialno').then(function (serial) {
        var s = String(serial || '').trim();
        log('serialno: ' + (s || '(none reported)'));
        return FASTBOOT.getvar('unlocked').then(function (u) {
          var unlocked = /yes/i.test(String(u || ''));
          log('unlocked: ' + (unlocked ? 'yes' : 'no'));
          if (unlocked) {
            setStatus('fb-msg', 'Connected. This phone is already unlocked, so it does not need to be erased again — go straight to installing the boot image.', 'ok');
            stage('fb-flash');
            return;
          }
          setStatus('fb-msg', 'Connected. Unlock next: the phone will ask you to confirm on its keypad.', 'ok');
          stage('fb-unlock');
        });
      });
    }).catch(function (e) {
      setStatus('fb-msg', e.message, 'bad');
      stage('fb-pick');
      // A timed-out command means the bootloader is still there but no longer
      // reading. Only a power cycle clears that, so show the card that says so
      // instead of leaving a bare error on the line.
      if (e && e.stopped) {
        silentWake = true;
        showWake('silent');
      }
    });
  });
  $('fb-unlock').addEventListener('click', function () {
    setStatus('fb-msg', 'Confirm on the phone keypad…', 'wait');
    FASTBOOT.unlock(function (line) { log('INFO: ' + line); }).then(function () {
      setStatus('fb-msg', 'Unlocked. The phone has been erased.', 'ok');
      stage('fb-flash');
    }).catch(function (e) {
      setStatus('fb-msg', e.message, 'bad');
    });
  });
  $('fb-flash').addEventListener('click', function () {
    var neutron = VERIFIED['neutron'];
    if (!neutron) {
      setStatus('fb-msg', 'The boot image was not checked in the files step — go back and pick it first.', 'bad');
      return;
    }
    setStatus('fb-msg', 'installing the boot image…', 'wait');
    FASTBOOT.flashBoot(new Uint8Array(neutron), function (line) { log('INFO: ' + line); },
      function (sent, total) { setStatus('fb-msg', 'sending ' + Math.round(sent / 1024) + ' / ' + Math.round(total / 1024) + ' KiB…', 'wait'); })
      .then(function () {
        setStatus('fb-msg', 'Boot image installed.', 'ok');
        stage('fb-reboot');
      }).catch(function (e) {
        setStatus('fb-msg', e.message, 'bad');
      });
  });
  $('fb-reboot').addEventListener('click', function () {
    setStatus('fb-msg', 'restarting…', 'wait');
    FASTBOOT.reboot().then(function () {
      setStatus('fb-msg', 'Restarted.', 'ok');
      // The phone is wiped and will not answer adb for a few minutes, so the
      // remaining work happens on the phone itself. Show it instead of prose.
      setStage('done');
    }).catch(function (e) {
      setStatus('fb-msg', e.message, 'bad');
    });
  });
  stage('fb-pick');
}

// --- return-to-factory slice (factory-gated, not on the step bar) -------------

// A stock boot image has no upstream pin, so it must never be able to satisfy
// the rooting path, and neutron.img must never satisfy this one. Only a file
// that passed the header, size, pasted-hash and build checks lands here.
var STOCK_VERIFIED = null;   // { bytes: Uint8Array, sha256: string }
var FACTORY_BACKUP = null;   // this session's host-side boot backup
var FACTORY_CURRENT = null;  // this phone's identity, read at backup time
var factoryStageName = null;

var FACTORY_STAGES = ['backup', 'verify', 'flash', 'reboot', 'wipe', 'done'];

// The same one-thing-on-screen rule the rooting step uses, kept as its own
// stage machine so a half-finished run in either slice cannot leak across.
function facStage(name) {
  factoryStageName = name;
  FACTORY_STAGES.forEach(function (s) {
    $('fac-stage-' + s).classList.toggle('hidden', s !== name);
  });
  $('fac-need-backup').classList.toggle('hidden', name !== 'flash' || !!FACTORY_BACKUP);
  $('fac-need-stock').classList.toggle('hidden', name !== 'flash' || !!STOCK_VERIFIED);
}

function factRow(box, label, value, cls) {
  var row = document.createElement('div');
  row.className = 'now-row';
  var l = document.createElement('span');
  l.className = 'now-label';
  l.textContent = label;
  var v = document.createElement('span');
  v.className = 'status' + (cls ? ' ' + cls : '');
  v.textContent = value;
  row.appendChild(l);
  row.appendChild(v);
  box.appendChild(row);
}

function initFactory() {
  // Typing the word is not enough on its own: three separate things have to be
  // acknowledged, so nobody arrives here holding one of them and guessing.
  function gate() {
    var word = $('factory-input').value.trim() === 'factory';
    var acks = $('fac-ack-image').checked && $('fac-ack-wipe').checked && $('fac-ack-root').checked;
    $('factory-open').disabled = !(word && acks);
    $('factory-gate-msg').textContent = !word
      ? 'Type the word to unlock the steps.'
      : (acks ? '' : 'Tick all three boxes to continue.');
  }

  $('factory-link').addEventListener('click', function (ev) {
    ev.preventDefault();
    showStep('factory');
    // A fresh visit starts locked at step 1 with nothing carried over from a
    // previous run — a stale backup or a checked hash would be a false promise.
    $('factory-body').classList.add('hidden');
    STOCK_VERIFIED = null;
    FACTORY_BACKUP = null;
    FACTORY_CURRENT = null;
    $('factory-input').value = '';
    ['fac-ack-image', 'fac-ack-wipe', 'fac-ack-root'].forEach(function (id) { $(id).checked = false; });
    ['fac-backup-msg', 'fac-verify-msg', 'fac-flash-msg', 'fac-reboot-msg', 'fac-check-msg'].forEach(function (id) {
      setStatus(id, '', '');
    });
    ['fac-backup-facts', 'fac-facts'].forEach(function (id) {
      $(id).classList.add('hidden');
      $(id).textContent = '';
      $(id).className = 'now hidden';
    });
    $('fac-serial-ok-wrap').classList.add('hidden');
    $('fac-serial-ok').checked = false;
    $('fac-backup-next').disabled = true;
    $('fac-verify-next').disabled = true;
    $('fac-flash').disabled = true;
    $('fac-file').value = '';
    $('fac-sha-input').value = '';
    $('fac-donor-fp').value = '';
    ['fac-verify-log', 'fac-flash-log'].forEach(function (id) {
      $(id).textContent = '';
      $(id).classList.add('hidden');
    });
    gate();
    facStage('backup');
  });

  $('factory-input').addEventListener('input', gate);
  ['fac-ack-image', 'fac-ack-wipe', 'fac-ack-root'].forEach(function (id) {
    $(id).addEventListener('change', gate);
  });

  $('factory-open').addEventListener('click', function () {
    $('factory-body').classList.remove('hidden');
    facStage('backup');
  });

  // 1 · back up the boot image the phone is running now. This is the only way
  // back to a rooted phone without unlocking it again, so nothing else opens
  // until it exists and someone has read the serial off the screen.
  $('fac-backup').addEventListener('click', function () {
    var btn = this;
    if (!window.FLIP2_NATIVE || !window.FLIP2_NATIVE.factoryBackupBoot) {
      setStatus('fac-backup-msg', 'Open this page in the Flip 2 Companion app — a plain browser cannot copy files off the phone.', 'bad');
      return;
    }
    btn.disabled = true;
    setStatus('fac-backup-msg', 'copying the boot image off the phone…', 'wait');
    Promise.all([
      window.FLIP2_NATIVE.factoryIdentity(),
      window.FLIP2_NATIVE.factoryBackupBoot()
    ]).then(function (r) {
      FACTORY_CURRENT = r[0];
      FACTORY_BACKUP = r[1];
      var box = $('fac-backup-facts');
      box.textContent = '';
      box.className = 'now';
      box.classList.remove('hidden');
      var okHeader = FACTORY_BACKUP.magic === 'ANDROID!';
      factRow(box, 'Phone serial', FACTORY_BACKUP.serial);
      factRow(box, 'Model', FACTORY_CURRENT['ro.product.model'] || '(not reported)');
      factRow(box, 'Build', FACTORY_CURRENT['ro.build.fingerprint'] || '(not reported)');
      factRow(box, 'Saved file', FACTORY_BACKUP.path);
      factRow(box, 'Size', FACTORY_BACKUP.size + ' bytes');
      factRow(box, 'SHA-256', FACTORY_BACKUP.sha256);
      factRow(box, 'Header', okHeader ? 'boot image (ANDROID!)' : FACTORY_BACKUP.magic, okHeader ? 'ok' : 'bad');
      if (!okHeader) {
        FACTORY_BACKUP = null;
        $('fac-serial-ok-wrap').classList.add('hidden');
        setStatus('fac-backup-msg', 'That file is not a boot image, so it is not a way back. Nothing was written to the phone.', 'bad');
        btn.disabled = false;
        return;
      }
      setStatus('fac-backup-msg', 'Saved. Keep this file — it is how this phone gets root back later.', 'ok');
      $('fac-serial-ok-wrap').classList.remove('hidden');
      $('fac-serial-ok').checked = false;
      $('fac-backup-next').disabled = true;
      btn.disabled = false;
    }).catch(function (e) {
      setStatus('fac-backup-msg', cleanErr(e), 'bad');
      btn.disabled = false;
    });
  });

  $('fac-serial-ok').addEventListener('change', function () {
    $('fac-backup-next').disabled = !(this.checked && FACTORY_BACKUP);
  });

  $('fac-backup-next').addEventListener('click', function () { facStage('verify'); });

  // 2 · check the stock image. Header, size against this phone's real boot
  // partition, the hash the user pasted, and that both phones are the same
  // build. Any one of those failing stops it here, before fastboot exists.
  $('fac-verify').addEventListener('click', function () {
    var file = $('fac-file').files[0];
    var pasted = $('fac-sha-input').value.trim().toLowerCase().replace(/\s+/g, '');
    var donorFp = $('fac-donor-fp').value.trim();
    $('fac-verify-log').textContent = '';
    var log = makeLog('fac-verify-log');
    STOCK_VERIFIED = null;
    $('fac-verify-next').disabled = true;

    if (!FACTORY_BACKUP) {
      setStatus('fac-verify-msg', 'Save this phone’s own boot image in step 1 first — without it there is no way back.', 'bad');
      return;
    }
    if (!file) {
      setStatus('fac-verify-msg', 'Choose the stock boot image first.', 'bad');
      return;
    }
    if (!/^[0-9a-f]{64}$/.test(pasted)) {
      setStatus('fac-verify-msg', 'Paste the file’s SHA-256: 64 characters, hex.', 'bad');
      return;
    }
    if (!donorFp) {
      setStatus('fac-verify-msg', 'Paste the other phone’s build fingerprint so the two phones can be compared.', 'bad');
      return;
    }
    var here = (FACTORY_CURRENT && FACTORY_CURRENT['ro.build.fingerprint']) || '';
    if (donorFp !== here) {
      log('this phone: ' + (here || '(not reported)'));
      log('other phone: ' + donorFp);
      setStatus('fac-verify-msg', 'That image came from a different build, so it is refused. Nothing was written.', 'bad');
      return;
    }

    setStatus('fac-verify-msg', 'checking the file…', 'wait');
    file.arrayBuffer().then(function (buf) {
      var view = new Uint8Array(buf);
      var magic = '';
      for (var i = 0; i < 8 && i < view.length; i++) magic += String.fromCharCode(view[i]);
      if (magic !== 'ANDROID!') {
        throw new Error('That file does not start with a boot image header, so it cannot be installed. Nothing was written.');
      }
      if (view.length > FACTORY_BACKUP.size) {
        throw new Error('That file is ' + view.length + ' bytes, larger than this phone’s boot partition (' + FACTORY_BACKUP.size + ' bytes). Nothing was written.');
      }
      return sha256Hex(buf).then(function (hex) {
        if (hex !== pasted) {
          throw new Error('The SHA-256 does not match the value you pasted, so the file is not the one you meant. Nothing was written.');
        }
        STOCK_VERIFIED = { bytes: view, sha256: hex };
        log('header: ANDROID!');
        log('size: ' + view.length + ' bytes (partition is ' + FACTORY_BACKUP.size + ')');
        log('sha256: ' + hex + ' — matches the pasted value');
        log('build: ' + donorFp + ' — matches this phone');
        setStatus('fac-verify-msg', 'Checked. This is a boot image from the same build as this phone.', 'ok');
        $('fac-verify-next').disabled = false;
      });
    }).catch(function (e) {
      log(e.message);
      setStatus('fac-verify-msg', e.message, 'bad');
    });
  });

  $('fac-verify-back').addEventListener('click', function () { facStage('backup'); });
  $('fac-verify-next').addEventListener('click', function () {
    if (!STOCK_VERIFIED) {
      setStatus('fac-verify-msg', 'Check the file first.', 'bad');
      return;
    }
    facStage('flash');
  });

  // 3 · connect to the bootloader and confirm it is the same phone the backup
  // came from. Serial is read from the device, never assumed.
  $('fac-pick').addEventListener('click', function () {
    if (!navigator.usb) {
      setStatus('fac-flash-msg', 'This browser has no WebUSB. Use the Flip 2 Companion app.', 'bad');
      return;
    }
    var want = FACTORY_BACKUP && FACTORY_BACKUP.serial;
    $('fac-flash').disabled = true;
    setStatus('fac-flash-msg', 'connecting to the bootloader…', 'wait');
    FASTBOOT.log = makeLog('fac-flash-log');
    FASTBOOT.pick().then(function () {
      return FASTBOOT.connect();
    }).then(function () {
      return FASTBOOT.getvar('serialno');
    }).then(function (s) {
      var got = String(s || '').trim();
      FASTBOOT.log('serialno: ' + (got || '(none reported)'));
      if (want && got !== want) {
        throw new Error('This is a different phone (' + (got || 'no serial') + '), not the one that was backed up (' + want + '). Unplug it and connect the right one. Nothing was written.');
      }
      setStatus('fac-flash-msg', 'Connected to ' + (got || 'the phone') + '. The stock image can be installed now.', 'ok');
      $('fac-flash').disabled = false;
    }).catch(function (e) {
      setStatus('fac-flash-msg', cleanErr(e), 'bad');
    });
  });

  $('fac-flash').addEventListener('click', function () {
    var btn = this;
    if (!STOCK_VERIFIED) {
      setStatus('fac-flash-msg', 'The stock image was not checked, so nothing is sent.', 'bad');
      return;
    }
    if (!FACTORY_BACKUP) {
      setStatus('fac-flash-msg', 'This phone’s own boot image was not saved, so nothing is sent.', 'bad');
      return;
    }
    btn.disabled = true;
    setStatus('fac-flash-msg', 'installing the stock boot image…', 'wait');
    FASTBOOT.flashBoot(new Uint8Array(STOCK_VERIFIED.bytes), function (line) {
      FASTBOOT.log('INFO: ' + line);
    }, function (sent, total) {
      setStatus('fac-flash-msg', 'sending ' + Math.round(sent / 1024) + ' / ' + Math.round(total / 1024) + ' KiB…', 'wait');
    }).then(function () {
      setStatus('fac-flash-msg', 'Stock boot image installed.', 'ok');
      facStage('reboot');
    }).catch(function (e) {
      setStatus('fac-flash-msg', cleanErr(e), 'bad');
      btn.disabled = false;
    });
  });

  $('fac-reboot').addEventListener('click', function () {
    var btn = this;
    btn.disabled = true;
    setStatus('fac-reboot-msg', 'restarting…', 'wait');
    FASTBOOT.reboot().then(function () {
      setStatus('fac-reboot-msg', 'Restarted.', 'ok');
      facStage('wipe');
      btn.disabled = false;
    }).catch(function (e) {
      setStatus('fac-reboot-msg', cleanErr(e), 'bad');
      btn.disabled = false;
    });
  });

  $('fac-wipe-next').addEventListener('click', function () { facStage('done'); });

  // 6 · ask the phone what it is now. The build and the absence of root are the
  // two things worth reading; the unlocked bootloader is stated as expected.
  $('fac-check').addEventListener('click', function () {
    var btn = this;
    if (!window.FLIP2_NATIVE || !window.FLIP2_NATIVE.factoryState) {
      setStatus('fac-check-msg', 'Open this page in the Flip 2 Companion app to ask the phone what it is now.', 'bad');
      return;
    }
    btn.disabled = true;
    setStatus('fac-check-msg', 'asking the phone…', 'wait');
    var expected = (FACTORY_CURRENT && FACTORY_CURRENT['ro.build.fingerprint']) || '';
    window.FLIP2_NATIVE.factoryState(expected).then(function (st) {
      var box = $('fac-facts');
      var happy = st.buildMatches && !st.rooted;
      box.textContent = '';
      box.className = 'now' + (happy ? ' caught' : ' bad');
      box.classList.remove('hidden');
      factRow(box, 'Phone serial', st.serial);
      factRow(box, 'Model', st.model || '(not reported)');
      factRow(box, 'Build', st.fingerprint || '(not reported)', st.buildMatches ? 'ok' : 'bad');
      factRow(box, 'Security patch', st.patch || '(not reported)');
      factRow(box, 'Root', st.rooted ? 'su still answers as root' : 'no root', st.rooted ? 'bad' : 'ok');
      factRow(box, 'Apps installed', st.packages < 0 ? 'could not count them' : String(st.packages));
      factRow(box, 'Bootloader', st.flashLocked === '1' ? 'locked' : 'unlocked (expected)', '');
      factRow(box, 'Verified boot', st.verifiedBootState || '(not reported)', '');
      setStatus('fac-check-msg', happy
        ? 'Back on the stock build, with no root. That is the factory state.'
        : 'Not quite there — read the rows above.', happy ? 'ok' : 'bad');
      btn.disabled = false;
    }).catch(function (e) {
      setStatus('fac-check-msg', cleanErr(e), 'bad');
      btn.disabled = false;
    });
  });

  facStage('backup');
  gate();
}

// --- back navigation --------------------------------------------------------
// Every step's Back button carries data-back="<previous step>". One delegated
// handler means a step cannot be added without a way out of it.
function initBackNav() {
  document.addEventListener('click', function (ev) {
    var btn = ev.target.closest ? ev.target.closest('[data-back]') : null;
    if (!btn) return;
    ev.preventDefault();
    showStep(btn.getAttribute('data-back'));
  });
}

// --- boot -------------------------------------------------------------------------------

function init() {
  loadCatalog().then(function () {
    buildCreditTable();
    initGate();
    initBackNav();
    initDownloads();
    initUdev();
    initUsb();
    initInstall();
    initVerify();
    initRoot();
    initFastboot();
    initFactory();
    showStep('credit');
    return Promise.all([
      fetch('../device/install.sh').then(function (r) { return r.text(); }),
      fetch('../device/verify.sh').then(function (r) { return r.text(); })
    ]).then(function (t) { INSTALL_SH = t[0]; VERIFY_SH = t[1]; });
  }).catch(function (e) {
    document.body.insertBefore(document.createTextNode(
      'The wizard failed to initialize: ' + e.message), document.body.firstChild);
  });
}

init();
