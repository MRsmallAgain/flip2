// Flip 2 Companion — Electron shell around the wizard pages.
// Serves wizard/ over a custom protocol, chooses the phone on the WebUSB and
// Web Serial dialogs, and installs the udev rules through pkexec so step 3
// is one click instead of a sudo recipe.

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
  // Recovery enumerates as a Nexus fastboot gadget. fastboot devices stays
  // empty on it, so it is not a flash target.
  '18d1:d001': 'recovery',
  // MTP only. No adb until USB debugging is on.
  '1bbb:0168': 'mtp',
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
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
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
  if (rel.startsWith('bundle/')) rel = rel.slice('bundle/'.length);
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
  if (!f.url) {
    throw new Error(f.file + ': no download URL; match the local pin');
  }
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
    // adb shell copies local stdin to the phone and does not exit until that
    // pipe reaches EOF. execFile leaves stdin open, so a finished command
    // still looks hung. Ignore stdin so the client exits with the command.
    execFile('adb', args, {
      timeout: timeoutMs || 120000,
      maxBuffer: 4 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe'],
    },
      function (err, stdout, stderr) {
        if (err) {
          const why = String(stderr || err.message || '').trim();
          return reject(new Error(why || 'adb failed'));
        }
        resolve(String(stdout || ''));
      });
  });
}

