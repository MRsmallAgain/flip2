// Flip 2 Companion — Electron shell around the wizard pages.
// Serves wizard/ over a custom protocol, auto-picks TCL adb on the WebUSB
// dialog, and installs the udev rules through pkexec so step 3 is one click
// instead of a sudo recipe.

const { app, BrowserWindow, ipcMain, protocol, session, shell, net } = require('electron');
const { execFile } = require('child_process');
const crypto = require('crypto');
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

// --- return to factory: the jobs that need the host adb server --------------
// The page drives fastboot over WebUSB, but it has no ADB SYNC RECV, so it can
// neither pull a 24 MB boot image off the phone nor read build properties
// without a handshake the host adb server already owns. Both happen here.

function adbRun(args, timeoutMs) {
  return new Promise(function (resolve, reject) {
    execFile('adb', args, { timeout: timeoutMs || 120000, maxBuffer: 4 * 1024 * 1024 },
      function (err, stdout, stderr) {
        if (err) {
          const why = String(stderr || err.message || '').trim();
          return reject(new Error(why || 'adb failed'));
        }
        resolve(String(stdout || ''));
      });
  });
}

// One phone, ready, or this fails. The serial is read, never assumed, so a
// second phone on the bus cannot be backed up or checked by mistake.
async function adbSerial() {
  const out = await adbRun(['devices', '-l']);
  const ready = out.split('\n').map(function (s) { return s.trim(); })
    .filter(function (line) { return /\sdevice(\s|$)/.test(line); });
  if (ready.length !== 1) {
    throw new Error(ready.length
      ? 'more than one phone is connected over adb — unplug the others'
      : 'no phone is ready over adb — plug it in and accept the debugging prompt');
  }
  return ready[0].split(/\s+/)[0];
}

const IDENTITY_PROPS = [
  'ro.product.model', 'ro.product.device', 'ro.build.fingerprint',
  'ro.build.description', 'ro.build.version.release',
  'ro.build.version.security_patch', 'ro.boot.verifiedbootstate',
  'ro.boot.flash.locked', 'ro.boot.serialno',
];

async function phoneIdentity() {
  const serial = await adbSerial();
  const props = {};
  for (const name of IDENTITY_PROPS) {
    props[name] = (await adbRun(['-s', serial, 'shell', 'getprop', name])).trim();
  }
  props.serial = serial;
  return props;
}

const BACKUP_DIR = () => path.join(downloadDir(), 'backups');
const sha256Of = (buf) => crypto.createHash('sha256').update(buf).digest('hex');

// A restored copy brings back a boot image, not root as a separate thing — root
// lives in that image's ramdisk, so whether `su` answered is a property of the
// copy. It is recorded with the copy so the final check can compare like with
// like instead of promising an unrooted phone that a rooted copy cannot deliver.
async function phoneRooted(serial) {
  try {
    return /uid=0/.test(await adbRun(['-s', serial, 'shell', 'su -c id'], 30000));
  } catch (e) {
    return false;
  }
}

// A copy is only reusable later if it remembers what it came from, so every
// dump writes a small sidecar beside it. That is what lets a copy saved in an
// earlier session be restored onto the right phone — including the case that
// matters most, a phone that will not start and so cannot be dumped now.
async function writeSidecar(dest, info) {
  await fsp.writeFile(dest.replace(/\.img$/, '.json'), JSON.stringify(info, null, 2) + '\n')
    .catch(function () { /* the image is the important part */ });
}

