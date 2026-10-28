// Flip 2 Companion — Electron shell around the wizard pages.
// Serves wizard/ over a custom protocol, chooses the phone on the WebUSB and
// Web Serial dialogs, and installs the udev rules through pkexec so step 3
// is one click instead of a sudo recipe.

const { app, BrowserWindow, ipcMain, protocol, session, shell, net } = require('electron');
const { execFile } = require('child_process');
const fs = require('fs');
const fsp = require('fs').promises;
const os = require('os');
const path = require('path');
const pick = require('./device-pick');

const WIZARD = path.join(__dirname, '..', 'wizard');
const RULES_NAME = '51-android-flip2-adb.rules';
const RULES_DST = path.join('/etc/udev/rules.d', RULES_NAME);

// Catalog files land here when the wizard downloads them in-app, so a retry
// does not re-fetch 290 MB. Computed lazily: app.getPath needs a live app.
function downloadDir() { return path.join(app.getPath('downloads'), 'flip2-wizard'); }

// Folders searched by "use files already on this PC". Ordered by preference.
function localRoots() {
  return [
    downloadDir(),
    app.getPath('downloads'),
    path.join(os.homedir(), 'flip2-wizard-test-2026-10-27', 'downloads'),
  ];
}

function insideLocalRoots(real) {
  return localRoots().some(function (root) {
    let realRoot;
    try { realRoot = fs.realpathSync(root); } catch (e) { return false; }
    return real === realRoot || real.startsWith(realRoot + path.sep);
  });
}

// Live USB state for the wizard's "what the phone is doing" panel. This only
// reads sysfs; it never opens a device, so it cannot disturb the handshake.
const USB_SYS = '/sys/bus/usb/devices';
const USB_MODES = {
  '0e8d:2000': 'preloader',
  '0e8d:201c': 'fastboot',
  '0e8d:0003': 'bootrom',
  '1bbb:0167': 'android',
  '1bbb:0c01': 'android',
  // TCL HID-only mode. No adb, no serial, no fastboot: the phone is sitting in
  // neither Android nor a flash mode, and needs a power cycle to move.
  '1bbb:20ff': 'stuck',
};

function readPhoneState() {
  let names = [];
  try {
    names = fs.readdirSync(USB_SYS).sort();
  } catch (e) {
    return { mode: 'unknown', detail: 'cannot read the USB device list' };
  }
  const hits = [];
  for (const name of names) {
    const dir = path.join(USB_SYS, name);
    let isDir = false;
    try { isDir = fs.statSync(dir).isDirectory(); } catch (e) { continue; }
    if (!isDir) continue;
    const read = (file) => {
      try { return fs.readFileSync(path.join(dir, file), 'utf8').trim(); } catch (e) { return ''; }
    };
    const vid = read('idVendor');
    if (!vid) continue;
    const id = vid + ':' + read('idProduct');
    if (!USB_MODES[id]) continue;
    hits.push({ mode: USB_MODES[id], id: id, port: name, serial: read('serial') });
  }
  if (hits.length === 0) return { mode: 'absent', detail: 'no Flip 2 on USB' };
  if (hits.length > 1) {
    return { mode: 'conflict', detail: hits.length + ' phone entries at once', ids: hits.map(h => h.id) };
  }
  const h = hits[0];
  return { mode: h.mode, id: h.id, port: h.port, serial: h.serial || null };
}

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
  '.sh': 'text/plain; charset=utf-8',
  '.rules': 'text/plain; charset=utf-8',
};

protocol.registerSchemesAsPrivileged([
  { scheme: 'flip2', privileges: { standard: true, secure: true, supportFetchAPI: true } },
]);

// flip2://bundle/<path> mirrors wizard/<path>; the window loads
// flip2://bundle/pages/index.html so the pages' ../ fetches land in wizard/.
function serveWizard(request) {
  let rel;
  try {
    rel = decodeURIComponent(new URL(request.url).pathname).replace(/^\/+/, '');
  } catch (e) {
    rel = '';
  }
  if (rel === '') rel = 'pages/index.html';
  if (rel.includes('..')) return Promise.resolve(new Response('bad path', { status: 400 }));
  const file = path.join(WIZARD, rel);
  return fsp.readFile(file).then(function (buf) {
    return new Response(buf, {
      headers: { 'content-type': MIME[path.extname(file)] || 'application/octet-stream' },
    });
  }).catch(function () {
    return new Response('not found: ' + rel, { status: 404 });
  });
}

const PERMISSIONS = ['usb', 'serial', 'usb-private-access'];

