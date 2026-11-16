/* Device: sideload, user apps, push, shell, screenshot, and keys.
   WebUSB when ADB.connected; Companion host adb otherwise.
   /sdcard/Download stays here — it is not a device-paths key. */

var DEVICE_DOWNLOAD = '/sdcard/Download';
var DEVICE_SCREEN_PNG = '/sdcard/Download/flip2-screen.png';
var DEVICE_TYPED_PKGS = {
  'com.tim.flip2.launcher4': true,
  'com.tim.flip2.nullkeyboard': true
};
var DEVICE_KEYS = { 1: true, 2: true, 4: true, 5: true, 6: true, 19: true, 20: true, 21: true, 22: true, 23: true };
var DEVICE_SHELL_DENY = ['wipe', 'fastboot', 'recovery', 'format', 'mkfs'];

var deviceUserPackages = [];
var deviceUninstallArmed = '';
var deviceShotUrl = '';
var deviceBusy = false;
var deviceReady = false;

function deviceTransport() {
  if (typeof ADB !== 'undefined' && ADB && ADB.connected) return 'webusb';
  if (window.FLIP2_NATIVE) return 'host';
  return 'none';
}

function deviceShellDenied(cmd) {
  var low = String(cmd || '').toLowerCase();
  var i;
  for (i = 0; i < DEVICE_SHELL_DENY.length; i++) {
    if (low.indexOf(DEVICE_SHELL_DENY[i]) >= 0) return true;
  }
  return false;
}

function deviceIsReboot(cmd) {
  return /^\s*reboot(\s|$)/.test(String(cmd || ''));
}

function deviceQuote(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'";
}

function deviceBaseName(name) {
  var base = String(name || '').replace(/\\/g, '/').split('/').pop();
  if (!base || base === '.' || base === '..' || base.indexOf('/') >= 0 || base.indexOf('\\') >= 0) {
    throw new Error('file name must be a single name, not a path');
  }
  return base;
}

function devicePkgOk(name) {
  return /^[A-Za-z0-9._]+$/.test(name) && name.indexOf('..') < 0;
}

function deviceStageApk() {
  if (typeof DP === 'undefined' || !DP || !DP.shellStaging) {
    throw new Error('device paths are not loaded');
  }
  return DP.shellStaging + '/user-install.apk';
}

function devicePermError(res) {
  var t = ((res && res.text) || '').toLowerCase();
  return t.indexOf('permission') >= 0 || t.indexOf('not allowed') >= 0 || t.indexOf('operation not permitted') >= 0;
}

function deviceIsPng(bytes) {
  return bytes && bytes.length >= 8 &&
    bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47;
}

function deviceBytesToBase64(bytes) {
  var chunk = 0x8000;
  var parts = [];
  var i;
  for (i = 0; i < bytes.length; i += chunk) {
    parts.push(String.fromCharCode.apply(null, bytes.subarray(i, i + chunk)));
  }
  return btoa(parts.join(''));
}

function deviceBase64ToBytes(b64) {
  var bin = atob(b64 || '');
  var out = new Uint8Array(bin.length);
  var i;
  for (i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i) & 0xff;
  return out;
}

function deviceNormalizeShell(res) {
  if (!res || typeof res !== 'object') throw new Error('no shell result');
  return {
    code: typeof res.code === 'number' ? res.code : 1,
    text: res.text != null ? String(res.text) : ''
  };
}

function deviceReadFile(file) {
  return file.arrayBuffer().then(function (buf) {
    return new Uint8Array(buf);
  });
}

function deviceStatus(el, text, kind) {
  if (typeof el === 'string') el = $(el);
  if (!el) return;
  el.textContent = text || '';
  el.className = 'status' + (kind ? ' ' + kind : '');
}

function deviceErrText(err) {
  if (typeof cleanErr === 'function') return cleanErr(err);
  return (err && err.message) || String(err);
}

function deviceFail(el, err) {
  deviceStatus(el, deviceErrText(err), 'bad');
}

function deviceLog(text) {
  var pre = $('device-shell-log');
  if (!pre) return;
  pre.classList.remove('hidden');
  pre.textContent += (pre.textContent ? '\n' : '') + text;
  pre.scrollTop = pre.scrollHeight;
}

function deviceRebootDrop(err) {
  var msg = String((err && err.message) || err || '');
  return /no exit status|stall|disconnect|transfer|device offline|closed/i.test(msg);
}