// Like adbRun but always resolves: verify.sh exits 1 when checks fail; stdout
// still holds the PASS/FAIL lines the UI must show.
function adbRunShell(args, timeoutMs) {
  return new Promise(function (resolve, reject) {
    execFile('adb', args, {
      timeout: timeoutMs || 120000,
      maxBuffer: 4 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe'],
    },
      function (err, stdout, stderr) {
        if (err && err.killed) {
          return reject(new Error(String(stderr || err.message || 'adb timed out')));
        }
        const code = err && typeof err.code === 'number' ? err.code : 0;
        resolve({
          stdout: String(stdout || ''),
          stderr: String(stderr || ''),
          code: code,
        });
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

async function wizardHostAdbReady() {
  try {
    const serial = await adbSerial();
    return { ok: true, serial: serial, message: 'Phone ready over host adb (' + serial + ').' };
  } catch (e) {
    return { ok: false, serial: '', message: e.message || String(e) };
  }
}

async function wizardHostShell(payload) {
  const cmd = String(payload && payload.cmd || '');
  if (!cmd) throw new Error('shell: cmd required');
  const serial = await adbSerial();
  const out = await adbRun(['-s', serial, 'shell', cmd], payload.timeoutMs || 30000);
  return { ok: true, stdout: out };
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

// Wizard install/verify over host adb — WebUSB sync: often times out on Linux.
// adbd cannot create files under /data/local/flip2 (SELinux); stage on sdcard, su cp.
const WIZARD_STAGING = '/sdcard/Download/flip2-wizard-staging';
let wizardHostTmp = null;

function shellQuote(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'";
}

async function wizardHostSu(serial, shCmd, timeoutMs) {
  // adb joins shell arguments and the phone's shell parses that line. Quote the
  // script so `&&` and spaces stay inside `sh -c` instead of running as shell.
  await adbRun(['-s', serial, 'shell', 'su', '0', 'sh', '-c', shellQuote(shCmd)], timeoutMs || 120000);
}

function installOutputLooksOk(lines) {
  const text = (lines || []).join('\n');
  if (/^FAIL:/m.test(text)) return false;
  return /DONE: install complete/.test(text);
}

async function wizardHostWriteRootFile(serial, destPath, content, mode) {
  // adbd's shell cannot create files under /data/local/flip2 (SELinux), and a
  // heredoc redirection in `adb shell` is applied by that shell before su runs.
  // Stage on sdcard, then copy into place as root. The script is one quoted
  // argument so the outer shell does not split on &&.
  if (destPath !== PROFILE_PATH) throw new Error('refusing to write that path');
  const modeStr = String(mode || '644');
  if (!/^[0-7]{3,4}$/.test(modeStr)) throw new Error('bad file mode');
  if (!wizardHostTmp) wizardHostTmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'flip2-wiz-'));
  const local = path.join(wizardHostTmp, 'profile.list');
  await fsp.writeFile(local, String(content), 'utf8');
  const remoteStage = WIZARD_STAGING + '/profile.list';
  await wizardHostSu(serial, 'mkdir -p ' + shellQuote(WIZARD_STAGING) + ' /data/local/flip2', 60000);
  await adbRun(['-s', serial, 'push', local, remoteStage], 120000);
  // chmod on /data/local/flip2 is denied even as root. install -m sets the
  // mode while creating the file, which this phone allows.
  await wizardHostSu(serial, 'mkdir -p /data/local/flip2', 60000);
  await wizardHostSu(serial,
    'install -m ' + modeStr + ' ' + shellQuote(remoteStage) + ' ' + shellQuote(destPath),
    180000);
  await adbRun(['-s', serial, 'shell', 'rm', '-f', remoteStage], 60000);
}

// profile.list is one known component id per line. The destination is fixed:
// cleanup deletes incoming/*, and the page must not choose another path.
const PROFILE_PATH = '/data/local/flip2/profile.list';
const PROFILE_IDS = {
  navoverlay: true, keypad: true, flipmouse: true, tagdrawer: true,
  launcher_overlay: true, launcher4: true, ime: true, forkgram: true,
  materialfiles: true, intertune: true, bouncy: true, home_keys: true,
  display: true, wallpaper: true, whisper: true, vosk: true, headwind: true, where: true,
  block_camera: true, enable_camera: true, block_browser: true, enable_browser: true,
};

const CATALOG_APKS = {
  'launcher4.apk': 'com.tim.flip2.launcher4',
  'nullkeyboard.apk': 'com.tim.flip2.nullkeyboard',
  'forkgram.apk': 'org.forkgram.classic',
  'materialfiles.apk': 'me.zhanghai.android.files',
  'intertune.apk': 'dev.skye.intertune',
  'bouncy.apk': 'com.dozingcatsoftware.bouncy',
  'headwind.apk': 'com.hmdm.launcher',
  'where.apk': 'net.af0.where',
};

const CATALOG_PACKAGES = {
  'com.tim.flip2.launcher4': true,
  'com.tim.flip2.nullkeyboard': true,
  'org.forkgram.classic': true,
  'me.zhanghai.android.files': true,
  'dev.skye.intertune': true,
  'com.dozingcatsoftware.bouncy': true,
  'com.hmdm.launcher': true,
  'net.af0.where': true,
};

const CATALOG_MODULES = {
  flip2_nav_overlay: true,
  flip2_keypad_backspace: true,
  FlipMouse: true,
  flip2_pixel_tag_drawer: true,
  flip2_launcher_overlay: true,
};

const DEVICE_OWNER_COMPONENT = 'com.hmdm.launcher/.AdminReceiver';

function normalizeProfileText(text) {
  const raw = String(text == null ? '' : text).replace(/\r/g, '');
  if (raw.length > 2048) throw new Error('profile.list rejected');
  if (!raw.endsWith('\n')) throw new Error('profile.list must end with a newline');
  if (raw.indexOf('..') !== -1 || raw.indexOf('/') !== -1 || raw.indexOf('\\') !== -1) {
    throw new Error('profile.list rejected');
  }
  const lines = raw.split('\n');
  lines.pop();
  if (!lines.length) throw new Error('profile.list is empty');
  const seen = Object.create(null);
  for (let i = 0; i < lines.length; i++) {
    const id = lines[i];
    if (!PROFILE_IDS[id] || seen[id]) throw new Error('profile.list rejected');
    seen[id] = true;
  }
  return lines.join('\n') + '\n';
}

async function wizardHostWriteProfile(payload) {
  const text = normalizeProfileText(payload && payload.text);
  const serial = await adbSerial();
  await wizardHostWriteRootFile(serial, PROFILE_PATH, text, '644');
  return { ok: true };
}

async function wizardHostInstallApk(payload) {
  const name = String(payload && payload.name || '');
  const pkg = CATALOG_APKS[name];
  if (!pkg) throw new Error('not a catalog apk');
  const serial = await adbSerial();
  const src = '/data/local/flip2/incoming/' + name;
  let out = '';
  try {
    out = await adbRun(
      ['-s', serial, 'shell', 'su', '0', 'sh', '-c', shellQuote('pm install -r ' + shellQuote(src))],
      180000);
  } catch (e) {
    return { ok: false, error: (e && e.message) || String(e), packageName: pkg };
  }
  if (/Failure|INSTALL_FAILED/.test(out)) {
    return { ok: false, error: out.trim() || 'install failed', packageName: pkg };
  }
  if (/Success/.test(out)) return { ok: true, packageName: pkg };
  return { ok: false, error: out.trim() || 'install failed', packageName: pkg };
}

async function wizardHostUninstallPackage(payload) {
  const pkg = String(payload && payload.packageName || '');
  if (!CATALOG_PACKAGES[pkg]) throw new Error('not a catalog package');
  const serial = await adbSerial();
  let out = '';
  try {
    out = await adbRun(['-s', serial, 'shell', 'pm', 'uninstall', pkg], 120000);
  } catch (e) {
    const msg = (e && e.message) || String(e);
    if (msg.indexOf('DELETE_FAILED_DEVICE_POLICY_MANAGER') !== -1) {
      return { ok: false, error: 'DELETE_FAILED_DEVICE_POLICY_MANAGER' };
    }
    return { ok: false, error: msg };
  }
  if (out.indexOf('DELETE_FAILED_DEVICE_POLICY_MANAGER') !== -1) {
    return { ok: false, error: 'DELETE_FAILED_DEVICE_POLICY_MANAGER' };
  }
  if (/Success/.test(out)) return { ok: true, packageName: pkg };
  return { ok: false, error: out.trim() || 'uninstall failed' };
}

async function wizardHostRemoveModule(payload) {
  const id = String(payload && payload.moduleId || '');
  if (!CATALOG_MODULES[id] || id.indexOf('/') !== -1 || id.indexOf('..') !== -1) {
    throw new Error('not a catalog module');
  }
  const serial = await adbSerial();
  await wizardHostSu(serial, 'rm -rf ' + shellQuote('/data/adb/modules/' + id), 60000);
  return {
    ok: true,
    moduleId: id,
    reboot: true,
    message: 'Module removed. Reboot the phone before expecting it to stay gone.',
  };
}

function deviceOwnerBlock(text) {
  const t = String(text || '').replace(/\r/g, '');
  const re = /(^|\n)\s*Device Owner:\s*([^\n]*)/g;
  let m;
  let found = false;
  while ((m = re.exec(t))) {
    found = true;
    const rest = m[2].trim();
    if (rest && !/^null$/i.test(rest) && !/^none$/i.test(rest)) {
      return { known: true, present: true, detail: rest };
    }
    const lines = t.slice(m.index + m[0].length).split('\n');
    const detail = [];
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (!line.trim()) break;
      if (i > 0 && !/^\s/.test(line)) break;
      detail.push(line.trim());
    }
    if (/admin\s*=|package\s*=/.test(detail.join('\n'))) {
      return { known: true, present: true, detail: detail.join('\n') };
    }
  }
  if (found) return { known: true, present: false, detail: 'null' };
  // Some ROMs (e.g. TCL 4058G) omit "Device Owner:" entirely when none is set.
  if (/Current Device Policy Manager state|Enabled Device Admins/i.test(t)) {
    return { known: true, present: false, detail: 'none (not reported in dumpsys)' };
  }
  return { known: false, present: false, detail: '' };
}

async function wizardHostSetDeviceOwner(payload) {
  if (!payload || payload.confirm !== 'manage') {
    return { ok: false, code: 'confirm', error: 'Type manage to set the device owner.' };
  }
  const serial = await adbSerial();
  let pkgPath = '';
  try {
    pkgPath = await adbRun(['-s', serial, 'shell', 'pm', 'path', 'com.hmdm.launcher'], 30000);
  } catch (e) {
    return {
      ok: false,
      code: 'not-installed',
      error: 'com.hmdm.launcher is not installed. Apply the managed profile first.',
    };
  }
  if (!/^package:/m.test(String(pkgPath).replace(/\r/g, ''))) {
    return {
      ok: false,
      code: 'not-installed',
      error: 'com.hmdm.launcher is not installed. Apply the managed profile first.',
    };
  }
  let policy = '';
  try {
    policy = await adbRun(['-s', serial, 'shell', 'dumpsys', 'device_policy'], 60000);
  } catch (e) {
    return { ok: false, code: 'policy', error: (e && e.message) || String(e) };
  }
  const owner = deviceOwnerBlock(policy);
  if (!owner.known) {
    return { ok: false, code: 'policy', error: 'Could not read the device owner from dumpsys device_policy.' };
  }
  if (owner.present) {
    return {
      ok: false,
      code: 'owner',
      error: 'A device owner is already set. This app will not replace it and will not edit device_policies.xml.',
    };
  }
  let accounts = '';
  try {
    accounts = await adbRun(['-s', serial, 'shell', 'dumpsys', 'account'], 60000);
  } catch (e) {
    return { ok: false, code: 'accounts', error: (e && e.message) || String(e) };
  }
  if (/Account\s*\{/.test(String(accounts).replace(/\r/g, ''))) {
    return {
      ok: false,
      code: 'accounts',
      error: 'This user has accounts. Factory reset stays on the phone. Back up to ~/flip2-pre-wipe-backup, then reset on the phone before typing manage. This app never wipes userdata over USB.',
    };
  }
  let out = '';
  try {
    out = await adbRun(
      ['-s', serial, 'shell', 'dpm', 'set-device-owner', DEVICE_OWNER_COMPONENT],
      60000);
  } catch (e) {
    const msg = (e && e.message) || String(e);
    if (/account/i.test(msg)) {
      return {
        ok: false,
        code: 'accounts',
        error: 'Device owner was refused because accounts exist. Factory reset stays on the phone. Back up to ~/flip2-pre-wipe-backup and reset on the phone. This app never wipes userdata over USB.',
      };
    }
    return { ok: false, code: 'dpm', error: msg };
  }
  if (/error|exception|fail|not allowed/i.test(out)) {
    return { ok: false, code: 'dpm', error: out.trim() };
  }
  return { ok: true, component: DEVICE_OWNER_COMPONENT, stdout: out.trim() };
}

// Same six modules as pipeline/deploy/installer/deroot.sh. Touch `remove` only.
// Do not rm -rf, do not run that script (it also resets the IME and home keys),
// and do not uninstall APKs. USB debugging is turned off after the marks.
const DROP_ROOT_MODULES = [
  'flip2_nav_overlay',
  'flip2_keypad_backspace',
  'FlipMouse',
  'flip2_pixel_tag_drawer',
  'flip2_launcher_overlay',
  'flip2_launcher3_null_icon_fix',
];

function adbLinkDropped(err) {
  const msg = String((err && err.message) || err || '');
  return /error:\s*closed|device offline|no devices\/emulators|device '[^']*' not found|device not found/i.test(msg);
}

async function putGlobalSetting(serial, key, value) {
  const cmd = 'settings put global ' + key + ' ' + value;
  try {
    await adbRun(['-s', serial, 'shell', 'settings', 'put', 'global', key, value], 30000);
  } catch (e) {
    await wizardHostSu(serial, cmd, 30000);
  }
}

async function wizardHostDropRootAdb(payload) {
  if (!payload || payload.confirm !== 'unroot') {
    return { ok: false, code: 'confirm', error: 'Type unroot to remove root and turn off USB debugging.' };
  }
  const serial = await adbSerial();
  if (!(await phoneRooted(serial))) {
    return {
      ok: false,
      code: 'no-root',
      error: 'su did not return uid 0. Modules were not marked and USB debugging was left on.',
    };
  }
  const lines = ['set -eu', 'fail=0'];
  DROP_ROOT_MODULES.forEach(function (id) {
    const dir = '/data/adb/modules/' + id;
    lines.push(
      'if [ -d ' + shellQuote(dir) + ' ]; then ' +
      'if touch ' + shellQuote(dir + '/remove') + '; then echo marked ' + id + '; ' +
      'else echo failed ' + id + '; fail=1; fi; ' +
      'else echo absent ' + id + '; fi');
  });
  lines.push('pkill -f ' + shellQuote('FlipMouse/service.sh') + ' >/dev/null 2>&1 || true');
  lines.push('pkill -f ' + shellQuote('FlipMouse/mouse') + ' >/dev/null 2>&1 || true');
  lines.push('test "$fail" = 0');
  let markOut = '';
  try {
    markOut = await adbRun(
      ['-s', serial, 'shell', 'su', '0', 'sh', '-c', shellQuote(lines.join('; '))],
      60000);
  } catch (e) {
    return {
      ok: false,
      code: 'modules',
      modulesMarked: false,
      adbDisabled: false,
      error: 'Module removal did not finish, so USB debugging was left on. ' + ((e && e.message) || e),
    };
  }
  try {
    await putGlobalSetting(serial, 'development_settings_enabled', '0');
  } catch (e) {
    return {
      ok: false,
      code: 'adb',
      modulesMarked: true,
      adbDisabled: false,
      stdout: String(markOut || '').trim(),
      error: 'Modules were marked for removal, but USB debugging was left on. ' + ((e && e.message) || e),
    };
  }
  try {
    await adbRun(['-s', serial, 'shell', 'settings', 'put', 'global', 'adb_enabled', '0'], 30000);
  } catch (e) {
    if (!adbLinkDropped(e)) {
      try {
        await wizardHostSu(serial, 'settings put global adb_enabled 0', 30000);
      } catch (e2) {
        if (!adbLinkDropped(e2)) {
          return {
            ok: false,
            code: 'adb',
            modulesMarked: true,
            adbDisabled: false,
            stdout: String(markOut || '').trim(),
            error: 'Modules were marked for removal, but USB debugging was left on. ' + ((e2 && e2.message) || e2),
          };
        }
      }
    }
  }
  return {
    ok: true,
    modulesMarked: true,
    adbDisabled: true,
    stdout: String(markOut || '').trim(),
    message: 'Flip2 modules were marked for removal and USB debugging was turned off. On the phone: Magisk, Uninstall, Restore Images, then reboot. This did not restore the boot image, did not uninstall apps, and did not wipe the phone. Companion can no longer talk to the phone.',
  };
}

async function wizardHostPrepare() {
  await adbSerial();
  wizardHostTmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'flip2-wiz-'));
  const serial = await adbSerial();
  await wizardHostSu(serial,
    'rm -rf ' + shellQuote(WIZARD_STAGING) +
      ' && mkdir -p /data/local/flip2/incoming ' + shellQuote(WIZARD_STAGING),
    60000);
  return { ok: true };
}

async function wizardHostPushOne(payload) {
  const name = String(payload.name || '');
  let buf;
  if (payload.dataBase64) {
    buf = Buffer.from(String(payload.dataBase64), 'base64');
  } else if (payload.data != null) {
    buf = Buffer.isBuffer(payload.data) ? payload.data : Buffer.from(payload.data);
  } else {
    throw new Error('push: name and dataBase64 (or data) required');
  }
  if (!name) throw new Error('push: name required');
  if (!wizardHostTmp) await wizardHostPrepare();
  const serial = await adbSerial();
  const local = path.join(wizardHostTmp, name);
  await fsp.writeFile(local, buf);
  const remoteStage = WIZARD_STAGING + '/' + name;
  const dest = '/data/local/flip2/incoming/' + name;
  await adbRun(['-s', serial, 'push', local, remoteStage], 900000);
  await wizardHostSu(serial,
    'cp ' + shellQuote(remoteStage) + ' ' + shellQuote(dest) + ' && rm -f ' + shellQuote(remoteStage),
    900000);
  return { ok: true, name: name, size: buf.length };
}

async function wizardHostRunInstall(payload) {
  const lines = [];
  const log = (s) => { lines.push(String(s)); };
  try {
    const serial = await adbSerial();
    const installSh = String(payload.installSh || '');
    if (!installSh) throw new Error('install.sh text missing');
    if (!wizardHostTmp) wizardHostTmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'flip2-wiz-'));
    const shLocal = path.join(wizardHostTmp, 'install.sh');
    await fsp.writeFile(shLocal, installSh, 'utf8');
    log('push install.sh');
    const shStage = WIZARD_STAGING + '/install.sh';
    await adbRun(['-s', serial, 'push', shLocal, shStage], 120000);
    try {
      await wizardHostSu(serial,
        'install -m 755 ' + shellQuote(shStage) + ' /data/local/flip2/install.sh && rm -f ' + shellQuote(shStage),
        120000);
    } catch (deployErr) {
      log('note: install -m755 deploy failed (' + (deployErr.message || deployErr) + '); trying su cp…');
      await wizardHostSu(serial,
        'cp ' + shellQuote(shStage) + ' /data/local/flip2/install.sh && chmod 755 /data/local/flip2/install.sh && rm -f ' + shellQuote(shStage),
        120000);
    }
    log('running install.sh as root…');
    const out = await adbRun(['-s', serial, 'shell', 'su', '0', 'sh', '-c', shellQuote('sh /data/local/flip2/install.sh')], 1800000);
    out.split('\n').forEach(function (line) {
      if (line.length) log(line);
    });
    const fail = lines.find(function (l) { return /^FAIL:/.test(l); });
    if (fail) return { ok: false, error: fail, lines: lines };
    if (installOutputLooksOk(lines)) return { ok: true, lines: lines };
    return { ok: false, error: 'install.sh did not report DONE', lines: lines };
  } catch (e) {
    if (installOutputLooksOk(lines)) {
      log('note: post-install step failed (' + (e.message || e) + ') but install output looks complete');
      return { ok: true, lines: lines, warnings: [e.message || String(e)] };
    }
    return { ok: false, error: e.message || String(e), lines: lines };
  } finally {
    if (wizardHostTmp) {
      await fsp.rm(wizardHostTmp, { recursive: true, force: true }).catch(function () {});
      wizardHostTmp = null;
    }
  }
}

