// Phone, Profile, and Apps for the TCL Flip2 Manager.
// Loaded after profiles.js and before main.js. Prepare still uses the
// credit / download / udev / usb / install / verify sections.
// requiredCatalog() is what Continue and Apply share.

var APPS_STATE = null;
var appsBusy = false;
// Set on Phone → Refresh when host adb succeeds: true/false from su -c id; null = not checked yet.
var phoneHostRootState = null;

function setTier1RootPrereqVisible(show) {
  var el = $('tier1-root-prereq');
  if (!el) return;
  el.classList.toggle('hidden', !show);
}

function openInstallModal() {
  var modal = $('inst-modal');
  if (!modal) return;
  var warn = $('inst-modal-root-warn');
  if (warn) warn.classList.toggle('hidden', phoneHostRootState !== false);
  modal.classList.remove('hidden');
  if (phoneHostRootState === false) {
    setStatus('inst-msg',
      'Phone did not report root on the last Refresh. Install needs su — root the phone first, then Refresh again.',
      'bad');
  }
}

var APK_INCOMING = {
  launcher4: { name: 'launcher4.apk', fromInstaller: 'payload/apks/launcher4.apk' },
  ime: { name: 'nullkeyboard.apk', fromInstaller: 'payload/apks/nullkeyboard.apk' },
  forkgram: { name: 'forkgram.apk', catalogId: 'forkgram' },
  materialfiles: { name: 'materialfiles.apk', catalogId: 'materialfiles' },
  intertune: { name: 'intertune.apk', catalogId: 'intertune' },
  bouncy: { name: 'bouncy.apk', catalogId: 'bouncy' },
  headwind: { name: 'headwind.apk', catalogId: 'headwind-launcher' },
  where: { name: 'where.apk', catalogId: 'where-app' }
};

function requiredCatalog() {
  if (typeof PROFILES !== 'undefined' && PROFILES.data) return PROFILES.catalogIds();
  var ids = [];
  var i, id;
  for (i = 0; i < CATALOG.list.length; i++) {
    id = CATALOG.list[i].id;
    if (id === 'neutron' || id === 'headwind-launcher' || id === 'where-app') continue;
    ids.push(id);
  }
  return ids;
}

function shellOut(cmd) {
  var N = window.FLIP2_NATIVE;
  if (!N || !N.wizardHostShell) {
    return Promise.reject(new Error('Open this page in the Flip 2 Companion app to read the phone.'));
  }
  return N.wizardHostShell({ cmd: cmd, timeoutMs: 20000 }).then(function (r) {
    return String((r && r.stdout) || '').replace(/\r/g, '');
  });
}

function shellSoft(cmd) {
  return shellOut(cmd).then(function (out) {
    return { ok: true, out: out };
  }, function (e) {
    return { ok: false, out: '', error: cleanErr(e) };
  });
}

function parseDeviceOwner(text) {
  var lines = String(text || '').split('\n');
  var header = 'Device Owner:';
  var i, idx, rest, j, m;
  for (i = 0; i < lines.length; i++) {
    idx = lines[i].indexOf(header);
    if (idx < 0) continue;
    rest = lines[i].slice(idx + header.length).trim();
    if (rest && rest !== 'null' && rest.toLowerCase() !== 'none') return rest;
    for (j = i + 1; j < lines.length; j++) {
      if (lines[j] && lines[j].charAt(0) !== ' ' && lines[j].charAt(0) !== '\t') break;
      m = /(?:admin|package)=(\S+)/.exec(lines[j]);
      if (m && m[1] && m[1] !== 'null' && m[1].toLowerCase() !== 'none') return m[1];
    }
    return 'none';
  }
  if (/Current Device Policy Manager state|Enabled Device Admins/i.test(String(text || ''))) {
    return 'none';
  }
  return 'unknown';
}

function initFrontNav() {
  var spans = document.querySelectorAll('#steps span[data-step]');
  var n;
  for (n = 0; n < spans.length; n++) {
    spans[n].addEventListener('click', function () {
      var step = this.getAttribute('data-step');
      showStep(step === 'prepare' ? 'credit' : step);
    });
  }
}

function initGettingStarted() {
  var box = $('step-start');
  if (!box) return;
  box.addEventListener('click', function (ev) {
    var prereq = ev.target.closest('[data-prereq-goto]');
    if (prereq) {
      var dest = prereq.getAttribute('data-prereq-goto');
      if (dest === 'root') showStep('root');
      return;
    }
    var btn = ev.target.closest('[data-goto-step]');
    if (!btn) return;
    var step = btn.getAttribute('data-goto-step');
    if (step === 'prepare') showStep('credit');
    else if (step === 'profile') showStep('start');
    else showStep(step);
  });
}