function deviceText(cmd, timeoutMs) {
  var ms = timeoutMs || 30000;
  if (ms > 60000) ms = 60000;
  var transport = deviceTransport();
  if (transport === 'none') {
    return Promise.reject(new Error('Use Chrome and Connect phone, or open Flip2 Companion.'));
  }
  if (transport === 'webusb') {
    return ADB.shellText(cmd, { idleTimeoutMs: ms }).catch(function (err) {
      if (deviceIsReboot(cmd) && deviceRebootDrop(err)) {
        return { code: 0, text: 'reboot sent (USB dropped)' };
      }
      throw err;
    });
  }
  if (!window.FLIP2_NATIVE || typeof window.FLIP2_NATIVE.deviceShell !== 'function') {
    return Promise.reject(new Error('Companion is missing Device controls'));
  }
  return window.FLIP2_NATIVE.deviceShell({ cmd: cmd, timeoutMs: ms }).then(deviceNormalizeShell);
}

function deviceUserShell(cmd, timeoutMs) {
  if (deviceShellDenied(cmd)) {
    return Promise.reject(new Error('that command is not allowed from Device'));
  }
  return deviceText(cmd, timeoutMs);
}

function deviceBegin() {
  if (deviceBusy) return false;
  if (deviceTransport() === 'none') return false;
  deviceBusy = true;
  var buttons = document.querySelectorAll('#step-device button[data-device-action]');
  var i;
  for (i = 0; i < buttons.length; i++) buttons[i].disabled = true;
  return true;
}

function deviceEnd() {
  deviceBusy = false;
  refreshDeviceTransport();
}

function refreshDeviceTransport() {
  var kind = deviceTransport();
  var msg = $('device-transport');
  var connect = $('device-connect');
  var buttons;
  var i;
  if (connect) {
    if (window.FLIP2_NATIVE) connect.classList.add('hidden');
    else connect.classList.remove('hidden');
  }
  if (!deviceBusy) {
    buttons = document.querySelectorAll('#step-device button[data-device-action]');
    for (i = 0; i < buttons.length; i++) buttons[i].disabled = kind === 'none';
  }
  if (!msg) return;
  if (kind === 'webusb') deviceStatus(msg, 'WebUSB', 'ok');
  else if (kind === 'host') deviceStatus(msg, 'Companion adb', 'ok');
  else deviceStatus(msg, 'Use Chrome and Connect phone, or open Flip2 Companion.', 'wait');
}

function deviceShellTimeoutMs() {
  var raw = parseInt($('device-shell-timeout').value, 10);
  if (!raw || raw < 1) raw = 30;
  if (raw > 60) raw = 60;
  return raw * 1000;
}

function deviceSelectedPkg() {
  var sel = $('device-pkg');
  if (!sel) return '';
  return sel.value || '';
}

function deviceRenderPackages() {
  var sel = $('device-pkg');
  var i;
  var opt;
  if (!sel) return;
  sel.innerHTML = '';
  if (!deviceUserPackages.length) {
    opt = document.createElement('option');
    opt.value = '';
    opt.textContent = '(no user apps)';
    sel.appendChild(opt);
    return;
  }
  for (i = 0; i < deviceUserPackages.length; i++) {
    opt = document.createElement('option');
    opt.value = deviceUserPackages[i];
    opt.textContent = deviceUserPackages[i];
    sel.appendChild(opt);
  }
}

function deviceSyncUninstallBtn() {
  var btn = $('device-uninstall');
  var pkg = deviceSelectedPkg();
  if (!btn) return;
  if (pkg && deviceUninstallArmed === pkg && !DEVICE_TYPED_PKGS[pkg]) btn.textContent = 'Confirm uninstall';
  else btn.textContent = 'Uninstall';
}

function deviceRmRemote(remote) {
  if (typeof ADB === 'undefined' || !ADB || !ADB.connected) return Promise.resolve();
  return ADB.shellText('rm -f ' + deviceQuote(remote), { idleTimeoutMs: 20000 }).then(function () {}, function () {});
}