async function wizardHostCleanup() {
  const lines = [];
  try {
    const serial = await adbSerial();
    await wizardHostSu(serial, 'rm -rf /data/local/flip2/incoming && mkdir -p /data/local/flip2/incoming', 120000);
    lines.push('OK: cleaned incoming/');
    return { ok: true, lines: lines };
  } catch (e) {
    lines.push('note: cleanup skipped (' + (e.message || e) + ')');
    return { ok: true, lines: lines, warning: e.message || String(e) };
  }
}

async function wizardHostVerify(payload) {
  const lines = [];
  const log = (s) => { lines.push(String(s)); };
  try {
    const serial = await adbSerial();
    const verifySh = String(payload.verifySh || '');
    if (!verifySh) throw new Error('verify.sh text missing');
    const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'flip2-wiz-'));
    try {
      const vLocal = path.join(tmp, 'verify.sh');
      await fsp.writeFile(vLocal, verifySh, 'utf8');
      const vStage = WIZARD_STAGING + '/verify.sh';
      await adbRun(['-s', serial, 'push', vLocal, vStage], 120000);
      await wizardHostSu(serial,
        'install -m 755 ' + shellQuote(vStage) + ' /data/local/flip2/verify.sh && rm -f ' + shellQuote(vStage),
        120000);
      const run = await adbRunShell(
        ['-s', serial, 'shell', 'su', '0', 'sh', '-c', shellQuote('sh /data/local/flip2/verify.sh')],
        600000);
      if (run.code !== 0 && !run.stdout.trim() && run.stderr.trim()) {
        throw new Error(run.stderr.trim());
      }
      run.stdout.split('\n').forEach(function (line) {
        if (line.length) log(line);
      });
      const fail = lines.find(function (l) { return /^FAIL:/.test(l); });
      if (fail) return { ok: false, error: fail, lines: lines };
      if (run.code !== 0 && !fail) {
        const summary = lines.filter(function (l) { return /^SUMMARY:/.test(l); }).pop();
        return { ok: false, error: summary || 'verify.sh exited with errors', lines: lines };
      }
      return { ok: true, lines: lines };
    } finally {
      await fsp.rm(tmp, { recursive: true, force: true }).catch(function () {});
    }
  } catch (e) {
    return { ok: false, error: e.message || String(e), lines: lines };
  }
}