// Read the boot partition into sdcard, pull it to this PC, hash it here. Read
// only: no partition is written, and the copy on sdcard is removed afterwards.
async function backupBoot() {
  const serial = await adbSerial();
  const dir = BACKUP_DIR();
  await fsp.mkdir(dir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const dest = path.join(dir, 'boot-' + stamp + '.img');
  const remote = '/sdcard/flip2-boot-backup.img';
  // Reading /dev/block/by-name/boot needs root. Without it adb's own error is
  // cryptic, and the honest answer is that this phone cannot be dumped — the
  // person needs to hear that rather than guess at a permission message.
  try {
    await adbRun(['-s', serial, 'shell',
      'su -c "dd if=/dev/block/by-name/boot of=' + remote + '"'], 180000);
  } catch (e) {
    throw new Error('this phone has no root, so its boot image cannot be copied off it. ' +
      'Use a copy saved on an earlier visit, or root the phone first.');
  }
  await adbRun(['-s', serial, 'pull', remote, dest], 300000);
  await adbRun(['-s', serial, 'shell', 'rm -f ' + remote]).catch(function () {});
  const buf = await fsp.readFile(dest);
  if (!buf.length) {
    throw new Error('the copy that came off the phone is empty, so it is not a way back. ' +
      'Nothing was written to the phone.');
  }
  const prop = (name) => adbRun(['-s', serial, 'shell', 'getprop', name], 30000)
    .then(function (s) { return String(s || '').trim(); })
    .catch(function () { return ''; });
  const info = {
    serial: serial,
    path: dest,
    size: buf.length,
    sha256: sha256Of(buf),
    magic: buf.slice(0, 8).toString('latin1'),
    takenAt: new Date().toISOString(),
    fingerprint: await prop('ro.build.fingerprint'),
    model: await prop('ro.product.model'),
    rooted: await phoneRooted(serial),
  };
  await writeSidecar(dest, info);
  return info;
}

// Copies already on this PC, newest first. Sizes are read from disk; the hash
// comes from the sidecar when it is trustworthy and is recomputed when it is
// not, so a copy with no sidecar is still usable and still named honestly.
async function listBootBackups() {
  let names = [];
  try { names = await fsp.readdir(BACKUP_DIR()); } catch (e) { return []; }
  const out = [];
  for (const name of names) {
    if (!/\.img$/.test(name)) continue;
    const full = path.join(BACKUP_DIR(), name);
    let st;
    try { st = await fsp.stat(full); } catch (e) { continue; }
    if (!st.isFile()) continue;
    let meta = {};
    try { meta = JSON.parse(await fsp.readFile(full.replace(/\.img$/, '.json'), 'utf8')); }
    catch (e) { meta = {}; }
    let sha256 = /^[0-9a-f]{64}$/.test(String(meta.sha256 || '')) ? meta.sha256 : '';
    if (!sha256) {
      try { sha256 = sha256Of(await fsp.readFile(full)); } catch (e) { continue; }
    }
    out.push({
      path: full,
      name: name,
      size: st.size,
      sha256: sha256,
      serial: String(meta.serial || ''),
      fingerprint: String(meta.fingerprint || ''),
      model: String(meta.model || ''),
      takenAt: String(meta.takenAt || st.mtime.toISOString()),
      // Passed straight through, including "no record": the page only compares
      // when this is a real boolean, so a missing value must stay missing rather
      // than becoming false and claiming the copy restores an unrooted phone.
      rooted: typeof meta.rooted === 'boolean' ? meta.rooted : null,
      mtime: st.mtime.toISOString(),
    });
  }
  out.sort(function (a, b) { return a.mtime < b.mtime ? 1 : -1; });
  return out.slice(0, 20);
}

// Hand the page the bytes it is about to write, re-read and re-hashed at that
// moment. Only files inside the wizard's own backup folder are reachable, so a
// path from the page cannot reach out to something else on this computer.
async function readBootBackup(dest) {
  let realDir = null;
  try { realDir = await fsp.realpath(BACKUP_DIR()); } catch (e) { realDir = null; }
  let real;
  try { real = await fsp.realpath(String(dest || '')); }
  catch (e) { throw new Error('that backup file is not on this computer any more'); }
  // No folder means nothing can be inside it, so that is the same refusal as a
  // path outside it. Keeping one message for both is what lets the smoke check
  // exercise the containment rule on a machine that has never saved a copy,
  // instead of passing because a different check happened to fail first.
  if (!realDir || (real !== realDir && !real.startsWith(realDir + path.sep))) {
    throw new Error('that file is not one of the wizard’s own boot copies');
  }
  const buf = await fsp.readFile(real);
  return {
    path: real,
    size: buf.length,
    sha256: sha256Of(buf),
    magic: buf.slice(0, 8).toString('latin1'),
    bytes: buf,
  };
}

// What the phone says about itself now, framed against the build the stock
// image came from. The page decides what to show; this only reports facts.
async function factoryState(expectedFingerprint) {
  const props = await phoneIdentity();
  let rooted = false;
  try {
    rooted = /uid=0/.test(await adbRun(['-s', props.serial, 'shell', 'su -c id'], 30000));
  } catch (e) { rooted = false; }
  let packages = -1;
  try {
    const list = await adbRun(['-s', props.serial, 'shell', 'pm list packages'], 60000);
    packages = list.split('\n').filter(function (l) { return /^package:/.test(l.trim()); }).length;
  } catch (e) { packages = -1; }
  return {
    serial: props.serial,
    model: props['ro.product.model'],
    fingerprint: props['ro.build.fingerprint'],
    description: props['ro.build.description'],
    patch: props['ro.build.version.security_patch'],
    release: props['ro.build.version.release'],
    verifiedBootState: props['ro.boot.verifiedbootstate'],
    flashLocked: props['ro.boot.flash.locked'],
    rooted: rooted,
    packages: packages,
    expected: String(expectedFingerprint || ''),
    buildMatches: !!expectedFingerprint && props['ro.build.fingerprint'] === expectedFingerprint,
  };
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
          // Exercise the two factory IPCs the way the page does, including a
          // path outside the backup folder that must be refused.
          'var facProbe = window.FLIP2_NATIVE.factoryListBackups().then(function (list) {' +
          '  var p = { count: list ? list.length : -1 };' +
          '  if (list && list.length) {' +
          '    var first = list[0];' +
          '    p.firstName = first.name;' +
          '    return window.FLIP2_NATIVE.factoryReadBackup(first.path).then(function (got) {' +
          '      p.readSize = got.size;' +
          '      p.readMagic = got.magic;' +
          '      p.shaMatchesSidecar = got.sha256 === first.sha256;' +
          '      return p;' +
          '    });' +
          '  }' +
          '  return p;' +
          '}).then(function (p) {' +
          // The refusal is the security property, so it is checked whether or
          // not any copy happens to exist on this machine.
          '  return window.FLIP2_NATIVE.factoryReadBackup("/etc/passwd")' +
          '    .then(function () { p.escapeRefused = false; },' +
          '          function (e) { p.escapeRefused = true; p.escapeMsg = String(e.message || e); })' +
          '    .then(function () { return p; });' +
          '});' +
          'Promise.all([window.FLIP2_NATIVE.udevStatus(), facProbe]).then(function (r) {' +
          'var u = r[0], fac = r[1];' +
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
          // The factory slice addresses its stage divs by concatenation, so a
          // missing one only shows up at runtime. Checking every id it touches
          // here is what keeps that from surfacing in front of the user.
          'factoryMissing: (function () {' +
          '  var ids = ["fac-ack-copy","fac-ack-wipe","fac-ack-state","fac-backup",' +
          '    "fac-backup-facts","fac-backup-msg","fac-backup-next","fac-check",' +
          '    "fac-check-msg","fac-copies","fac-copies-msg","fac-copies-wrap","fac-facts",' +
          '    "fac-flash","fac-flash-log","fac-flash-msg","fac-need-copy","fac-pick",' +
          '    "fac-picked","fac-reboot","fac-reboot-msg","fac-refresh",' +
          '    "fac-stage-backup","fac-stage-done","fac-stage-flash","fac-stage-reboot",' +
          '    "fac-stage-verify","fac-stage-wipe","fac-verify","fac-verify-back",' +
          '    "fac-verify-log","fac-verify-msg","fac-verify-next","fac-wipe-next"];' +
          '  return ids.filter(function (id) { return !document.getElementById(id); });' +
          '})(),' +
          'factoryGateLocked: (function () {' +
          '  var b = document.getElementById("factory-open");' +
          '  return !!b && b.disabled;' +
          '})(),' +
          'factory: fac,' +
          'udev: u };})'
        ).then(function (state) {
          console.log('SMOKE ' + JSON.stringify(state));
          app.quit();
        }).catch(function (e) { console.error('SMOKE-ERR ' + (e.message || e)); app.exit(1); });
      }, 500);
    });
  }
  // Read-only page probe: drives stages 1, 2 and 6 of the return-to-factory
  // slice against a phone that is plugged in. It exists because a host-level
  // fastboot drill cannot exercise the parts that live in the page, and those
  // are exactly the parts a person will use.
  if (process.argv.includes('--factory-probe')) {
    win.webContents.once('did-finish-load', function () {
      setTimeout(function () {
        const stamp = new Date().toISOString().replace(/[:.]/g, '-');
        const outDir = path.join(os.homedir(), 'flip2-backups', 'factory-probe-' + stamp);
        require('./factory-probe').runFactoryProbe(win, outDir).then(function (report) {
          report.outDir = outDir;
          console.log('FACTORY-PROBE ' + JSON.stringify(report));
          app.quit();
        }).catch(function (e) {
          console.error('FACTORY-PROBE-ERR ' + (e.stack || e.message || e));
          app.exit(1);
        });
      }, 800);
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
  // Return-to-factory: the host adb server does the work the page cannot.
  ipcMain.handle('factory-identity', function () { return phoneIdentity(); });
  ipcMain.handle('factory-backup-boot', function () { return backupBoot(); });
  ipcMain.handle('factory-state', function (_e, fp) { return factoryState(fp); });
  ipcMain.handle('factory-list-backups', function () { return listBootBackups(); });
  ipcMain.handle('factory-read-backup', function (_e, dest) { return readBootBackup(dest); });
  createWindow();
  app.on('activate', function () {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', function () { app.quit(); });
