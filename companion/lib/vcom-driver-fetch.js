/**
 * MediaTek USB VCOM driver — download ZIP, extract INF + usbser.sys into destDir.
 * Used by prepack script (mjs wrapper) and companion main (runtime Get files).
 */
const crypto = require('crypto');
const fs = require('fs');
const fsp = require('fs').promises;
const path = require('path');
const { pipeline } = require('stream/promises');

const VCOM_ZIP_URL = 'https://spflashtool.com/download/MediaTek_USB_VCOM_drivers.zip';
const VCOM_REFERER = 'https://spflashtool.com/';
const EXPECTED_SHA256 =
  '5d13be18ed4bddeabe68e099732c421ec061b306f939222ffc91ed257783309f';
const ZIP_PREFIX = 'MediaTek USB VCOM drivers/Drivers/';
/** Self-contained INF (no mdmcpq.inf); MTK usb2ser_Win764.inf fails folder browse on Win10/11. */
const INF_MARKER = 'flip2_preloader_vcom.inf';
const LEGACY_INF = 'usb2ser_Win764.inf';
const EXTRACT_PATHS = [
  'Driver - USB VCOM Driver (binary)/mtk_sp_usb2ser.inf',
  'Driver - USB VCOM Driver (binary)/usbser.sys',
  'USB VCOM Driver/Win7/usb2ser_Win7.inf',
  'USB VCOM Driver/Win7/usb2ser_Win764.inf',
];

async function pathExists(p) {
  try {
    await fsp.access(p);
    return true;
  } catch {
    return false;
  }
}

async function vcomReady(destDir) {
  if (!destDir) return false;
  const inf = path.join(destDir, INF_MARKER);
  const legacy = path.join(destDir, LEGACY_INF);
  const sys = path.join(destDir, 'usbser.sys');
  const hasInf = (await pathExists(inf)) || (await pathExists(legacy));
  return hasInf && (await pathExists(sys));
}

function resolveInstallInf(destDir) {
  const preferred = path.join(destDir, INF_MARKER);
  if (fs.existsSync(preferred)) return preferred;
  return path.join(destDir, LEGACY_INF);
}

/**
 * @param {string} destDir
 * @param {{ fetchFn?: typeof fetch, unzipper?: object, skipShaWarn?: boolean }} [opts]
 */
async function ensureVcomDriverAt(destDir, opts) {
  opts = opts || {};
  if (process.platform !== 'win32') {
    return { ok: false, message: 'VCOM driver is only needed on Windows.' };
  }
  if (await vcomReady(destDir)) {
    return {
      ok: true,
      cached: true,
      dir: destDir,
      inf: resolveInstallInf(destDir),
      message: 'VCOM driver files are already on this PC.',
    };
  }

  const fetchFn = opts.fetchFn || fetch;
  const res = await fetchFn(VCOM_ZIP_URL, {
    redirect: 'follow',
    headers: {
      'User-Agent': 'flip2-companion-fetch/1.0',
      Referer: VCOM_REFERER,
    },
  });
  if (!res.ok) throw new Error('HTTP ' + res.status + ' from VCOM mirror');
  const buf = Buffer.from(await res.arrayBuffer());
  if (buf.length < 500_000) {
    throw new Error(
      'VCOM download too small — mirror may have returned HTML instead of the ZIP',
    );
  }
  const sha = crypto.createHash('sha256').update(buf).digest('hex');
  if (sha !== EXPECTED_SHA256 && !opts.skipShaWarn) {
    // Still extract; pin drift is surfaced in logs only.
    console.warn('vcom-driver: SHA-256 mismatch (got ' + sha + ')');
  }

  let unzipper = opts.unzipper;
  if (!unzipper) {
    try {
      unzipper = require('unzipper');
    } catch (e) {
      throw new Error('Missing unzipper — reinstall the companion or run npm install in companion/');
    }
  }

  await fsp.rm(destDir, { recursive: true, force: true }).catch(function () {});
  await fsp.mkdir(destDir, { recursive: true });

  const directory = await unzipper.Open.buffer(buf);
  const want = new Map();
  for (const rel of EXTRACT_PATHS) {
    const zipPath = ZIP_PREFIX + rel;
    want.set(zipPath, rel.split('/').pop());
  }

  for (const entry of directory.files) {
    const norm = entry.path.replace(/\\/g, '/');
    const base = want.get(norm);
    if (!base) continue;
    const dest = path.join(destDir, base);
    await pipeline(entry.stream(), fs.createWriteStream(dest));
  }

  await copyBundledFlip2Inf(destDir);

  if (!(await vcomReady(destDir))) {
    throw new Error('Zip did not contain usbser.sys and a VCOM INF');
  }

  const notice = path.join(destDir, 'THIRD_PARTY_NOTICE.txt');
  await fsp.writeFile(
    notice,
    [
      'MediaTek USB VCOM drivers (usb2ser_*.inf, usbser.sys)',
      'Retrieved via third-party mirror: ' + VCOM_ZIP_URL,
      'Install via Device Manager → Update driver → Browse → Let me pick → Have Disk → Browse → ' +
        INF_MARKER +
        ' in this folder.',
      'Zip SHA-256: ' + sha,
      '',
    ].join('\n'),
    'utf8',
  );

  return {
    ok: true,
    cached: false,
    dir: destDir,
    inf: resolveInstallInf(destDir),
    message: 'Downloaded and unpacked the MediaTek VCOM driver.',
  };
}

/** Path to repo-shipped self-contained INF (sibling of lib/). */
function bundledFlip2InfPath() {
  return path.join(__dirname, '..', 'vcom-driver-win', INF_MARKER);
}

async function copyBundledFlip2Inf(destDir) {
  const src = bundledFlip2InfPath();
  if (!fs.existsSync(src)) return false;
  await fsp.copyFile(src, path.join(destDir, INF_MARKER));
  return true;
}

/** Files copied from packaged extraResources into a normal folder for Device Manager Browse / Have Disk. */
const STAGE_FROM_BUNDLED = [
  INF_MARKER,
  'usbser.sys',
  LEGACY_INF,
  'usb2ser_Win7.inf',
  'mtk_sp_usb2ser.inf',
  'THIRD_PARTY_NOTICE.txt',
];

/**
 * Copy bundled VCOM files into destDir (e.g. Downloads\flip2-wizard\vcom-driver).
 * Device Manager often rejects asar/temp paths under LocalAppData\Temp.
 * @param {string} bundledDir
 * @param {string} destDir
 */
async function stageVcomFromBundled(bundledDir, destDir) {
  if (!bundledDir || !destDir) return false;
  await fsp.mkdir(destDir, { recursive: true });
  let copied = 0;
  for (const name of STAGE_FROM_BUNDLED) {
    const src = path.join(bundledDir, name);
    if (!fs.existsSync(src)) continue;
    await fsp.copyFile(src, path.join(destDir, name));
    copied++;
  }
  if (!fs.existsSync(path.join(destDir, INF_MARKER))) {
    await copyBundledFlip2Inf(destDir);
  }
  return await vcomReady(destDir);
}

module.exports = {
  VCOM_ZIP_URL,
  VCOM_REFERER,
  EXPECTED_SHA256,
  INF_MARKER,
  LEGACY_INF,
  vcomReady,
  resolveInstallInf,
  copyBundledFlip2Inf,
  stageVcomFromBundled,
  ensureVcomDriverAt,
};