function wireSession(ses) {
  ses.setPermissionRequestHandler(function (_wc, permission, cb) {
    cb(PERMISSIONS.indexOf(permission) >= 0);
  });
  ses.setPermissionCheckHandler(function (_wc, permission) {
    return PERMISSIONS.indexOf(permission) >= 0;
  });
  // Hold the chooser until one allowed device is listed. preventDefault
  // means an empty callback cancels; it does not open Electron's picker.
  // USB has no webContents on this event. details.frame is not that object,
  // so the wait stays unscoped in this one-window app. Preloader 0e8d:2000
  // is serial-only. Fastboot 0e8d:201c is USB-only.
  ses.on('select-usb-device', function (event, details, callback) {
    event.preventDefault();
    const list = (details.deviceList || []).slice();
    pick.holdChoice(ses, null, list, 'usb-device-added', 'usb-device-removed',
      pick.soleUsbDeviceId, function (deviceId) {
        pick.deliverUsb(callback, deviceId);
      });
  });
  ses.on('select-serial-port', function (event, portList, webContents, callback) {
    event.preventDefault();
    const list = (portList || []).slice();
    pick.holdChoice(ses, webContents, list, 'serial-port-added', 'serial-port-removed',
      pick.onlyPreloaderPortId, function (portId) {
        pick.deliverSerial(callback, portId);
      });
  });
}

function udevStatus() {
  return fsp.readFile(path.join(WIZARD, RULES_NAME), 'utf8').then(function (src) {
    return fsp.readFile(RULES_DST, 'utf8').then(
      function (cur) { return { installed: cur.trim() === src.trim(), path: RULES_DST }; },
      function () { return { installed: false, path: RULES_DST }; }
    );
  }, function () { return { installed: false, path: RULES_DST }; });
}

// Runs one command as root through the desktop's polkit prompt. pkexec is
// setuid, but this app can be started with NoNewPrivs, which makes setuid
// inert — then pkexec fails without ever drawing a prompt. Handing the command
// to the user's own systemd manager avoids that: the manager spawns without the
// flag, so the password dialog appears normally.
function rootRun(cmd) {
  const env = process.env;
  const pass = ['DISPLAY', 'WAYLAND_DISPLAY', 'XAUTHORITY', 'XDG_RUNTIME_DIR',
    'DBUS_SESSION_BUS_ADDRESS', 'PATH'];
  const args = ['--user', '--collect', '--pipe', '--wait', '--quiet'];
  pass.forEach(function (k) {
    if (env[k]) args.push('--setenv=' + k + '=' + env[k]);
  });
  args.push('--', 'pkexec', 'sh', '-c', cmd);
  return new Promise(function (resolve, reject) {
    execFile('systemd-run', args, { timeout: 180000 }, function (err, out, stderr) {
      if (!err) return resolve(out);
      const msg = err.message + (stderr ? ' — ' + stderr.trim() : '');
      // Only fall back when there is no user manager to hand off to; a
      // dismissed password prompt must not trigger a second attempt.
      if (!/Failed to connect to bus|not been booted with systemd|ENOENT/i.test(msg)) {
        return reject(new Error(msg));
      }
      execFile('pkexec', ['sh', '-c', cmd], { timeout: 180000 }, function (e2, out2, err2) {
        if (e2) reject(new Error(e2.message + (err2 ? ' — ' + err2.trim() : '')));
        else resolve(out2);
      });
    });
  });
}

// One root run: the rules file is staged in /tmp, then copied into place and
// udev is reloaded. The password prompt is the user's own approval.
async function installUdev() {
  let dir = null;
  try {
    const st = await udevStatus();
    if (st.installed) return { ok: true, message: 'Rules are already in place.' };
    dir = await fsp.mkdtemp(path.join(os.tmpdir(), 'flip2-rules-'));
    const staged = path.join(dir, RULES_NAME);
    await fsp.copyFile(path.join(WIZARD, RULES_NAME), staged);
    const cmd =
      'cp ' + JSON.stringify(staged) + ' ' + JSON.stringify(RULES_DST) +
      ' && chmod 644 ' + JSON.stringify(RULES_DST) +
      ' && udevadm control --reload-rules && udevadm trigger';
    await rootRun(cmd);
    if (!(await udevStatus()).installed) {
      throw new Error('pkexec ran but the rules file did not land as expected');
    }
    return { ok: true, message: 'Rules installed. Unplug and replug the phone, then continue.' };
  } catch (e) {
    const dismissed = /dismissed|canceled|cancelled/i.test(e.message || '');
    return { ok: false, message: dismissed ? 'Password prompt dismissed — nothing was installed.' : e.message };
  } finally {
    if (dir) fsp.rm(dir, { recursive: true, force: true }).catch(function () {});
  }
}

// --- catalog files ----------------------------------------------------------
// The Files step used to be a dead end inside the app: the download links were
// handed to the system browser and "Continue" stayed locked until all ten files
// verified. These three handlers give the page a direct path: reuse a copy that
// is already on this PC, or fetch it here (no CORS, no browser detour).

const CATALOG_PATH = path.join(WIZARD, 'catalog.json');

async function readCatalog() {
  const text = await fsp.readFile(CATALOG_PATH, 'utf8');
  return JSON.parse(text).files || [];
}

async function catalogEntry(id) {
  const files = await readCatalog();
  const f = files.find(function (x) { return x.id === id; });
  if (!f) throw new Error('unknown file id ' + id);
  return f;
}