function deviceInstallWeb(bytes) {
  var remote = deviceStageApk();
  var dir = DP.shellStaging;
  return ADB.shellText('mkdir -p ' + deviceQuote(dir)).then(function (res) {
    if (res.code !== 0) throw new Error((res.text || 'could not create staging dir').trim());
    return ADB.pushFile(remote, '0644', bytes);
  }).then(function () {
    return ADB.shellText('pm install -r ' + deviceQuote(remote), { idleTimeoutMs: 180000 });
  }).then(function (res) {
    if (res.code !== 0 && devicePermError(res)) {
      var inner = 'pm install -r ' + deviceQuote(remote);
      return ADB.shellText('su 0 sh -c ' + deviceQuote(inner), { idleTimeoutMs: 180000 });
    }
    return res;
  }).then(function (res) {
    return deviceRmRemote(remote).then(function () { return res; });
  }, function (err) {
    return deviceRmRemote(remote).then(function () { throw err; });
  });
}

function deviceInstall(file) {
  var transport = deviceTransport();
  if (!file) return Promise.reject(new Error('pick an apk'));
  if (!/\.apk$/i.test(file.name || '')) return Promise.reject(new Error('pick an .apk file'));
  return deviceReadFile(file).then(function (bytes) {
    if (!bytes.length) throw new Error('apk is empty');
    if (transport === 'webusb') return deviceInstallWeb(bytes);
    if (!window.FLIP2_NATIVE || typeof window.FLIP2_NATIVE.deviceInstallApk !== 'function') {
      throw new Error('Companion is missing Device controls');
    }
    return window.FLIP2_NATIVE.deviceInstallApk({ dataBase64: deviceBytesToBase64(bytes) }).then(deviceNormalizeShell);
  });
}

function deviceShowResult(el, res) {
  var text = (res.text || '').trim();
  if (res.code === 0) deviceStatus(el, text || 'done', 'ok');
  else deviceStatus(el, text || ('failed (' + res.code + ')'), 'bad');
}

function deviceOnInstall() {
  var input = $('device-install-file');
  var msg = $('device-install-msg');
  var file = input && input.files && input.files[0];
  if (!file) {
    deviceStatus(msg, 'Pick an apk.', 'wait');
    return;
  }
  if (!deviceBegin()) return;
  deviceStatus(msg, 'installing…', 'wait');
  deviceInstall(file).then(function (res) {
    deviceShowResult(msg, res);
  }, function (err) {
    deviceFail(msg, err);
  }).then(deviceEnd, deviceEnd);
}

function deviceParsePackages(text) {
  var pkgs = [];
  var lines = String(text || '').split('\n');
  var i, line, name;
  for (i = 0; i < lines.length; i++) {
    line = lines[i].trim();
    if (line.indexOf('package:') !== 0) continue;
    name = line.slice(8).trim().split(/\s+/)[0];
    if (devicePkgOk(name) && pkgs.indexOf(name) < 0) pkgs.push(name);
  }
  pkgs.sort();
  return pkgs;
}

function deviceOnRefreshApps() {
  var msg = $('device-apps-msg');
  if (!deviceBegin()) return;
  deviceStatus(msg, 'listing…', 'wait');
  deviceText('pm list packages -3', 30000).then(function (res) {
    if (res.code !== 0) throw new Error((res.text || 'pm list failed').trim());
    deviceUserPackages = deviceParsePackages(res.text);
    deviceUninstallArmed = '';
    deviceRenderPackages();
    deviceSyncUninstallBtn();
    deviceStatus(msg, deviceUserPackages.length ? (deviceUserPackages.length + ' user apps') : 'no user apps', 'ok');
  }, function (err) {
    deviceFail(msg, err);
  }).then(deviceEnd, deviceEnd);
}

function deviceOnUninstall() {
  var msg = $('device-apps-msg');
  var pkg = deviceSelectedPkg();
  var typed;
  if (!pkg || deviceUserPackages.indexOf(pkg) < 0) {
    deviceStatus(msg, 'Refresh the list, then pick a package that is on it.', 'wait');
    return;
  }
  if (!devicePkgOk(pkg)) {
    deviceStatus(msg, 'Package name is not safe.', 'bad');
    return;
  }
  if (DEVICE_TYPED_PKGS[pkg]) {
    typed = ($('device-pkg-type').value || '').trim();
    if (typed !== pkg) {
      deviceStatus(msg, 'Type ' + pkg + ' to remove it.', 'wait');
      return;
    }
  } else if (deviceUninstallArmed !== pkg) {
    deviceUninstallArmed = pkg;
    deviceSyncUninstallBtn();
    deviceStatus(msg, 'Click Confirm uninstall to remove ' + pkg + '.', 'wait');
    return;
  }
  deviceUninstallArmed = '';
  deviceSyncUninstallBtn();
  if (!deviceBegin()) return;
  deviceStatus(msg, 'removing ' + pkg + '…', 'wait');
  deviceUninstall(pkg).then(function (res) {
    deviceShowResult(msg, res);
    if (res.code !== 0) return null;
    return deviceText('pm list packages -3', 30000).then(function (listRes) {
      if (listRes.code !== 0) throw new Error((listRes.text || 'pm list failed').trim());
      deviceUserPackages = deviceParsePackages(listRes.text);
      deviceUninstallArmed = '';
      deviceRenderPackages();
      deviceSyncUninstallBtn();
      deviceStatus(msg, deviceUserPackages.length ? (deviceUserPackages.length + ' user apps') : 'no user apps', 'ok');
    });
  }, function (err) {
    deviceFail(msg, err);
  }).then(deviceEnd, deviceEnd);
}

