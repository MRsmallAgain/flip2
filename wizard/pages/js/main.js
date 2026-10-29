// Page wiring: step navigation, credit gate, download verification,
// udev text, USB connect, install/verify buttons, erase-gated rooting slice.
// Every module below is loaded by index.html before this one:
//   CATALOG/loadCatalog/sha256Hex, ADBKEY, ADB, PIPE, BOOTROM.

var ORDER = ['credit', 'download', 'udev', 'usb', 'install', 'verify'];
var REACHED = { credit: true };
var VERIFIED = {};            // catalog id -> ArrayBuffer of a hash-checked file
var INSTALL_SH = null;        // text of ../device/install.sh
var VERIFY_SH = null;         // text of ../device/verify.sh
var VERIFY_RAN_ONCE = false;  // unlock footer advanced links after first verify attempt

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

function unlockAdvancedFooter() {
  VERIFY_RAN_ONCE = true;
  var adv = $('footer-advanced');
  var hint = $('footer-advanced-hint');
  if (adv) adv.classList.remove('hidden');
  if (hint) hint.classList.add('hidden');
}

function probeRooted() {
  var banner = $('usb-rooted-banner');
  if (!banner) return;
  ADB.shell('su -c id', function () {})
    .then(function () {
      banner.classList.remove('hidden');
    })
    .catch(function () {});
}

function runPushAndInstall() {
  var files = {};
  ['installer-full', 'tagdrawer', 'forkgram', 'intertune', 'bouncy',
    'materialfiles', 'whisper-tiny', 'vosk-en', 'vosk-uk'].forEach(function (id) {
    if (VERIFIED[id]) files[id] = new Uint8Array(VERIFIED[id]);
  });
  $('inst-btn').disabled = true;
  setStatus('inst-msg', 'building push set…', 'wait');
  var log = makeLog('inst-log');
  var pushSet;
  try {
    pushSet = PIPE.buildPushSet(files);
  } catch (e) {
    setStatus('inst-msg', e.message, 'bad');
    $('inst-retry').classList.remove('hidden');
    $('inst-btn').disabled = false;
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
  }).then(function () {
    $('inst-btn').disabled = false;
  });
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
      probeRooted();
    }).catch(function (e) {
      setStatus('usb-msg', usbError(e), 'bad');
    });
  });
  $('usb-next').addEventListener('click', function () { showStep('install'); });
}

// --- 5 · install ------------------------------------------------------------------

function initInstall() {
  var modal = $('inst-modal');
  $('inst-btn').addEventListener('click', function () {
    if (modal) modal.classList.remove('hidden');
  });
  if ($('inst-modal-cancel')) {
    $('inst-modal-cancel').addEventListener('click', function () {
      if (modal) modal.classList.add('hidden');
    });
  }
  if ($('inst-modal-go')) {
    $('inst-modal-go').addEventListener('click', function () {
      if (modal) modal.classList.add('hidden');
      runPushAndInstall();
    });
  }
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
      unlockAdvancedFooter();
    });
  }
  $('ver-btn').addEventListener('click', runVerify);
  $('ver-recheck').addEventListener('click', runVerify);
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