// Personal backups: catalog APKs, contacts, and text messages.
// Stored in ~/flip2-personal-backup, outside the boot-backup folder, so
// factoryReadBackup cannot read them. Contacts are version-checked and
// byte-copied. Messages are rebuilt with personal_db.py. snapshot() runs
// only on a disposable temp copy, never on ~/flip2-pre-wipe-backup.
// Counts only cross IPC. This does not wipe userdata, set device owner, or drop root.
function personalRoot() {
  return path.join(os.homedir(), 'flip2-personal-backup');
}

const PERSONAL_DB = {
  contacts: {
    file: 'contacts2.db',
    path: '/data/data/com.android.providers.contacts/databases/contacts2.db',
    owner: 'u0_a17:u0_a17',
    stops: [
      'am force-stop com.android.contacts || true',
      'am force-stop com.android.providers.contacts || true',
      'pids=$(pidof com.android.providers.contacts || true); if [ -n "$pids" ]; then kill $pids || true; fi',
    ],
  },
  messages: {
    file: 'mmssms.db',
    path: '/data/data/com.android.providers.telephony/databases/mmssms.db',
    owner: 'radio:radio',
    stops: [
      'am force-stop com.android.mms || true',
      'am force-stop com.android.messaging || true',
      'am force-stop com.android.providers.telephony || true',
      'pids=$(pidof com.android.providers.telephony || true); if [ -n "$pids" ]; then kill $pids || true; fi',
    ],
  },
};