function deviceUninstall(pkg) {
  if (deviceTransport() === 'webusb') {
    return ADB.shellText('pm uninstall ' + deviceQuote(pkg), { idleTimeoutMs: 60000 });
  }
  if (!window.FLIP2_NATIVE || typeof window.FLIP2_NATIVE.deviceUninstallPackage !== 'function') {
    return Promise.reject(new Error('Companion is missing Device controls'));
  }
  return window.FLIP2_NATIVE.deviceUninstallPackage({ package: pkg }).then(deviceNormalizeShell);
}

function deviceOnPush() {
  var input = $('device-push-file');
  var msg = $('device-push-msg');
  var file = input && input.files && input.files[0];
  var base;
  var dest;
  if (!file) {
    deviceStatus(msg, 'Pick a file.', 'wait');
    return;
  }
  try {
    base = deviceBaseName(file.name);
    dest = DEVICE_DOWNLOAD + '/' + base;
  } catch (err) {
    deviceFail(msg, err);
    return;
  }
  if (!deviceBegin()) return;
  deviceStatus(msg, 'pushing ' + base + '…', 'wait');
  deviceReadFile(file).then(function (bytes) {
    if (!bytes.length) throw new Error('file is empty');
    if (deviceTransport() === 'webusb') {
      return ADB.shellText('mkdir -p ' + deviceQuote(DEVICE_DOWNLOAD)).then(function (res) {
        if (res.code !== 0) throw new Error((res.text || 'could not create Download').trim());
        return ADB.pushFile(dest, '0644', bytes);
      }).then(function () {
        return { code: 0, text: dest };
      });
    }
    if (!window.FLIP2_NATIVE || typeof window.FLIP2_NATIVE.devicePushFile !== 'function') {
      throw new Error('Companion is missing Device controls');
    }
    return window.FLIP2_NATIVE.devicePushFile({
      name: base,
      dataBase64: deviceBytesToBase64(bytes)
    }).then(deviceNormalizeShell);
  }).then(function (res) {
    deviceShowResult(msg, res);
  }, function (err) {
    deviceFail(msg, err);
  }).then(deviceEnd, deviceEnd);
}

function deviceOnShell() {
  var cmd = $('device-shell-cmd').value || '';
  var msg = $('device-shell-msg');
  var ms;
  if (!cmd.trim()) {
    deviceStatus(msg, 'Enter a command.', 'wait');
    return;
  }
  if (deviceShellDenied(cmd)) {
    deviceStatus(msg, 'That command is not allowed from Device.', 'bad');
    return;
  }
  ms = deviceShellTimeoutMs();
  if (!deviceBegin()) return;
  deviceLog('$ ' + cmd);
  deviceStatus(msg, 'running…', 'wait');
  deviceUserShell(cmd, ms).then(function (res) {
    if (res.text) deviceLog(res.text);
    deviceStatus(msg, 'exit ' + res.code, res.code === 0 ? 'ok' : 'bad');
  }, function (err) {
    deviceLog(deviceErrText(err));
    deviceFail(msg, err);
  }).then(deviceEnd, deviceEnd);
}

function deviceShotWebFile() {
  return ADB.shellText('screencap -p ' + deviceQuote(DEVICE_SCREEN_PNG), { idleTimeoutMs: 30000 }).then(function (res) {
    if (res.code !== 0) throw new Error((res.text || 'screencap failed').trim());
    return ADB.pullFile(DEVICE_SCREEN_PNG);
  }).then(function (bytes) {
    return deviceRmRemote(DEVICE_SCREEN_PNG).then(function () { return bytes; });
  });
}

