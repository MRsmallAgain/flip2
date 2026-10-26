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
  var root = $('step-root');
  if (name === 'root') {
    root.hidden = false;
    root.classList.add('on');
  } else {
    root.classList.remove('on');
  }
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
    var a = document.createElement('a');
    a.href = f.url; a.textContent = 'download'; a.target = '_blank'; a.rel = 'noreferrer';
    td3.appendChild(a);
    var td4 = document.createElement('td'); td4.textContent = '—';
    td4.setAttribute('data-status', f.id);
    tr.appendChild(td0); tr.appendChild(td1); tr.appendChild(td2); tr.appendChild(td3); tr.appendChild(td4);
    tbody.appendChild(tr);
  });
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
      var td = r.id ? document.querySelector('[data-status="' + r.id + '"]') : null;
      if (td) {
        td.textContent = r.ok ? 'verified' : 'FAILED';
        td.className = r.ok ? 'ok' : 'bad';
      }
      if (!r.ok) {
        var div = document.createElement('div');
        div.textContent = 'BAD: ' + r.msg;
        div.className = 'bad';
        $('dl-results').appendChild(div);
      }
    });
    var missing = CATALOG.list.filter(function (f) { return !VERIFIED[f.id]; });
    if (missing.length === 0) {
      setStatus('dl-msg', 'All ' + CATALOG.list.length + ' files verified.', 'ok');
      $('dl-next').disabled = false;
    } else {
      setStatus('dl-msg', missing.length + ' file(s) still missing or failed: ' +
        missing.map(function (f) { return f.file; }).join(', '), 'wait');
      $('dl-next').disabled = true;
    }
  }).catch(function (e) {
    setStatus('dl-msg', 'could not read a picked file: ' + e.message, 'bad');
  });
}

function initDownloads() {
  buildDownloadTable();
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
      ADB.log = adbLog;
      return ADB.connect();
    }).then(function () {
      setStatus('usb-msg', 'Connected over ADB.', 'ok');
      $('usb-next').disabled = false;
    }).catch(function (e) {
      setStatus('usb-msg', e.message, 'bad');
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

function initRoot() {
  $('root-link').addEventListener('click', function (ev) {
    ev.preventDefault();
    showStep('root');
  });
  $('erase-input').addEventListener('input', function () {
    $('root-open').disabled = this.value.trim() !== 'erase';
  });
  $('root-open').addEventListener('click', function () {
    $('root-body').classList.remove('hidden');
  });
  $('boot-btn').addEventListener('click', function () {
    if (!navigator.serial) {
      setStatus('boot-msg', 'This browser has no Web Serial. Use Chrome on Linux.', 'bad');
      return;
    }
    this.disabled = true;
    setStatus('boot-msg', 'watching for the preloader…', 'wait');
    BOOTROM.log = makeLog('boot-log');
    BOOTROM.boot('FASTBOOT').then(function () {
      setStatus('boot-msg', 'Handshake complete — phone is in fastboot mode.', 'ok');
      $('fb-h').classList.remove('hidden');
      $('fb-p').classList.remove('hidden');
      $('fb-controls').classList.remove('hidden');
    }).catch(function (e) {
      setStatus('boot-msg', e.message, 'bad');
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
    setStatus('fb-msg', 'picking…', 'wait');
    FASTBOOT.pick().then(function () {
      return FASTBOOT.connect();
    }).then(function () {
      setStatus('fb-msg', 'Fastboot connected.', 'ok');
      stage('fb-unlock');
    }).catch(function (e) {
      setStatus('fb-msg', e.message, 'bad');
      stage('fb-pick');
    });
  });
  $('fb-unlock').addEventListener('click', function () {
    setStatus('fb-msg', 'Confirm on the phone keypad…', 'wait');
    FASTBOOT.unlock(function (line) { log('INFO: ' + line); }).then(function () {
      setStatus('fb-msg', 'Unlocked. The phone was wiped.', 'ok');
      stage('fb-flash');
    }).catch(function (e) {
      setStatus('fb-msg', e.message, 'bad');
    });
  });
  $('fb-flash').addEventListener('click', function () {
    var neutron = VERIFIED['neutron'];
    if (!neutron) {
      setStatus('fb-msg', 'neutron.img was not verified in the files step — go back and pick it first.', 'bad');
      return;
    }
    setStatus('fb-msg', 'flashing boot…', 'wait');
    FASTBOOT.flashBoot(new Uint8Array(neutron), function (line) { log('INFO: ' + line); },
      function (sent, total) { setStatus('fb-msg', 'sending ' + Math.round(sent / 1024) + ' / ' + Math.round(total / 1024) + ' KiB…', 'wait'); })
      .then(function () {
        setStatus('fb-msg', 'boot flashed with neutron.img.', 'ok');
        stage('fb-reboot');
      }).catch(function (e) {
        setStatus('fb-msg', e.message, 'bad');
      });
  });
  $('fb-reboot').addEventListener('click', function () {
    setStatus('fb-msg', 'rebooting…', 'wait');
    FASTBOOT.reboot().then(function () {
      setStatus('fb-msg', 'Rebooted. After the wipe: dial *#*#217703#*#*, let Magisk finish, reboot again, re-enable USB debugging, then start the wizard from Connect.', 'ok');
    }).catch(function (e) {
      setStatus('fb-msg', e.message, 'bad');
    });
  });
  stage('fb-pick');
}

// --- boot -------------------------------------------------------------------------------

function init() {
  loadCatalog().then(function () {
    buildCreditTable();
    initGate();
    initDownloads();
    initUdev();
    initUsb();
    initInstall();
    initVerify();
    initRoot();
    initFastboot();
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
