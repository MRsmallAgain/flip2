// Page wiring for TCL Flip2 Manager.
// Front door (phone, profile, apps) lives in manager.js, loaded before this file.
// Prepare still uses the credit gate, downloads, udev, USB connect, install, and verify.
// Rooting stays behind "erase". Return to factory stays behind "factory".
// Every module below is loaded by index.html before this one:
//   CATALOG/loadCatalog/sha256Hex, ADBKEY, ADB, PIPE, PROFILES, BOOTROM.

var ORDER = ['phone', 'profile', 'apps', 'prepare'];
var PREPARE = ['credit', 'download', 'udev', 'usb', 'install', 'verify'];
var REACHED = { phone: true };
var VERIFIED = {};            // catalog id -> ArrayBuffer of a hash-checked file
var INSTALL_SH = null;        // text of ../device/install.sh
var VERIFY_SH = null;         // text of ../device/verify.sh
var VERIFY_RAN_ONCE = false;  // unlock footer advanced links after first verify attempt

function $(id) { return document.getElementById(id); }

function showStep(name) {
  if (name === 'prepare') name = 'credit';
  var prepare = PREPARE.indexOf(name) >= 0;
  var pill = prepare ? 'prepare' : name;
  var i = ORDER.indexOf(pill), n;
  if (i >= 0) REACHED[pill] = true;
  ORDER.forEach(function (id) {
    var el = $('step-' + id);
    if (el) el.classList.toggle('on', id === name);
  });
  PREPARE.forEach(function (id) {
    var el = $('step-' + id);
    if (el) el.classList.toggle('on', id === name);
  });
  var spans = document.querySelectorAll('#steps span[data-step]');
  for (n = 0; n < spans.length; n++) {
    var step = spans[n].getAttribute('data-step');
    var idx = ORDER.indexOf(step);
    spans[n].classList.toggle('on', step === pill);
    spans[n].classList.toggle('done', idx >= 0 && i >= 0 && idx < i);
  }
  // Rooting and return-to-factory stay off the pill bar. Opening one closes
  // the other. Prepare subsections are not extra pills.
  ['root', 'factory'].forEach(function (extra) {
    var el = $('step-' + extra);
    if (!el) return;
    if (name === extra) {
      el.hidden = false;
      el.classList.add('on');
    } else {
      el.hidden = true;
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

function isBenignInstallError(msg) {
  if (!msg) return false;
  var m = String(msg);
  if (/Permission denied.*chmod/i.test(m)) return true;
  if (/install -m755 deploy failed/i.test(m)) return true;
  if (/cleanup (failed|skipped)/i.test(m)) return true;
  return false;
}

function maybeRecoverInstallAfterFailure(errMsg, log) {
  var useHost = window.FLIP2_NATIVE && window.FLIP2_NATIVE.wizardHostVerify;
  if (!useHost || !VERIFY_SH) return Promise.resolve(false);
  log('checking whether install actually succeeded (verify probe)…');
  var verifyShText = typeof VERIFY_SH === 'string' ? VERIFY_SH : new TextDecoder().decode(VERIFY_SH);
  return PIPE.hostVerify(verifyShText, log).then(function () {
    return true;
  }).catch(function () {
    return false;
  });
}

function markInstallSuccess(msg) {
  setStatus('inst-msg', msg || 'Install complete.', 'ok');
  var next = $('inst-next');
  next.classList.remove('hidden');
  next.disabled = false;
  var skip = $('inst-skip-verify');
  if (skip) skip.classList.add('hidden');
}

function runPushAndInstall() {
  var files = {};
  PROFILES.catalogIds().forEach(function (id) {
    if (VERIFIED[id]) files[id] = new Uint8Array(VERIFIED[id]);
  });
  $('inst-btn').disabled = true;
  var next = $('inst-next');
  next.disabled = true;
  next.classList.add('hidden');
  setStatus('inst-msg', 'building push set…', 'wait');
  var log = makeLog('inst-log');
  var pushSet;
  try {
    pushSet = PIPE.buildPushSet(files, PROFILES.componentIds());
  } catch (e) {
    setStatus('inst-msg', e.message, 'bad');
    $('inst-retry').classList.remove('hidden');
    $('inst-btn').disabled = false;
    return;
  }
  var useHost = window.FLIP2_NATIVE && window.FLIP2_NATIVE.wizardHostPrepare;
  if (!useHost && PROFILES.selectedId === 'managed') {
    setStatus('inst-msg', 'managed Apply requires Flip 2 Companion', 'bad');
    $('inst-retry').classList.remove('hidden');
    $('inst-btn').disabled = false;
    return;
  }
  if (!useHost) {
    setStatus('inst-msg', 'pushing ' + Object.keys(pushSet).length + ' files…', 'wait');
  }
  var installShText = typeof INSTALL_SH === 'string' ? INSTALL_SH : new TextDecoder().decode(INSTALL_SH);
  var pushP = useHost
    ? PIPE.hostPushAndInstall(pushSet, installShText, log, PROFILES.profileText(), function (text) {
        setStatus('inst-msg', text, 'wait');
      })
    : PIPE.pushAndInstall(pushSet, INSTALL_SH, log);
  var cleanP = useHost ? PIPE.hostCleanup(log) : PIPE.cleanup(log);
  pushP.then(function () {
    return cleanP;
  }).then(function () {
    markInstallSuccess('Install complete.');
  }).catch(function (e) {
    var errMsg = e.message || String(e);
    setStatus('inst-msg', errMsg, 'bad');
    $('inst-retry').classList.remove('hidden');
    var skip = $('inst-skip-verify');
    var hint = $('inst-wipe-hint');
    if (skip) skip.classList.remove('hidden');
    if (hint) hint.classList.remove('hidden');
    return maybeRecoverInstallAfterFailure(errMsg, log).then(function (recovered) {
      if (recovered) {
        markInstallSuccess('Install reported an error, but verify passed — continuing.');
        unlockAdvancedFooter();
        return;
      }
      if (isBenignInstallError(errMsg)) {
        log('note: this error is often harmless after a successful install — use Continue to verify anyway');
      }
    });
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
    if (f.url) {
      var a = document.createElement('a');
      a.href = f.url;
      a.textContent = f.upstream || f.url;
      a.target = '_blank';
      a.rel = 'noreferrer';
      td3.appendChild(a);
    } else {
      td3.textContent = f.upstream || 'local pin';
    }
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
    if (!f.url) {
      td3.textContent = f.upstream || 'local pin';
    } else if (window.FLIP2_NATIVE && window.FLIP2_NATIVE.downloadFile) {
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
  var ids = (typeof requiredCatalog === 'function') ? requiredCatalog() : CATALOG.list.map(function (f) { return f.id; });
  var missing = [];
  ids.forEach(function (id) {
    if (!VERIFIED[id]) {
      var f = CATALOG.byId[id];
      missing.push(f || { id: id, file: id });
    }
  });
  if (missing.length === 0) {
    setStatus('dl-msg', 'All ' + ids.length + ' files for this profile are verified.', 'ok');
    $('dl-next').disabled = false;
  } else {
    setStatus('dl-msg', missing.length + ' of ' + ids.length +
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
  var entry = CATALOG.byId[id];
  if (!entry || !entry.url) {
    setRow(id, 'local pin', 'wait');
    badLine((entry && entry.file ? entry.file : id) + ': no download URL; match the local pin');
    refreshDownloadGate();
    return Promise.resolve({ ok: false, msg: 'no download URL' });
  }
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
  var todo = CATALOG.list.filter(function (f) { return f.url && !VERIFIED[f.id]; })
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
    var failed = missing.filter(function (f) { return f.url; });
    if (failed.length) {
      setStatus('dl-msg', failed.length + ' could not be downloaded. A server may be down — try again, or choose files you got another way.', 'bad');
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
      var need = requiredCatalog();
      var n = need.filter(function (id) { return found[id]; }).length;
      if (n > 0 && !Object.keys(VERIFIED).length) {
        setStatus('dl-msg', n + ' of ' + need.length +
          ' files for this profile are already on this PC. Press "Use files already on this PC".', 'wait');
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

function enableUsbContinue(message, cls) {
  setStatus('usb-msg', message, cls || 'ok');
  $('usb-next').disabled = false;
}

function checkHostAdb() {
  var N = window.FLIP2_NATIVE;
  if (!N || !N.wizardHostAdbReady) {
    return Promise.reject(new Error('host adb check requires Flip 2 Companion'));
  }
  setStatus('usb-msg', 'checking host adb…', 'wait');
  return N.wizardHostAdbReady().then(function (r) {
    if (r.ok) {
      enableUsbContinue(r.message || 'Phone ready over host adb.', 'ok');
      probeRootedHost();
      return;
    }
    setStatus('usb-msg', r.message || 'Phone not ready over adb.', 'bad');
    $('usb-next').disabled = true;
  });
}

function probeRootedHost() {
  var banner = $('usb-rooted-banner');
  if (!banner || !window.FLIP2_NATIVE || !window.FLIP2_NATIVE.wizardHostShell) return;
  window.FLIP2_NATIVE.wizardHostShell({ cmd: 'su -c id', timeoutMs: 15000 })
    .then(function (r) {
      if (r.ok && /uid=0/.test(r.stdout || '')) banner.classList.remove('hidden');
    })
    .catch(function () {});
}

function initUsb() {
  var hostBtn = $('usb-host-btn');
  var hint = $('usb-companion-hint');
  if (window.FLIP2_NATIVE && window.FLIP2_NATIVE.wizardHostAdbReady) {
    if (hint) hint.classList.remove('hidden');
    if (hostBtn) hostBtn.classList.remove('hidden');
    if (hostBtn) {
      hostBtn.addEventListener('click', function () {
        hostBtn.disabled = true;
        checkHostAdb().finally(function () { hostBtn.disabled = false; });
      });
    }
    checkHostAdb();
  }
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
      enableUsbContinue('Connected over ADB.', 'ok');
      probeRooted();
    }).catch(function (e) {
      var msg = usbError(e);
      if (window.FLIP2_NATIVE && window.FLIP2_NATIVE.wizardHostAdbReady) {
        msg += ' Or press Check host adb — Companion install does not need WebUSB.';
      }
      setStatus('usb-msg', msg, 'bad');
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
    var next = $('inst-next');
    next.disabled = true;
    next.classList.add('hidden');
    var skip = $('inst-skip-verify');
    var hint = $('inst-wipe-hint');
    if (skip) skip.classList.add('hidden');
    if (hint) hint.classList.add('hidden');
  });
  $('inst-next').addEventListener('click', function () { showStep('verify'); });
  var skipBtn = $('inst-skip-verify');
  if (skipBtn) {
    skipBtn.addEventListener('click', function () { showStep('verify'); });
  }
}

// --- 6 · verify ---------------------------------------------------------------------

function initVerify() {
  function runVerify() {
    $('ver-btn').disabled = true;
    $('ver-recheck').classList.add('hidden');
    var useHost = window.FLIP2_NATIVE && window.FLIP2_NATIVE.wizardHostVerify;
    setStatus('ver-msg', useHost ? 'running verify.sh (host adb)…' : 'running verify.sh…', 'wait');
    var log = makeLog('ver-log');
    var verifyShText = typeof VERIFY_SH === 'string' ? VERIFY_SH : new TextDecoder().decode(VERIFY_SH);
    var verifyP = useHost ? PIPE.hostVerify(verifyShText, log) : PIPE.verify(VERIFY_SH, log);
    verifyP.then(function () {
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
    // The factory slice points FASTBOOT.log at its own pane when it connects and
    // nothing puts it back, so a rooting flash after a factory run would write
    // its download and flash lines into the other slice's log.
    FASTBOOT.log = log;
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

// The image this slice writes is this phone's own boot partition, saved by the
// wizard on this visit or an earlier one. It has no upstream pin, so it must
// never satisfy the rooting path, and neutron.img must never satisfy this one.
// Only a copy re-read off disk and re-hashed in step 2 lands in FACTORY_VERIFIED.
var FACTORY_PICKED = null;    // the copy chosen in step 1, with its recorded hash
var FACTORY_VERIFIED = null;  // { bytes, sha256, path } after the disk re-check
var FACTORY_CURRENT = null;   // this phone's identity, after a fresh dump
var FACTORY_COPIES = [];      // copies found on this computer, newest first
var factoryStageName = null;

var FACTORY_STAGES = ['backup', 'verify', 'flash', 'reboot', 'wipe', 'done'];

// The 4058G boot partition is 24 MiB. The device rejects anything larger in the
// DATA phase anyway, but refusing here keeps a wrong file off the wire entirely.
var BOOT_PARTITION = 25165824;

// The same one-thing-on-screen rule the rooting step uses, kept as its own
// stage machine so a half-finished run in either slice cannot leak across.
function facStage(name) {
  factoryStageName = name;
  FACTORY_STAGES.forEach(function (s) {
    $('fac-stage-' + s).classList.toggle('hidden', s !== name);
  });
  $('fac-need-copy').classList.toggle('hidden', name !== 'flash' || !!FACTORY_VERIFIED);
}

function facWhen(iso) {
  var d = new Date(iso);
  return isNaN(d.getTime()) ? 'date not recorded' : d.toLocaleString();
}

// One line per saved copy: when it was taken, and off which phone.
function facCopyLabel(c) {
  var bits = [facWhen(c.takenAt)];
  if (c.model) bits.push(c.model);
  bits.push(c.serial || 'phone not recorded');
  return bits.join(' · ') + ' — ' + Math.round(c.size / 1024) + ' KiB';
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
    var acks = $('fac-ack-copy').checked && $('fac-ack-wipe').checked && $('fac-ack-state').checked;
    $('factory-open').disabled = !(word && acks);
    $('factory-gate-msg').textContent = !word
      ? 'Type the word to unlock the steps.'
      : (acks ? '' : 'Tick all three boxes to continue.');
  }

  $('factory-link').addEventListener('click', function (ev) {
    ev.preventDefault();
    showStep('factory');
    // A fresh visit starts locked at step 1 with nothing carried over from a
    // previous run — a copy checked in a run that ended somewhere else would be
    // a false promise about what is about to be written.
    $('factory-body').classList.add('hidden');
    FACTORY_PICKED = null;
    FACTORY_VERIFIED = null;
    FACTORY_CURRENT = null;
    FACTORY_COPIES = [];
    $('factory-input').value = '';
    ['fac-ack-copy', 'fac-ack-wipe', 'fac-ack-state'].forEach(function (id) { $(id).checked = false; });
    ['fac-backup-msg', 'fac-copies-msg', 'fac-verify-msg', 'fac-flash-msg', 'fac-reboot-msg', 'fac-check-msg']
      .forEach(function (id) { setStatus(id, '', ''); });
    ['fac-backup-facts', 'fac-picked', 'fac-facts'].forEach(function (id) {
      $(id).classList.add('hidden');
      $(id).textContent = '';
      $(id).className = 'now hidden';
    });
    $('fac-copies-wrap').classList.add('hidden');
    $('fac-copies').textContent = '';
    $('fac-backup-next').disabled = true;
    $('fac-verify-next').disabled = true;
    $('fac-flash').disabled = true;
    ['fac-verify-log', 'fac-flash-log'].forEach(function (id) {
      $(id).textContent = '';
      $(id).classList.add('hidden');
    });
    gate();
    facStage('backup');
  });

  $('factory-input').addEventListener('input', gate);
  ['fac-ack-copy', 'fac-ack-wipe', 'fac-ack-state'].forEach(function (id) {
    $(id).addEventListener('change', gate);
  });

  $('factory-open').addEventListener('click', function () {
    $('factory-body').classList.remove('hidden');
    facStage('backup');
  });

  // Copies already on this computer, so a phone that will not start can still be
  // restored from a copy saved on an earlier visit. Newest first.
  function loadCopies() {
    if (!window.FLIP2_NATIVE || !window.FLIP2_NATIVE.factoryListBackups) {
      setStatus('fac-copies-msg', 'Open this page in the Flip 2 Companion app to look for saved copies.', 'bad');
      return Promise.resolve();
    }
    setStatus('fac-copies-msg', 'looking…', 'wait');
    return window.FLIP2_NATIVE.factoryListBackups().then(function (list) {
      FACTORY_COPIES = Array.isArray(list) ? list : [];
      var sel = $('fac-copies');
      sel.textContent = '';
      FACTORY_COPIES.forEach(function (c, i) {
        var opt = document.createElement('option');
        opt.value = String(i);
        opt.textContent = facCopyLabel(c);
        sel.appendChild(opt);
      });
      $('fac-copies-wrap').classList.toggle('hidden', !FACTORY_COPIES.length);
      setStatus('fac-copies-msg', FACTORY_COPIES.length
        ? FACTORY_COPIES.length + (FACTORY_COPIES.length === 1 ? ' saved copy found.' : ' saved copies found.')
        : 'No copies saved on this computer yet. Save one from the phone above.', FACTORY_COPIES.length ? 'ok' : '');
      if (FACTORY_COPIES.length) selectCopy();
    }).catch(function (e) {
      setStatus('fac-copies-msg', cleanErr(e), 'bad');
    });
  }

  function selectCopy() {
    var c = FACTORY_COPIES[Number($('fac-copies').value || 0)];
    if (!c) return;
    FACTORY_PICKED = c;
    FACTORY_VERIFIED = null;
    $('fac-backup-next').disabled = false;
    setStatus('fac-copies-msg', 'Chosen: ' + facWhen(c.takenAt) + ' from ' + (c.serial || 'a phone whose serial was not recorded') + '. It is checked in step 2.', 'ok');
  }

  // 1 · save the boot image the phone is running now, or choose one already on
  // this computer. A copy is what step 3 puts back, so nothing else opens until
  // one has been chosen.
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
      var info = r[1];
      var box = $('fac-backup-facts');
      box.textContent = '';
      box.className = 'now';
      box.classList.remove('hidden');
      var okHeader = info.magic === 'ANDROID!';
      factRow(box, 'Phone serial', info.serial);
      factRow(box, 'Model', info.model || '(not reported)');
      factRow(box, 'Build', info.fingerprint || '(not reported)');
      factRow(box, 'Saved file', info.path);
      factRow(box, 'Size', info.size + ' bytes');
      factRow(box, 'SHA-256', info.sha256);
      factRow(box, 'Header', okHeader ? 'boot image (ANDROID!)' : info.magic, okHeader ? 'ok' : 'bad');
      factRow(box, 'Root right now', info.rooted ? 'rooted — a copy taken now comes back rooted' : 'no root');
      if (!okHeader) {
        setStatus('fac-backup-msg', 'That file is not a boot image, so it is not a way to bring this phone back. Nothing was written to the phone.', 'bad');
        btn.disabled = false;
        return;
      }
      FACTORY_PICKED = info;
      FACTORY_VERIFIED = null;
      $('fac-backup-next').disabled = false;
      // The copy just saved belongs in the list too, so it can be chosen later
      // even if the phone cannot be read on that visit.
      loadCopies().catch(function () {});
      setStatus('fac-backup-msg', 'Saved. That is the image step 3 puts back, and it stays on this computer for next time.', 'ok');
      btn.disabled = false;
    }).catch(function (e) {
      setStatus('fac-backup-msg', cleanErr(e), 'bad');
      btn.disabled = false;
    });
  });

  $('fac-refresh').addEventListener('click', function () { loadCopies(); });
  $('fac-copies').addEventListener('change', selectCopy);

  // 1 · carry the chosen copy into step 2 and show exactly what was chosen, so
  // the person can see the date and the phone it came off before it is checked.
  $('fac-backup-next').addEventListener('click', function () {
    if (!FACTORY_PICKED) {
      setStatus('fac-copies-msg', 'Choose a copy first.', 'bad');
      return;
    }
    FACTORY_VERIFIED = null;
    $('fac-verify-next').disabled = true;
    var box = $('fac-picked');
    box.textContent = '';
    box.className = 'now';
    box.classList.remove('hidden');
    factRow(box, 'Saved', facWhen(FACTORY_PICKED.takenAt));
    factRow(box, 'From', FACTORY_PICKED.model || '(model not recorded)');
    factRow(box, 'Phone serial', FACTORY_PICKED.serial || 'not recorded');
    factRow(box, 'Build when saved', FACTORY_PICKED.fingerprint || '(not recorded)');
    factRow(box, 'File', FACTORY_PICKED.path);
    factRow(box, 'Size', FACTORY_PICKED.size + ' bytes');
    factRow(box, 'Recorded SHA-256', FACTORY_PICKED.sha256);
    factRow(box, 'Root in that copy', FACTORY_PICKED.rooted
      ? 'yes — the phone comes back rooted'
      : (FACTORY_PICKED.rooted === false ? 'no — the phone comes back unrooted' : 'not recorded'));
    facStage('verify');
  });

  // 2 · read the copy off this computer again and check it. Header, size against
  // the real boot partition, and the hash recorded when it was saved. Anything
  // that has changed since then is refused, before fastboot exists.
  $('fac-verify').addEventListener('click', function () {
    $('fac-verify-log').textContent = '';
    var log = makeLog('fac-verify-log');
    FACTORY_VERIFIED = null;
    $('fac-verify-next').disabled = true;

    if (!FACTORY_PICKED) {
      setStatus('fac-verify-msg', 'Choose a copy in step 1 first — without one there is nothing to put back.', 'bad');
      return;
    }
    if (!window.FLIP2_NATIVE || !window.FLIP2_NATIVE.factoryReadBackup) {
      setStatus('fac-verify-msg', 'Open this page in the Flip 2 Companion app — a plain browser cannot read the copy.', 'bad');
      return;
    }

    // A copy chosen from the list arrives with no live reading of the phone, so
    // ask it now. A phone that will not start is expected here; that failure is
    // reported and the build comparison is skipped rather than treated as an error.
    var current = FACTORY_CURRENT
      ? Promise.resolve(FACTORY_CURRENT)
      : (window.FLIP2_NATIVE.factoryIdentity
        ? window.FLIP2_NATIVE.factoryIdentity().catch(function () { return null; })
        : Promise.resolve(null));

    setStatus('fac-verify-msg', 'reading the copy off this computer…', 'wait');
    Promise.all([window.FLIP2_NATIVE.factoryReadBackup(FACTORY_PICKED.path), current])
      .then(function (r) {
      var got = r[0];
      var now = r[1];
      if (now) FACTORY_CURRENT = now;
      var bytes = new Uint8Array(got.bytes);
      var magic = '';
      for (var i = 0; i < 8 && i < bytes.length; i++) magic += String.fromCharCode(bytes[i]);
      log('header: ' + (magic === 'ANDROID!' ? 'ANDROID!' : magic || '(empty file)'));
      log('size: ' + bytes.length + ' bytes (partition holds ' + BOOT_PARTITION + ')');
      log('sha256 now: ' + got.sha256);
      log('sha256 when saved: ' + FACTORY_PICKED.sha256);
      if (magic !== 'ANDROID!') {
        throw new Error('That file does not start with a boot image header, so it cannot be installed. Nothing was written.');
      }
      if (bytes.length > BOOT_PARTITION) {
        throw new Error('That file is ' + bytes.length + ' bytes, larger than the boot partition (' + BOOT_PARTITION + ' bytes). Nothing was written.');
      }
      if (got.sha256 !== FACTORY_PICKED.sha256) {
        throw new Error('The file has changed since it was saved, so it is not the copy that was checked. Nothing was written.');
      }
      var expect = FACTORY_PICKED.fingerprint;
      var here = (now && now['ro.build.fingerprint']) || '';
      if (expect && here && expect !== here) {
        log('this phone: ' + here);
        log('copy came from: ' + expect);
        throw new Error('That copy came from a different build, so it is refused. Nothing was written.');
      }
      if (expect && here) log('build: matches this phone');
      else log('build: not compared — ' + (here
        ? 'the copy does not record one'
        : 'the phone cannot be read right now, which is what this is for'));
      FACTORY_VERIFIED = { bytes: bytes, sha256: got.sha256, path: got.path };
      setStatus('fac-verify-msg', 'Checked. This is the copy that was saved, unchanged.', 'ok');
      $('fac-verify-next').disabled = false;
    }).catch(function (e) {
      log(e.message);
      setStatus('fac-verify-msg', e.message, 'bad');
    });
  });

  $('fac-verify-back').addEventListener('click', function () { facStage('backup'); });
  $('fac-verify-next').addEventListener('click', function () {
    if (!FACTORY_VERIFIED) {
      setStatus('fac-verify-msg', 'Check the copy first.', 'bad');
      return;
    }
    facStage('flash');
  });

  // 3 · connect to the bootloader and confirm it is the same phone the copy came
  // from. Serial is read from the device, never assumed; a copy with no serial
  // recorded cannot be compared, so that is said rather than guessed.
  $('fac-pick').addEventListener('click', function () {
    if (!navigator.usb) {
      setStatus('fac-flash-msg', 'This browser has no WebUSB. Use the Flip 2 Companion app.', 'bad');
      return;
    }
    var want = (FACTORY_PICKED && FACTORY_PICKED.serial) || '';
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
        throw new Error('This is a different phone (' + (got || 'no serial') + '), not the one the copy came from (' + want + '). Unplug it and connect the right one. Nothing was written.');
      }
      if (!want) FASTBOOT.log('the copy has no serial recorded, so there is nothing to compare it with');
      setStatus('fac-flash-msg', 'Connected to ' + (got || 'the phone') + '. The copy can be installed now.', 'ok');
      $('fac-flash').disabled = false;
    }).catch(function (e) {
      setStatus('fac-flash-msg', cleanErr(e), 'bad');
    });
  });

  $('fac-flash').addEventListener('click', function () {
    var btn = this;
    if (!FACTORY_VERIFIED) {
      setStatus('fac-flash-msg', 'The copy was not checked, so nothing is sent.', 'bad');
      return;
    }
    btn.disabled = true;
    setStatus('fac-flash-msg', 'installing the copy…', 'wait');
    FASTBOOT.flashBoot(new Uint8Array(FACTORY_VERIFIED.bytes), function (line) {
      FASTBOOT.log('INFO: ' + line);
    }, function (sent, total) {
      setStatus('fac-flash-msg', 'sending ' + Math.round(sent / 1024) + ' / ' + Math.round(total / 1024) + ' KiB…', 'wait');
    }).then(function () {
      setStatus('fac-flash-msg', 'The copy is installed.', 'ok');
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

  // 6 · ask the phone what it is now and compare it with the copy that was put
  // back. Root is not a separate thing to check: it lives in that image's
  // ramdisk, so the honest question is whether the phone came back as the copy.
  $('fac-check').addEventListener('click', function () {
    var btn = this;
    if (!window.FLIP2_NATIVE || !window.FLIP2_NATIVE.factoryState) {
      setStatus('fac-check-msg', 'Open this page in the Flip 2 Companion app to ask the phone what it is now.', 'bad');
      return;
    }
    btn.disabled = true;
    setStatus('fac-check-msg', 'asking the phone…', 'wait');
    var copy = FACTORY_PICKED || {};
    var expected = copy.fingerprint || (FACTORY_CURRENT && FACTORY_CURRENT['ro.build.fingerprint']) || '';
    window.FLIP2_NATIVE.factoryState(expected).then(function (st) {
      var box = $('fac-facts');
      // A copy with no recorded root state cannot be compared, so it is not
      // counted against the run — only a definite mismatch is a failure.
      var rootAgrees = typeof copy.rooted !== 'boolean' || st.rooted === copy.rooted;
      var buildAgrees = !expected || st.buildMatches;
      var happy = rootAgrees && buildAgrees;
      box.textContent = '';
      box.className = 'now' + (happy ? ' caught' : ' bad');
      box.classList.remove('hidden');
      factRow(box, 'Phone serial', st.serial);
      factRow(box, 'Model', st.model || '(not reported)');
      factRow(box, 'Build', st.fingerprint || '(not reported)', buildAgrees ? 'ok' : 'bad');
      factRow(box, 'Security patch', st.patch || '(not reported)');
      factRow(box, 'Root', st.rooted ? 'rooted' : 'no root', rootAgrees ? 'ok' : 'bad');
      factRow(box, 'Root in the copy', typeof copy.rooted === 'boolean'
        ? (copy.rooted ? 'rooted' : 'no root')
        : '(not recorded)', rootAgrees ? 'ok' : 'bad');
      factRow(box, 'Apps installed', st.packages < 0 ? 'could not count them' : String(st.packages));
      factRow(box, 'Bootloader', st.flashLocked === '1' ? 'locked' : 'unlocked (expected)', '');
      factRow(box, 'Verified boot', st.verifiedBootState || '(not reported)', '');
      setStatus('fac-check-msg', happy
        ? 'The phone came back as the copy that was saved.'
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
    return PROFILES.load();
  }).then(function () {
    if (typeof initFrontNav !== 'function') throw new Error('manager.js did not load');
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
    initFrontNav();
    initPhone();
    initProfile();
    initApps();
    if (window.FLIP2_NATIVE) {
      unlockAdvancedFooter();
      var fw = $('footer-wipe-always');
      if (fw) fw.classList.remove('hidden');
    }
    showStep('phone');
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