function integerFields(parsed, kind) {
  const out = { kind: kind };
  if (!parsed || typeof parsed !== 'object') return out;
  Object.keys(parsed).forEach(function (key) {
    if (key === 'kind') return;
    const value = parsed[key];
    if (typeof value === 'number' && Number.isInteger(value)) out[key] = value;
  });
  return out;
}

function takeCounts(parsed, kind) {
  if (!parsed || parsed.kind !== kind) throw new Error('personal backup helper failed');
  return integerFields(parsed, kind);
}

function publicError(err) {
  const msg = err && err.message ? String(err.message) : 'personal backup failed';
  const code = msg.match(/INSTALL_FAILED_[A-Z0-9_]+/);
  if (code) return code[0];
  const known = [
    'contacts backup is not version 1401',
    'messages backup is not version 670020',
    'message backup still has attachments',
    'contacts backup is missing name counts',
    'personal backup helper failed',
    'python3 is not installed',
    'no saved backup yet',
    'pre-wipe backup is not on this PC',
    'unknown backup source',
    'could not copy the database off the phone',
    'could not copy catalog apps',
    'no catalog app copies saved',
    'not a catalog package',
    'unknown personal database',
    'unknown backup',
  ];
  for (let i = 0; i < known.length; i++) {
    if (msg.indexOf(known[i]) !== -1) return known[i];
  }
  if (/more than one phone/i.test(msg)) return 'more than one phone is connected over adb, unplug the others';
  if (/no phone is ready/i.test(msg) || /unauthor/i.test(msg)) return 'Accept the USB debugging prompt on the phone.';
  if (/permission denied/i.test(msg)) return 'permission denied while copying the backup';
  if (/device offline/i.test(msg)) return 'the phone is offline over adb';
  if (msg.length > 180 || (msg.match(/\d/g) || []).length >= 7) return 'personal backup failed';
  return msg;
}

function personalGuard(fn) {
  return function (payload) {
    return Promise.resolve().then(function () {
      return fn(payload);
    }).then(function (result) {
      return result;
    }, function (err) {
      return { ok: false, error: publicError(err) };
    });
  };
}