function setPhoneNext(html, show) {
  var el = $('phone-next');
  if (!el) return;
  if (!show) {
    el.classList.add('hidden');
    el.innerHTML = '';
    return;
  }
  el.innerHTML = html;
  el.classList.remove('hidden');
}

function phoneNotReadyCopy(mode) {
  if (mode === 'recovery') {
    return {
      fact: 'recovery',
      cls: 'bad',
      status: 'The phone is in recovery.',
      next: 'Reboot the phone to Android. Do not flash from this screen.'
    };
  }
  if (mode === 'mtp') {
    return {
      fact: 'file transfer only',
      cls: 'wait',
      status: 'USB is file transfer only.',
      next: 'Switch the USB mode or turn on USB debugging. This is not a flash mode.'
    };
  }
  if (mode === 'android') {
    return {
      fact: 'accept the debugging prompt',
      cls: 'wait',
      status: 'Accept the USB debugging prompt on the phone.',
      next: 'Android is on USB, but adb is not allowed yet. Accept the prompt on the phone, then press <b>Refresh</b>. This is not a wipe.'
    };
  }
  if (mode === 'preloader') {
    return {
      fact: 'preloader',
      cls: 'bad',
      status: 'The phone is in the preloader.',
      next: 'Power the phone back to Android. Do not flash from this screen.'
    };
  }
  if (mode === 'fastboot') {
    return {
      fact: 'fastboot',
      cls: 'bad',
      status: 'The phone is in fastboot.',
      next: 'Reboot the phone to Android. Do not flash from this screen.'
    };
  }
  if (mode === 'bootrom') {
    return {
      fact: 'bootrom',
      cls: 'bad',
      status: 'The phone is in the bootrom.',
      next: 'Power the phone back to Android. Do not flash from this screen.'
    };
  }
  if (mode === 'stuck') {
    return {
      fact: 'not in Android',
      cls: 'bad',
      status: 'The phone is not in Android.',
      next: 'Power-cycle the phone back to Android. Do not flash from this screen.'
    };
  }
  if (mode === 'conflict') {
    return {
      fact: 'more than one phone',
      cls: 'bad',
      status: 'More than one phone is on USB.',
      next: 'Unplug the other phone so only one Flip2 is on USB.'
    };
  }
  if (mode === 'absent') {
    return {
      fact: 'no Flip2 on USB',
      cls: 'wait',
      status: 'No Flip2 on USB.',
      next: 'Plug the phone in, then press <b>Refresh</b>.'
    };
  }
  if (mode === 'unknown') {
    return {
      fact: 'USB not recognized',
      cls: 'wait',
      status: 'Companion could not match this USB device.',
      next: 'Companion could not match this USB device.'
    };
  }
  return {
    fact: 'not ready',
    cls: 'bad',
    status: 'Phone not ready.',
    next: 'Plug in USB, accept the debugging prompt on the phone, then press <b>Refresh</b>. If adb still fails, open <b>USB debugging</b> or <b>USB rules</b> under Prepare.'
  };
}