// Every copy of a catalog file the wizard can see, keyed by id. Two folders can
// hold the same file name and only one of them be the right build, so the page
// gets each candidate and hashes them in turn; the first name match is not
// trusted. Size-matching copies come first only to save hashing time.
async function localFiles() {
  const files = await readCatalog();
  const out = {};
  for (const f of files) {
    const seen = new Set();
    const list = [];
    for (const root of localRoots()) {
      let real;
      try { real = fs.realpathSync(path.join(root, f.file)); } catch (e) { continue; }
      if (!insideLocalRoots(real) || seen.has(real)) continue;
      seen.add(real);
      let st;
      try { st = fs.statSync(real); } catch (e) { continue; }
      if (!st.isFile()) continue;
      list.push({ name: real, size: st.size, expected: f.size });
    }
    list.sort(function (a, b) {
      return (b.size === b.expected ? 1 : 0) - (a.size === a.expected ? 1 : 0);
    });
    if (list.length) out[f.id] = list;
  }
  return out;
}

// One candidate's bytes, so the page can SHA-256 it itself before trusting it.
async function readLocal(id, index) {
  const f = await catalogEntry(id);
  const cands = (await localFiles())[id] || [];
  const c = cands[index || 0];
  if (!c) throw new Error(f.file + ' is not in a folder the wizard can read');
  return { id: id, path: c.name, bytes: await fsp.readFile(c.name) };
}

async function downloadFile(id) {
  const f = await catalogEntry(id);
  const dir = downloadDir();
  await fsp.mkdir(dir, { recursive: true });
  const dst = path.join(dir, f.file);
  try {
    const st = await fsp.stat(dst);
    if (st.isFile() && st.size === f.size) {
      return { id: id, bytes: await fsp.readFile(dst), cached: true };
    }
  } catch (e) { /* not cached yet */ }
  const res = await net.fetch(f.url, { redirect: 'follow' });
  if (!res.ok) throw new Error('HTTP ' + res.status + ' from ' + f.upstream);
  const buf = Buffer.from(await res.arrayBuffer());
  if (buf.length !== f.size) {
    throw new Error(f.file + ': got ' + buf.length + ' bytes, expected ' + f.size);
  }
  await fsp.writeFile(dst, buf);
  return { id: id, bytes: buf, cached: false };
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1020,
    height: 800,
    autoHideMenuBar: true,
    title: 'Flip 2 Companion',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  // Upstream links (credits, downloads) open in the system browser; the
  // wizard itself never navigates away from flip2://.
  win.webContents.setWindowOpenHandler(function (details) {
    if (/^https?:/i.test(details.url)) shell.openExternal(details.url);
    return { action: 'deny' };
  });
  win.webContents.on('will-navigate', function (event, url) {
    if (!url.startsWith('flip2://')) event.preventDefault();
  });
  win.loadURL('flip2://bundle/pages/index.html');
  // Self-check for CI/headless runs: print page state as JSON, then exit.
  if (process.argv.includes('--smoke')) {
    win.webContents.once('did-finish-load', function () {
      setTimeout(function () {
        // Everything runs in the renderer — the main process has no DOM and
        // no FLIP2_NATIVE, so the promise chain must finish there.
        win.webContents.executeJavaScript(
          'Promise.resolve(window.FLIP2_NATIVE.udevStatus()).then(function (u) {' +
          'return {' +
          'title: document.title,' +
          'steps: document.querySelectorAll("#steps span[data-step]").length,' +
          'creditRows: document.querySelectorAll("#credit-table tbody tr").length,' +
          'dlRows: document.querySelectorAll("#dl-table tbody tr").length,' +
          'catalog: typeof CATALOG === "object" && CATALOG.list.length,' +
          'fflate: typeof fflate === "object" || typeof fflate === "function",' +
          'native: !!window.FLIP2_NATIVE,' +
          'udevBtnVisible: (function (el) { return !!el && !el.classList.contains("hidden"); })(document.getElementById("udev-native")),' +
          'usbApi: !!navigator.usb,' +
          'serialApi: !!navigator.serial,' +
          'udev: u };})'
        ).then(function (state) {
          console.log('SMOKE ' + JSON.stringify(state));
          app.quit();
        }).catch(function (e) { console.error('SMOKE-ERR ' + (e.message || e)); app.exit(1); });
      }, 500);
    });
  }
}

app.whenReady().then(function () {
  protocol.handle('flip2', serveWizard);
  wireSession(session.defaultSession);
  ipcMain.handle('udev-status', udevStatus);
  ipcMain.handle('install-udev', installUdev);
  ipcMain.handle('phone-state', function () { return readPhoneState(); });
  ipcMain.handle('local-files', function () { return localFiles(); });
  ipcMain.handle('read-local', function (_e, id, index) { return readLocal(id, index); });
  ipcMain.handle('download-file', function (_e, id) { return downloadFile(id); });
  createWindow();
  app.on('activate', function () {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', function () { app.quit(); });