function runPersonalDb(args) {
  return new Promise(function (resolve, reject) {
    execFile('python3', [path.join(__dirname, 'personal_db.py')].concat(args), {
      timeout: 180000,
      maxBuffer: 1024 * 1024,
    }, function (err, stdout) {
      if (err && err.code === 'ENOENT') {
        reject(new Error('python3 is not installed'));
        return;
      }
      let parsed = null;
      try { parsed = JSON.parse(String(stdout || '').trim()); } catch (e) { parsed = null; }
      if (err || !parsed || typeof parsed.kind !== 'string') {
        reject(new Error('personal backup helper failed'));
        return;
      }
      resolve(parsed);
    });
  });
}

async function ensurePersonalDirs() {
  const root = personalRoot();
  await fsp.mkdir(path.join(root, 'apps'), { recursive: true });
  return root;
}

async function mergeManifest(patch) {
  const root = await ensurePersonalDirs();
  const file = path.join(root, 'manifest.json');
  let cur = {};
  try { cur = JSON.parse(await fsp.readFile(file, 'utf8')); } catch (e) { cur = {}; }
  if (!cur || typeof cur !== 'object' || Array.isArray(cur)) cur = {};
  if (patch.contacts) cur.contacts = patch.contacts;
  if (patch.messages) cur.messages = patch.messages;
  const tmp = file + '.tmp';
  await fsp.writeFile(tmp, JSON.stringify(cur));
  await fsp.rename(tmp, file);
}

function assertContacts(counts) {
  if (!counts || counts.userVersion !== 1401) throw new Error('contacts backup is not version 1401');
  if (typeof counts.data !== 'number' || typeof counts.named !== 'number' || typeof counts.blankNames !== 'number') {
    throw new Error('contacts backup is missing name counts');
  }
}

function assertMessages(counts) {
  if (!counts || counts.userVersion !== 670020) throw new Error('messages backup is not version 670020');
  if (counts.pdu !== 0 || counts.part !== 0) throw new Error('message backup still has attachments');
}

function catalogApkPath(text) {
  const lines = String(text || '').split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.indexOf('package:') !== 0) continue;
    const remote = line.slice('package:'.length).trim();
    if (!/^\/(data|mnt|system|product|vendor)\/[A-Za-z0-9._~+/=-]+$/.test(remote)) return '';
    if (remote.indexOf('..') !== -1 || !/\.apk$/.test(remote)) return '';
    return remote;
  }
  return '';
}

async function stagePull(serial, remotePath, localPath) {
  const base = 'personal-' + path.basename(remotePath);
  if (!/^personal-[A-Za-z0-9._-]+$/.test(base)) throw new Error('unknown backup');
  const stage = WIZARD_STAGING + '/' + base;
  const stageWal = stage + '-wal';
  const stageShm = stage + '-shm';
  const flag = stage + '.flag';
  const script = [
    'mkdir -p ' + shellQuote(WIZARD_STAGING),
    'cp ' + shellQuote(remotePath) + ' ' + shellQuote(stage),
    'chmod 644 ' + shellQuote(stage),
    'rm -f ' + shellQuote(stageWal) + ' ' + shellQuote(stageShm),
    'if [ -f ' + shellQuote(remotePath + '-wal') + ' ]; then cp ' + shellQuote(remotePath + '-wal') + ' ' + shellQuote(stageWal) + ' && chmod 644 ' + shellQuote(stageWal) + '; fi',
    'if [ -f ' + shellQuote(remotePath + '-shm') + ' ]; then cp ' + shellQuote(remotePath + '-shm') + ' ' + shellQuote(stageShm) + ' && chmod 644 ' + shellQuote(stageShm) + '; fi',
    'if [ -f ' + shellQuote(stageWal) + ' ]; then echo WAL_YES > ' + shellQuote(flag) + ' && chmod 644 ' + shellQuote(flag) + '; else echo WAL_NO > ' + shellQuote(flag) + ' && chmod 644 ' + shellQuote(flag) + '; fi',
  ].join(' && ');
  await wizardHostSu(serial, script, 120000);
  const flagLocal = localPath + '.flag';
  try {
    await adbRun(['-s', serial, 'pull', stage, localPath], 180000);
    await adbRun(['-s', serial, 'pull', flag, flagLocal], 30000);
    const marker = String(await fsp.readFile(flagLocal, 'utf8')).trim();
    if (marker === 'WAL_YES') {
      await adbRun(['-s', serial, 'pull', stageWal, localPath + '-wal'], 180000);
      await adbRun(['-s', serial, 'pull', stageShm, localPath + '-shm'], 60000).catch(function () {});
    } else if (marker !== 'WAL_NO') {
      throw new Error('could not copy the database off the phone');
    }
  } finally {
    await adbRun(['-s', serial, 'shell', 'rm', '-f', stage, stageWal, stageShm, flag], 30000).catch(function () {});
  }
}

async function flattenDisposable(src, dest) {
  await fsp.rm(dest, { force: true });
  try {
    await fsp.access(src + '-wal');
  } catch (e) {
    await fsp.copyFile(src, dest);
    return;
  }
  await runPersonalDb(['snapshot', src, dest]);
}

async function savedDatabase(fileName) {
  if (fileName !== 'contacts2.db' && fileName !== 'mmssms.db') throw new Error('unknown backup');
  const root = personalRoot();
  const file = path.join(root, fileName);
  if (!fs.existsSync(file)) throw new Error('no saved backup yet');
  const realRoot = await fsp.realpath(root);
  const real = await fsp.realpath(file);
  if (real.indexOf(realRoot + path.sep) !== 0) throw new Error('unknown backup');
  return real;
}

function prewipeDatabase(fileName) {
  if (fileName !== 'contacts2.db' && fileName !== 'mmssms.db') throw new Error('unknown backup');
  const file = path.join(os.homedir(), 'flip2-pre-wipe-backup', 'readable', fileName);
  if (!fs.existsSync(file)) throw new Error('pre-wipe backup is not on this PC');
  return file;
}