function refreshPhone() {
  var box = $('phone-facts');
  if (!box) return;
  box.textContent = '';
  box.className = 'now';
  setPhoneNext('', false);
  var N = window.FLIP2_NATIVE;
  if (!N || !N.wizardHostAdbReady) {
    phoneHostRootState = null;
    setTier1RootPrereqVisible(false);
    factRow(box, 'Companion', 'Open this page in the Flip 2 Companion app to read the phone.', 'wait');
    setStatus('phone-msg', 'Host adb status needs Flip 2 Companion.', 'wait');
    return;
  }
  setStatus('phone-msg', 'reading the phone\u2026', 'wait');
  N.wizardHostAdbReady().then(function (ready) {
    if (!ready || !ready.ok) {
      var describe = (N.phoneState ? N.phoneState() : Promise.resolve(null)).then(function (state) {
        return (state && state.mode) || 'unknown';
      }, function () {
        return 'unknown';
      });
      return describe.then(function (mode) {
        phoneHostRootState = null;
        setTier1RootPrereqVisible(false);
        var copy = phoneNotReadyCopy(mode);
        factRow(box, 'USB', copy.fact, copy.cls);
        setStatus('phone-msg', copy.status, copy.cls);
        setPhoneNext(copy.next, true);
      });
    }
    factRow(box, 'Serial', ready.serial || '(unknown)', 'ok');
    return Promise.all([
      shellSoft('getprop ro.product.model'),
      shellSoft('su -c id'),
      shellSoft('dumpsys device_policy'),
      shellSoft('dumpsys account')
    ]).then(function (parts) {
      var model = parts[0].ok ? parts[0].out.trim() : '';
      factRow(box, 'Model', model || '(not reported)');
      var rooted = parts[1].ok && /uid=0/.test(parts[1].out);
      phoneHostRootState = rooted;
      setTier1RootPrereqVisible(!rooted);
      factRow(box, 'Root', rooted ? 'rooted' : 'no root', rooted ? 'ok' : 'wait');
      var owner = parts[2].ok ? parseDeviceOwner(parts[2].out) : 'unknown';
      factRow(box, 'Device owner', owner, owner === 'none' ? 'ok' : 'wait');
      var accountsUnknown = !parts[3].ok;
      var accounts = parts[3].ok && /Account\s*\{/.test(parts[3].out);
      factRow(box, 'Accounts', accountsUnknown ? 'unknown' : (accounts ? 'present' : 'none'),
        accounts || accountsUnknown ? 'wait' : 'ok');
      if (accounts) {
        factRow(box, 'Wipe', 'Factory reset stays on the phone. Backup ~/flip2-pre-wipe-backup.', 'wait');
      }
      if (!rooted) {
        setStatus('phone-msg', 'Phone is on adb but does not report root.', 'wait');
        setPhoneNext(
          '<b>Tier 1 needs root.</b> Tier 3 <b>Erase and root</b> or the release zip, then <b>Refresh</b>. Push and install need <code>su</code>.',
          true);
        return;
      }
      setStatus('phone-msg', 'Phone ready over host adb.', 'ok');
      setPhoneNext(
        '<b>Next:</b> pick Base or Managed above → <b>Prepare</b> or <b>Apps</b> Apply.',
        true);
    });
  }).catch(function (e) {
    phoneHostRootState = null;
    setTier1RootPrereqVisible(false);
    setStatus('phone-msg', cleanErr(e), 'bad');
  });
}

function initPhone() {
  $('phone-refresh').addEventListener('click', refreshPhone);
  $('phone-prepare').addEventListener('click', function () { showStep('credit'); });
  var udevBtn = $('phone-udev');
  if (udevBtn) udevBtn.addEventListener('click', function () { showStep('udev'); });
  var usbBtn = $('phone-usb');
  if (usbBtn) usbBtn.addEventListener('click', function () { showStep('usb'); });
  refreshPhone();
}

function profileLabel(p) {
  if (!p) return '';
  if (p.label) return p.label;
  if (p.id === 'base') return 'Base';
  if (p.id === 'managed') return 'Managed';
  if (p.id === 'secure') return 'Secure';
  return p.id;
}

function renderProfiles() {
  var box = $('profile-list');
  if (!box || !PROFILES.data) return;
  box.textContent = '';
  PROFILES.list().forEach(function (p) {
    var card = document.createElement('button');
    card.type = 'button';
    card.className = 'profile-card' + (p.id === PROFILES.selectedId ? ' on' : '');
    card.disabled = p.enabled === false;
    var title = document.createElement('strong');
    title.textContent = profileLabel(p);
    card.appendChild(title);
    var sum = document.createElement('span');
    sum.className = 'profile-summary';
    sum.textContent = p.summary || '';
    card.appendChild(sum);
    if (p.warning) {
      var w = document.createElement('span');
      w.className = 'profile-warn';
      w.textContent = p.warning;
      card.appendChild(w);
    }
    if (p.enabled === false && p.reason) {
      var reason = document.createElement('span');
      reason.className = 'profile-reason';
      reason.textContent = p.reason;
      card.appendChild(reason);
    }
    if (p.enabled !== false) {
      card.addEventListener('click', function () { PROFILES.select(p.id); });
    }
    box.appendChild(card);
  });
  var cur = PROFILES.selected();
  if (cur && cur.flags && cur.flags.length && cur.enabled !== false) {
    var flags = document.createElement('div');
    flags.className = 'profile-flags';
    var heading = document.createElement('p');
    heading.className = 'note';
    heading.textContent = 'Managed: disable packages for this user (Apply writes profile.list).';
    flags.appendChild(heading);
    cur.flags.forEach(function (f) {
      var lab = document.createElement('label');
      lab.className = 'profile-flag';
      var input = document.createElement('input');
      input.type = 'checkbox';
      input.checked = PROFILES.flagState[f.id] !== false;
      input.addEventListener('change', function () {
        PROFILES.setFlag(f.id, input.checked);
      });
      lab.appendChild(input);
      var text = document.createElement('span');
      var strong = document.createElement('strong');
      strong.textContent = f.label || f.id;
      text.appendChild(strong);
      if (f.detail) {
        var detail = document.createElement('span');
        detail.className = 'profile-flag-detail';
        detail.textContent = f.detail;
        text.appendChild(detail);
      }
      lab.appendChild(text);
      flags.appendChild(lab);
    });
    box.appendChild(flags);
  }
  var label = cur ? profileLabel(cur) : PROFILES.selectedId;
  var note = $('inst-profile-note');
  if (note) {
    note.textContent = 'Profile: ' + label + '.';
  }
  setStatus('profile-msg', 'Selected: ' + label + '.', 'ok');
}

function initProfile() {
  renderProfiles();
  if (initProfile.bound) return;
  initProfile.bound = true;
  PROFILES.onChange(function () {
    renderProfiles();
    renderApps();
    if (typeof refreshDownloadGate === 'function') refreshDownloadGate();
  });
}

function appsLock() {
  if (appsBusy) return false;
  appsBusy = true;
  return true;
}

function appsUnlock() {
  appsBusy = false;
}

function bytesToB64(u8) {
  var bin = '';
  var chunk = 8192;
  var i, k, slice, args;
  for (i = 0; i < u8.length; i += chunk) {
    slice = u8.subarray(i, Math.min(i + chunk, u8.length));
    args = new Array(slice.length);
    for (k = 0; k < slice.length; k++) args[k] = slice[k];
    bin += String.fromCharCode.apply(null, args);
  }
  return btoa(bin);
}

function apkBytesFor(row) {
  var spec = APK_INCOMING[row.id];
  if (!spec) return { error: 'no single-install path for ' + row.label };
  if (spec.catalogId) {
    if (!VERIFIED[spec.catalogId]) {
      return { error: 'Verify ' + spec.catalogId + ' under Prepare, Files, first.' };
    }
    return { name: spec.name, bytes: new Uint8Array(VERIFIED[spec.catalogId]) };
  }
  if (!VERIFIED['installer-full']) {
    return { error: 'Verify installer-full under Prepare, Files, first.' };
  }
  var zip = fflate.unzipSync(new Uint8Array(VERIFIED['installer-full']));
  var entry = zip[spec.fromInstaller];
  if (!entry) return { error: 'installer zip is missing ' + spec.fromInstaller };
  return { name: spec.name, bytes: entry instanceof Uint8Array ? entry : new Uint8Array(entry) };
}

function appStatus(row) {
  if (row.kind === 'settings') return { text: 'with Apply', cls: '' };
  if (!APPS_STATE) return { text: 'not checked', cls: 'wait' };
  if (row.kind === 'module') {
    if (!APPS_STATE.modsKnown) return { text: 'not checked', cls: 'wait' };
    return APPS_STATE.mods[row.moduleId]
      ? { text: 'installed', cls: 'ok' }
      : { text: 'missing', cls: 'wait' };
  }
  if (row.packageName && APPS_STATE.pkgs[row.packageName]) return { text: 'installed', cls: 'ok' };
  return { text: 'missing', cls: 'wait' };
}

function parsePackages(text) {
  var pkgs = {};
  var lines = String(text || '').split('\n');
  var i, line, m;
  for (i = 0; i < lines.length; i++) {
    line = lines[i].replace(/\r/g, '').trim();
    m = /^package:(.+)$/.exec(line);
    if (m) pkgs[m[1].trim()] = true;
  }
  return pkgs;
}

function refreshAppsStatus(doneMsg) {
  var N = window.FLIP2_NATIVE;
  if (!N || !N.wizardHostShell) {
    APPS_STATE = null;
    renderApps();
    setStatus('apps-msg', 'Install, remove, and device owner need Flip 2 Companion.', 'wait');
    return;
  }
  if (!doneMsg) setStatus('apps-msg', 'reading the phone\u2026', 'wait');
  Promise.all([
    shellSoft('pm list packages'),
    shellSoft("su -c 'ls /data/adb/modules'")
  ]).then(function (parts) {
    APPS_STATE = {
      pkgs: parts[0].ok ? parsePackages(parts[0].out) : {},
      mods: {},
      modsKnown: parts[1].ok
    };
    if (parts[1].ok) {
      var lines = parts[1].out.split('\n');
      var i, id;
      for (i = 0; i < lines.length; i++) {
        id = lines[i].replace(/\r/g, '').trim();
        if (id && id.indexOf(' ') < 0 && id.indexOf('/') < 0) APPS_STATE.mods[id] = true;
      }
    }
    renderApps();
    if (!parts[0].ok) setStatus('apps-msg', parts[0].error || 'could not list packages', 'bad');
    else if (doneMsg) setStatus('apps-msg', doneMsg, 'ok');
    else setStatus('apps-msg', '', '');
  });
}

function renderApps() {
  var box = $('apps-rows');
  if (!box || !PROFILES.data) return;
  box.textContent = '';
  var rows = PROFILES.rows();
  var i;
  for (i = 0; i < rows.length; i++) {
    (function (row) {
      var rowEl = document.createElement('div');
      rowEl.className = 'app-row';
      var main = document.createElement('div');
      main.className = 'app-main';
      var title = document.createElement('strong');
      title.textContent = row.label;
      main.appendChild(title);
      var st = appStatus(row);
      var s = document.createElement('span');
      s.className = st.cls ? ('status ' + st.cls) : 'note';
      s.textContent = st.text;
      main.appendChild(s);
      rowEl.appendChild(main);
      var actions = document.createElement('div');
      actions.className = 'app-actions';
      if (row.kind === 'apk') {
        var inst = document.createElement('button');
        inst.type = 'button';
        inst.className = 'small';
        inst.textContent = 'Install';
        inst.addEventListener('click', function () { installOne(row); });
        actions.appendChild(inst);
      } else if (row.kind === 'module') {
        var instM = document.createElement('button');
        instM.type = 'button';
        instM.className = 'small ghost';
        instM.textContent = 'Install';
        instM.disabled = true;
        instM.title = 'Module install is part of Apply';
        actions.appendChild(instM);
      }
      if (row.kind === 'apk' || row.kind === 'module') {
        var rm = document.createElement('button');
        rm.type = 'button';
        rm.className = 'small ghost';
        rm.textContent = 'Remove';
        rm.addEventListener('click', function () { removeOne(row); });
        actions.appendChild(rm);
      }
      rowEl.appendChild(actions);
      box.appendChild(rowEl);
    })(rows[i]);
  }
  var owner = $('apps-owner');
  if (owner) owner.classList.toggle('hidden', PROFILES.selectedId !== 'managed');
  var warn = $('apps-owner-warn');
  if (warn && PROFILES.selectedId === 'managed') {
    var p = PROFILES.selected();
    warn.textContent = (p && p.warning) || '';
  }
}

function installOne(row) {
  var N = window.FLIP2_NATIVE;
  if (row.kind === 'module') {
    setStatus('apps-msg', 'Module install is part of Apply.', 'wait');
    return;
  }
  if (row.kind !== 'apk') {
    setStatus('apps-msg', row.label + ' is applied with the profile.', 'wait');
    return;
  }
  if (!N || !N.wizardHostPushOne || !N.wizardHostInstallApk) {
    setStatus('apps-msg', 'installing one app requires Flip 2 Companion', 'bad');
    return;
  }
  var got;
  try {
    got = apkBytesFor(row);
  } catch (e) {
    setStatus('apps-msg', cleanErr(e), 'bad');
    return;
  }
  if (!got || got.error) {
    setStatus('apps-msg', (got && got.error) || 'nothing to install', 'bad');
    return;
  }
  if (!appsLock()) return;
  var log = makeLog('apps-log');
  setStatus('apps-msg', 'staging ' + got.name + '\u2026', 'wait');
  log('staging ' + got.name);
  var bytes = got.bytes instanceof Uint8Array ? got.bytes : new Uint8Array(got.bytes);
  N.wizardHostPushOne({ name: got.name, dataBase64: bytesToB64(bytes) }).then(function () {
    log('OK: staged ' + got.name);
    return N.wizardHostInstallApk({ name: got.name });
  }).then(function (r) {
    if (!r || r.ok === false) throw new Error((r && r.error) || 'install failed');
    log('OK: installed ' + (row.packageName || got.name));
    refreshAppsStatus(row.label + ' installed. Device owner is a separate step.');
  }).catch(function (e) {
    setStatus('apps-msg', cleanErr(e), 'bad');
  }).then(function () { appsUnlock(); });
}

function policyBlocked(msg) {
  return msg && String(msg).indexOf('DELETE_FAILED_DEVICE_POLICY_MANAGER') >= 0;
}

function removeOne(row) {
  var N = window.FLIP2_NATIVE;
  if (row.kind === 'settings') return;
  if (!N || (row.kind === 'apk' && !N.wizardHostUninstallPackage) || (row.kind === 'module' && !N.wizardHostRemoveModule)) {
    setStatus('apps-msg', 'removing an app requires Flip 2 Companion', 'bad');
    return;
  }
  if (row.extraConfirm && !window.confirm(row.extraConfirm)) return;
  if (!appsLock()) return;
  setStatus('apps-msg', 'removing ' + row.label + '\u2026', 'wait');
  var pending = row.kind === 'module'
    ? N.wizardHostRemoveModule({ moduleId: row.moduleId })
    : N.wizardHostUninstallPackage({ packageName: row.packageName });
  pending.then(function (r) {
    if (!r || r.ok === false) {
      var err = (r && r.error) || 'remove failed';
      if (policyBlocked(err)) {
        setStatus('apps-msg', 'DELETE_FAILED_DEVICE_POLICY_MANAGER. Device owner or admin policy blocked uninstall. Stopped. See docs/HEADWIND-MDM-RECOVERY.md. This app does not edit device_policies.xml.', 'bad');
        return;
      }
      throw new Error(err);
    }
    if (row.kind === 'module') {
      refreshAppsStatus((r && r.message) || 'Module removed. Reboot the phone before expecting it to stay gone.');
    } else {
      refreshAppsStatus(row.label + ' removed.');
    }
  }).catch(function (e) {
    var err = cleanErr(e);
    if (policyBlocked(err)) {
      setStatus('apps-msg', 'DELETE_FAILED_DEVICE_POLICY_MANAGER. Device owner or admin policy blocked uninstall. Stopped. See docs/HEADWIND-MDM-RECOVERY.md. This app does not edit device_policies.xml.', 'bad');
      return;
    }
    setStatus('apps-msg', err, 'bad');
  }).then(function () { appsUnlock(); });
}

function setDeviceOwner() {
  var N = window.FLIP2_NATIVE;
  var btn = $('apps-owner-btn');
  if (!N || !N.wizardHostSetDeviceOwner) {
    setStatus('apps-owner-msg', 'device owner requires Flip 2 Companion', 'bad');
    return;
  }
  if ($('apps-owner-input').value.trim() !== 'manage') return;
  if (!appsLock()) return;
  btn.disabled = true;
  setStatus('apps-owner-msg', 'setting device owner\u2026', 'wait');
  N.wizardHostSetDeviceOwner({ confirm: 'manage' }).then(function (r) {
    if (!r || r.ok === false) {
      setStatus('apps-owner-msg', (r && r.error) || 'device owner was not set', 'bad');
      return;
    }
    setStatus('apps-owner-msg', 'Device owner set: ' + (r.component || 'com.hmdm.launcher/.AdminReceiver') + '.', 'ok');
    refreshPhone();
  }).catch(function (e) {
    setStatus('apps-owner-msg', cleanErr(e), 'bad');
  }).then(function () {
    appsUnlock();
    btn.disabled = $('apps-owner-input').value.trim() !== 'manage';
  });
}

function dropRootAdb() {
  var N = window.FLIP2_NATIVE;
  var btn = $('apps-unroot-btn');
  if (!N || !N.wizardHostDropRootAdb) {
    setStatus('apps-unroot-msg', 'removing root requires Flip 2 Companion', 'bad');
    return;
  }
  if ($('apps-unroot-input').value.trim() !== 'unroot') return;
  if (!appsLock()) return;
  btn.disabled = true;
  setStatus('apps-unroot-msg', 'removing root and turning off USB debugging\u2026', 'wait');
  N.wizardHostDropRootAdb({ confirm: 'unroot' }).then(function (r) {
    if (!r || r.ok === false) {
      setStatus('apps-unroot-msg', (r && r.error) || 'root was not removed', 'bad');
      return;
    }
    setStatus('apps-unroot-msg', r.message || 'Root modules were marked and USB debugging was turned off.', 'ok');
  }).catch(function (e) {
    setStatus('apps-unroot-msg', cleanErr(e), 'bad');
  }).then(function () {
    appsUnlock();
    btn.disabled = $('apps-unroot-input').value.trim() !== 'unroot';
  });
}

function runAppsVerify() {
  showStep('verify');
  if (!VERIFY_SH) {
    setStatus('ver-msg', 'verify.sh is still loading', 'wait');
    return;
  }
  $('ver-btn').click();
}

function initApps() {
  renderApps();
  $('apps-refresh').addEventListener('click', function () { refreshAppsStatus(); });
  $('apps-apply').addEventListener('click', function () {
    showStep('install');
    openInstallModal();
  });
  $('apps-verify').addEventListener('click', runAppsVerify);
  var verifyTop = $('apps-verify-top');
  if (verifyTop) verifyTop.addEventListener('click', runAppsVerify);
  var input = $('apps-owner-input');
  var obtn = $('apps-owner-btn');
  input.addEventListener('input', function () {
    obtn.disabled = input.value.trim() !== 'manage';
  });
  obtn.addEventListener('click', setDeviceOwner);
  var unrootInput = $('apps-unroot-input');
  var unrootBtn = $('apps-unroot-btn');
  unrootInput.addEventListener('input', function () {
    unrootBtn.disabled = unrootInput.value.trim() !== 'unroot';
  });
  unrootBtn.addEventListener('click', dropRootAdb);
  refreshAppsStatus();
}

function initPersonalBackup() {
  var N = window.FLIP2_NATIVE || {};
  var savedInfoGen = 0;

  function ntext(n) {
    return (typeof n === 'number' && isFinite(n) && Math.floor(n) === n) ? String(n) : '?';
  }

  function contactsCounts(c) {
    if (!c) return 'none saved';
    return ntext(c.named) + ' named, ' + ntext(c.blankNames) + ' blank, ' + ntext(c.data) + ' data';
  }

  function messagesCounts(m) {
    if (!m) return 'none saved';
    return ntext(m.sms) + ' sms, ' + ntext(m.threads) + ' threads, ' + ntext(m.inbox) + ' inbox, ' + ntext(m.sent) + ' sent';
  }

  function say(text, cls) {
    setStatus('apps-backup-msg', text, cls);
  }

  function failText(r) {
    var parts = [];
    var i;
    if (r && typeof r.error === 'string' && r.error) parts.push(r.error);
    if (r && typeof r.installed === 'number' && r.failed && r.failed.length) {
      parts.push(ntext(r.installed) + ' installed');
    }
    if (r && r.failed && r.failed.length) {
      for (i = 0; i < r.failed.length; i++) {
        var item = r.failed[i] || {};
        var name = (typeof item.packageName === 'string' && item.packageName) ? item.packageName : 'package';
        var err = (typeof item.error === 'string' && item.error) ? item.error : 'install failed';
        parts.push(name + ': ' + err);
      }
    }
    return parts.length ? parts.join('. ') : 'personal backup failed';
  }

  function paintBackupInfo(r) {
    var info = $('apps-backup-info');
    if (!info) return;
    if (!r || r.ok === false) {
      info.textContent = (r && typeof r.error === 'string' && r.error) ? r.error : 'No saved backup read yet.';
      return;
    }
    info.textContent = 'Contacts: ' + contactsCounts(r.contacts) +
      '. Messages: ' + messagesCounts(r.messages) +
      '. Apps: ' + ntext(r.apps) +
      '. Pre-wipe readable backup: ' + (r.prewipe ? 'yes' : 'no') + '.';
  }

  function refreshSaved(fromClick) {
    var info = $('apps-backup-info');
    if (typeof N.personalBackupInfo !== 'function') {
      if (info) info.textContent = 'Open this page in Flip 2 Companion. Relaunch Companion if this window was already open.';
      return;
    }
    var gen = ++savedInfoGen;
    if (fromClick && !appsBusy) say('Reading the saved backup\u2026', 'wait');
    N.personalBackupInfo().then(function (r) {
      if (gen !== savedInfoGen) return;
      paintBackupInfo(r);
      if (!fromClick || appsBusy) return;
      if (!r || r.ok === false) say(failText(r), 'bad');
      else say('Saved backup updated.', 'ok');
    }).catch(function (e) {
      if (gen !== savedInfoGen) return;
      var msg = cleanErr(e);
      if (info) info.textContent = msg;
      if (fromClick && !appsBusy) say(msg, 'bad');
    });
  }

  function arm(id, methodName) {
    var btn = $(id);
    if (!btn) return null;
    if (typeof N[methodName] !== 'function') {
      btn.disabled = true;
      return null;
    }
    return btn;
  }

  function runPersonal(btn, waitText, call, okText) {
    if (!btn || btn.disabled) return;
    if (!appsLock()) {
      say('Another Apps action is still running.', 'wait');
      return;
    }
    btn.disabled = true;
    say(waitText, 'wait');
    Promise.resolve().then(call).then(function (r) {
      if (!r || r.ok === false) {
        say(failText(r), 'bad');
        return;
      }
      say(okText(r), 'ok');
    }).catch(function (e) {
      say(cleanErr(e), 'bad');
    }).then(function () {
      appsUnlock();
      btn.disabled = false;
      refreshSaved(false);
    });
  }

  var refreshBtn = arm('apps-backup-refresh', 'personalBackupInfo');
  if (refreshBtn) refreshBtn.addEventListener('click', function () { refreshSaved(true); });

  var backupContacts = arm('apps-backup-contacts', 'personalBackupContacts');
  if (backupContacts) backupContacts.addEventListener('click', function () {
    runPersonal(backupContacts, 'Backing up contacts\u2026', function () {
      return N.personalBackupContacts();
    }, function (r) {
      return 'Contacts saved. ' + contactsCounts(r.contacts) + '.';
    });
  });

  var backupMessages = arm('apps-backup-messages', 'personalBackupMessages');
  if (backupMessages) backupMessages.addEventListener('click', function () {
    runPersonal(backupMessages, 'Backing up messages\u2026', function () {
      return N.personalBackupMessages();
    }, function (r) {
      return 'Messages saved. ' + messagesCounts(r.messages) + '.';
    });
  });

  var backupApps = arm('apps-backup-apps', 'personalBackupApps');
  if (backupApps) backupApps.addEventListener('click', function () {
    runPersonal(backupApps, 'Backing up apps\u2026', function () {
      return N.personalBackupApps();
    }, function (r) {
      return 'Apps saved: ' + ntext(r.apps) + '.';
    });
  });

  var restoreContacts = arm('apps-restore-contacts', 'personalRestoreContacts');
  if (restoreContacts) restoreContacts.addEventListener('click', function () {
    runPersonal(restoreContacts, 'Restoring saved contacts\u2026', function () {
      return N.personalRestoreContacts({ source: 'saved' });
    }, function (r) {
      return 'Contacts restored. ' + contactsCounts(r.contacts) + '.';
    });
  });

  var restoreMessages = arm('apps-restore-messages', 'personalRestoreMessages');
  if (restoreMessages) restoreMessages.addEventListener('click', function () {
    runPersonal(restoreMessages, 'Restoring saved messages\u2026', function () {
      return N.personalRestoreMessages({ source: 'saved' });
    }, function (r) {
      return 'Messages restored. ' + messagesCounts(r.messages) + '.';
    });
  });

  var restoreApps = arm('apps-restore-apps', 'personalRestoreApps');
  if (restoreApps) restoreApps.addEventListener('click', function () {
    runPersonal(restoreApps, 'Restoring saved apps\u2026', function () {
      return N.personalRestoreApps();
    }, function (r) {
      return 'Apps restored. ' + ntext(r.installed) + ' installed.';
    });
  });

  var prewipeContacts = arm('apps-restore-prewipe-contacts', 'personalRestoreContacts');
  if (prewipeContacts) prewipeContacts.addEventListener('click', function () {
    runPersonal(prewipeContacts, 'Restoring pre-wipe contacts\u2026', function () {
      return N.personalRestoreContacts({ source: 'prewipe' });
    }, function (r) {
      return 'Pre-wipe contacts restored. ' + contactsCounts(r.contacts) + '.';
    });
  });

  var prewipeMessages = arm('apps-restore-prewipe-messages', 'personalRestoreMessages');
  if (prewipeMessages) prewipeMessages.addEventListener('click', function () {
    runPersonal(prewipeMessages, 'Restoring pre-wipe messages\u2026', function () {
      return N.personalRestoreMessages({ source: 'prewipe' });
    }, function (r) {
      return 'Pre-wipe messages restored. ' + messagesCounts(r.messages) + '.';
    });
  });

  refreshSaved(false);
}
