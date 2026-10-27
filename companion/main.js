// Flip 2 Companion — Electron shell around the wizard pages.
// Serves wizard/ over a custom protocol, auto-picks TCL adb on the WebUSB
// dialog, and installs the udev rules through pkexec so step 3 is one click
// instead of a sudo recipe.

const { app, BrowserWindow, ipcMain, protocol, session, shell } = require('electron');
const { execFile } = require('child_process');
const fsp = require('fs').promises;
const os = require('os');
const path = require('path');

const WIZARD = path.join(__dirname, '..', 'wizard');
const RULES_NAME = '51-android-flip2-adb.rules';
const RULES_DST = path.join('/etc/udev/rules.d', RULES_NAME);

// TCL composite adb (1bbb:0167) and adb-only (1bbb:0c01).
const DEVICES = [
  { vendorId: 0x1bbb, productId: 0x0167 },
  { vendorId: 0x1bbb, productId: 0x0c01 },
];

function isOurs(d) {
  return DEVICES.some(function (m) {
    return d.vendorId === m.vendorId && d.productId === m.productId;
  });
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
  // Auto-pick the phone so nobody fights the chooser; callback() with no
  // device falls back to the normal picker when nothing matches.
  ses.on('select-usb-device', function (event, details, callback) {
    event.preventDefault();
    const ours = (details.deviceList || []).filter(isOurs);
    callback(ours[0] && ours[0].deviceId);
  });
  ses.on('select-serial-port', function (event, portList, _wc, callback) {
    event.preventDefault();
    const ours = portList.filter(isOurs);
    callback(ours.length ? ours[0].portId : '');
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

// One pkexec run: the rules file is staged in /tmp, then root copies it into
// place and reloads udev. The password prompt is the user's own approval.
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
    await new Promise(function (resolve, reject) {
      execFile('pkexec', ['sh', '-c', cmd], { timeout: 180000 }, function (err, _out, stderr) {
        if (err) reject(new Error(err.message + (stderr ? ' — ' + stderr.trim() : '')));
        else resolve();
      });
    });
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
  createWindow();
  app.on('activate', function () {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', function () { app.quit(); });