async function databaseSource(payload, fileName) {
  const which = String(payload && payload.source || 'saved');
  if (which === 'saved') return savedDatabase(fileName);
  if (which === 'prewipe') return prewipeDatabase(fileName);
  throw new Error('unknown backup source');
}

async function installPersonalDb(serial, localPath, kind) {
  const spec = PERSONAL_DB[kind];
  if (!spec) throw new Error('unknown personal database');
  const stage = WIZARD_STAGING + '/' + spec.file;
  await wizardHostSu(serial, 'mkdir -p ' + shellQuote(WIZARD_STAGING), 60000);
  await adbRun(['-s', serial, 'push', localPath, stage], 180000);
  const script = ['set -e'].concat(spec.stops).concat([
    'sleep 1',
    'install -m 660 ' + shellQuote(stage) + ' ' + shellQuote(spec.path),
    'chown ' + spec.owner + ' ' + shellQuote(spec.path),
    'restorecon ' + shellQuote(spec.path) + ' || true',
    'rm -f ' + shellQuote(spec.path + '-journal') + ' ' + shellQuote(spec.path + '-wal') + ' ' + shellQuote(spec.path + '-shm'),
    'rm -f ' + shellQuote(stage),
  ]).join('\n');
  try {
    await wizardHostSu(serial, script, 180000);
  } catch (e) {
    await adbRun(['-s', serial, 'shell', 'rm', '-f', stage], 30000).catch(function () {});
    throw e;
  }
}

async function personalBackupInfo() {
  const root = personalRoot();
  const contactsPath = path.join(root, 'contacts2.db');
  const messagesPath = path.join(root, 'mmssms.db');
  let contacts = null;
  if (fs.existsSync(contactsPath)) {
    try {
      contacts = takeCounts(await runPersonalDb(['check-contacts', contactsPath]), 'contacts');
    } catch (e) {
      contacts = null;
    }
  }
  let manifest = {};
  try { manifest = JSON.parse(await fsp.readFile(path.join(root, 'manifest.json'), 'utf8')); } catch (e) { manifest = {}; }
  let messages = null;
  if (fs.existsSync(messagesPath) && manifest && manifest.messages && manifest.messages.userVersion === 670020) {
    messages = integerFields(manifest.messages, 'messages');
  }
  let apps = 0;
  Object.keys(CATALOG_PACKAGES).forEach(function (pkg) {
    if (fs.existsSync(path.join(root, 'apps', pkg + '.apk'))) apps += 1;
  });
  const prewipeDir = path.join(os.homedir(), 'flip2-pre-wipe-backup', 'readable');
  const prewipe = fs.existsSync(path.join(prewipeDir, 'contacts2.db')) && fs.existsSync(path.join(prewipeDir, 'mmssms.db'));
  return { ok: true, contacts: contacts, messages: messages, apps: apps, prewipe: prewipe };
}

async function personalBackupContacts() {
  const serial = await adbSerial();
  const root = await ensurePersonalDirs();
  const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'flip2-personal-'));
  try {
    const pulled = path.join(tmp, 'contacts2.db');
    await stagePull(serial, PERSONAL_DB.contacts.path, pulled);
    const flat = path.join(tmp, 'flat.db');
    await flattenDisposable(pulled, flat);
    const counts = takeCounts(await runPersonalDb(['check-contacts', flat]), 'contacts');
    assertContacts(counts);
    await fsp.copyFile(flat, path.join(root, 'contacts2.db'));
    await mergeManifest({ contacts: counts });
    return { ok: true, contacts: counts };
  } finally {
    await fsp.rm(tmp, { recursive: true, force: true });
  }
}

async function personalRestoreContacts(payload) {
  const source = await databaseSource(payload, 'contacts2.db');
  const counts = takeCounts(await runPersonalDb(['check-contacts', source]), 'contacts');
  assertContacts(counts);
  const serial = await adbSerial();
  const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'flip2-personal-'));
  try {
    const copy = path.join(tmp, 'contacts2.db');
    await fsp.copyFile(source, copy);
    await installPersonalDb(serial, copy, 'contacts');
  } finally {
    await fsp.rm(tmp, { recursive: true, force: true });
  }
  return { ok: true, contacts: counts };
}

async function personalBackupMessages() {
  const serial = await adbSerial();
  const root = await ensurePersonalDirs();
  const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'flip2-personal-'));
  try {
    const pulled = path.join(tmp, 'mmssms.db');
    await stagePull(serial, PERSONAL_DB.messages.path, pulled);
    const flat = path.join(tmp, 'flat.db');
    await flattenDisposable(pulled, flat);
    const built = path.join(tmp, 'built.db');
    const counts = takeCounts(await runPersonalDb(['build-messages', flat, built]), 'messages');
    assertMessages(counts);
    await fsp.copyFile(built, path.join(root, 'mmssms.db'));
    await mergeManifest({ messages: counts });
    return { ok: true, messages: counts };
  } finally {
    await fsp.rm(tmp, { recursive: true, force: true });
  }
}

async function personalRestoreMessages(payload) {
  const source = await databaseSource(payload, 'mmssms.db');
  const serial = await adbSerial();
  const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'flip2-personal-'));
  try {
    const src = path.join(tmp, 'src.db');
    const built = path.join(tmp, 'built.db');
    await fsp.copyFile(source, src);
    const counts = takeCounts(await runPersonalDb(['build-messages', src, built]), 'messages');
    assertMessages(counts);
    await installPersonalDb(serial, built, 'messages');
    return { ok: true, messages: counts };
  } finally {
    await fsp.rm(tmp, { recursive: true, force: true });
  }
}