function deviceShotWeb() {
  return ADB.execBytes('screencap -p', { idleTimeoutMs: 30000 }).then(function (bytes) {
    if (deviceIsPng(bytes)) return bytes;
    return deviceShotWebFile();
  }, function () {
    return deviceShotWebFile();
  }).then(function (bytes) {
    if (!deviceIsPng(bytes)) throw new Error('screenshot was not a PNG');
    return bytes;
  });
}

function deviceShowShot(bytes) {
  var img = $('device-shot');
  var blob;
  if (!img) return;
  if (deviceShotUrl) {
    URL.revokeObjectURL(deviceShotUrl);
    deviceShotUrl = '';
  }
  blob = new Blob([bytes], { type: 'image/png' });
  deviceShotUrl = URL.createObjectURL(blob);
  img.src = deviceShotUrl;
  img.classList.remove('hidden');
}

function deviceOnShot() {
  var msg = $('device-shot-msg');
  if (!deviceBegin()) return;
  deviceStatus(msg, 'taking screenshot…', 'wait');
  var transport = deviceTransport();
  var pending;
  if (transport === 'webusb') pending = deviceShotWeb();
  else if (window.FLIP2_NATIVE && typeof window.FLIP2_NATIVE.deviceScreencap === 'function') {
    pending = window.FLIP2_NATIVE.deviceScreencap().then(function (res) {
      var b64 = typeof res === 'string' ? res : (res && res.dataBase64);
      var bytes = deviceBase64ToBytes(b64 || '');
      if (!deviceIsPng(bytes)) throw new Error('screenshot was not a PNG');
      return bytes;
    });
  } else {
    pending = Promise.reject(new Error('Companion is missing Device controls'));
  }
  pending.then(function (bytes) {
    deviceShowShot(bytes);
    deviceStatus(msg, 'screenshot', 'ok');
  }, function (err) {
    deviceFail(msg, err);
  }).then(deviceEnd, deviceEnd);
}

function deviceOnKey(code) {
  var msg = $('device-key-msg');
  if (!DEVICE_KEYS[code]) {
    deviceStatus(msg, 'Key is not allowed.', 'bad');
    return;
  }
  if (!deviceBegin()) return;
  deviceStatus(msg, 'key ' + code + '…', 'wait');
  var pending;
  if (deviceTransport() === 'webusb') {
    pending = ADB.shellText('input keyevent ' + code, { idleTimeoutMs: 15000 });
  } else if (window.FLIP2_NATIVE && typeof window.FLIP2_NATIVE.deviceKey === 'function') {
    pending = window.FLIP2_NATIVE.deviceKey({ code: code }).then(deviceNormalizeShell);
  } else {
    pending = Promise.reject(new Error('Companion is missing Device controls'));
  }
  pending.then(function (res) {
    if (res.code !== 0) deviceShowResult(msg, res);
    else deviceStatus(msg, 'key ' + code, 'ok');
  }, function (err) {
    deviceFail(msg, err);
  }).then(deviceEnd, deviceEnd);
}

function initDevice() {
  var keys;
  var i;
  if (deviceReady) return;
  if (!$('step-device')) throw new Error('device section is missing');
  deviceReady = true;

  $('device-connect').addEventListener('click', function () {
    var btn = $('get-ready-connect');
    if (btn) btn.click();
  });
  $('device-install-btn').addEventListener('click', deviceOnInstall);
  $('device-apps-refresh').addEventListener('click', deviceOnRefreshApps);
  $('device-uninstall').addEventListener('click', deviceOnUninstall);
  $('device-pkg').addEventListener('change', function () {
    deviceUninstallArmed = '';
    deviceSyncUninstallBtn();
  });
  $('device-push-btn').addEventListener('click', deviceOnPush);
  $('device-shell-btn').addEventListener('click', deviceOnShell);
  $('device-shell-cmd').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') {
      e.preventDefault();
      deviceOnShell();
    }
  });
  $('device-shot-btn').addEventListener('click', deviceOnShot);
  keys = document.querySelectorAll('#device-keys button[data-key]');
  for (i = 0; i < keys.length; i++) {
    keys[i].addEventListener('click', function (e) {
      deviceOnKey(parseInt(e.currentTarget.getAttribute('data-key'), 10));
    });
  }
  refreshDeviceTransport();
}