async function personalBackupApps() {
  const serial = await adbSerial();
  const root = await ensurePersonalDirs();
  const names = Object.keys(CATALOG_PACKAGES);
  let found = 0;
  const saved = [];
  for (let i = 0; i < names.length; i++) {
    const pkg = names[i];
    const stage = WIZARD_STAGING + '/catalog-backup.apk';
    try {
      const listed = await adbRun(['-s', serial, 'shell', 'pm', 'path', pkg], 60000);
      const remote = catalogApkPath(listed);
      if (!remote) continue;
      found += 1;
      await wizardHostSu(serial,
        'mkdir -p ' + shellQuote(WIZARD_STAGING) +
        ' && cp ' + shellQuote(remote) + ' ' + shellQuote(stage) +
        ' && chmod 644 ' + shellQuote(stage),
        120000);
      const local = path.join(root, 'apps', pkg + '.apk');
      await adbRun(['-s', serial, 'pull', stage, local], 180000);
      const st = await fsp.stat(local);
      if (!st.size) {
        await fsp.rm(local, { force: true });
        continue;
      }
      saved.push(pkg);
    } catch (e) {
      // One missing package should not drop the rest of the catalog.
    } finally {
      await adbRun(['-s', serial, 'shell', 'rm', '-f', stage], 30000).catch(function () {});
    }
  }
  if (found && !saved.length) throw new Error('could not copy catalog apps');
  return { ok: true, apps: saved.length };
}

async function personalRestoreApps() {
  const serial = await adbSerial();
  const appDir = path.join(personalRoot(), 'apps');
  if (!fs.existsSync(appDir)) throw new Error('no catalog app copies saved');
  const realRoot = await fsp.realpath(appDir);
  const names = Object.keys(CATALOG_PACKAGES);
  let installed = 0;
  let present = 0;
  const failed = [];
  for (let i = 0; i < names.length; i++) {
    const pkg = names[i];
    const local = path.join(appDir, pkg + '.apk');
    if (!fs.existsSync(local)) continue;
    const real = await fsp.realpath(local);
    if (real.indexOf(realRoot + path.sep) !== 0) continue;
    present += 1;
    const stage = WIZARD_STAGING + '/catalog-restore.apk';
    let error = 'install failed';
    try {
      await wizardHostSu(serial, 'mkdir -p ' + shellQuote(WIZARD_STAGING), 60000);
      await adbRun(['-s', serial, 'push', real, stage], 180000);
      const out = await adbRun(
        ['-s', serial, 'shell', 'su', '0', 'sh', '-c', shellQuote('pm install -r ' + shellQuote(stage))],
        180000);
      if (/Success/.test(out)) {
        installed += 1;
        continue;
      }
      const code = String(out).match(/INSTALL_FAILED_[A-Z0-9_]+/);
      error = code ? code[0] : 'install failed';
    } catch (e) {
      const safe = publicError(e);
      error = /INSTALL_FAILED_[A-Z0-9_]+/.test(safe) ? safe : 'install failed';
    } finally {
      await adbRun(['-s', serial, 'shell', 'rm', '-f', stage], 30000).catch(function () {});
    }
    failed.push({ packageName: pkg, error: error });
  }
  if (!present) throw new Error('no catalog app copies saved');
  return { ok: failed.length === 0, installed: installed, failed: failed, apps: present };
}

ipcMain.handle('personal-backup-info', function () { return personalGuard(personalBackupInfo)(); });
ipcMain.handle('personal-backup-contacts', function () { return personalGuard(personalBackupContacts)(); });
ipcMain.handle('personal-backup-messages', function () { return personalGuard(personalBackupMessages)(); });
ipcMain.handle('personal-backup-apps', function () { return personalGuard(personalBackupApps)(); });
ipcMain.handle('personal-restore-contacts', function (_e, payload) { return personalGuard(personalRestoreContacts)(payload); });
ipcMain.handle('personal-restore-messages', function (_e, payload) { return personalGuard(personalRestoreMessages)(payload); });
ipcMain.handle('personal-restore-apps', function () { return personalGuard(personalRestoreApps)(); });

function createWindow() {
  const win = new BrowserWindow({
    width: 1020,
    height: 800,
    autoHideMenuBar: true,
    title: 'TCL Flip2 Manager',
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
  ipcMain.handle('wizard-host-adb-ready', function () { return wizardHostAdbReady(); });
  ipcMain.handle('wizard-host-shell', function (_e, payload) { return wizardHostShell(payload); });
  ipcMain.handle('wizard-host-prepare', function () { return wizardHostPrepare(); });
  ipcMain.handle('wizard-host-push-one', function (_e, payload) { return wizardHostPushOne(payload); });
  ipcMain.handle('wizard-host-run-install', function (_e, payload) { return wizardHostRunInstall(payload); });
  ipcMain.handle('wizard-host-cleanup', function () { return wizardHostCleanup(); });
  ipcMain.handle('wizard-host-verify', function (_e, payload) { return wizardHostVerify(payload); });
  ipcMain.handle('wizard-host-write-profile', function (_e, payload) { return wizardHostWriteProfile(payload); });
  ipcMain.handle('wizard-host-install-apk', function (_e, payload) { return wizardHostInstallApk(payload); });
  ipcMain.handle('wizard-host-uninstall-package', function (_e, payload) { return wizardHostUninstallPackage(payload); });
  ipcMain.handle('wizard-host-remove-module', function (_e, payload) { return wizardHostRemoveModule(payload); });
  ipcMain.handle('wizard-host-set-device-owner', function (_e, payload) { return wizardHostSetDeviceOwner(payload); });
  ipcMain.handle('wizard-host-drop-root-adb', function (_e, payload) { return wizardHostDropRootAdb(payload); });
  createWindow();
  app.on('activate', function () {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', function () { app.quit(); });
