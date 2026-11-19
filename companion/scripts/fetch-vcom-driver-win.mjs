#!/usr/bin/env node
/**
 * Download MediaTek USB VCOM driver pack (third-party mirror) into
 * companion/vcom-driver-win/ for electron-builder extraResources.
 * Win7 x64 INF + binary usbser.sys; overlay repo flip2_preloader_vcom.inf (no mdmcpq.inf).
 * Safe to re-run; skips if flip2_preloader_vcom.inf + usbser.sys present.
 */
import { createWriteStream } from 'fs';
import { mkdir, access, rm, writeFile, copyFile, readFile } from 'fs/promises';
import { createHash } from 'crypto';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { pipeline } from 'stream/promises';
import { createRequire } from 'module';

const require = createRequire(import.meta.url);
const __dir = dirname(fileURLToPath(import.meta.url));
const COMPANION = join(__dir, '..');
const OUT = join(COMPANION, 'vcom-driver-win');
const FLIP2_INF = 'flip2_preloader_vcom.inf';
const URL = 'https://spflashtool.com/download/MediaTek_USB_VCOM_drivers.zip';
const REFERER = 'https://spflashtool.com/';
/** Pinned when mirror serves this blob (Nov 2025 fetch). */
const EXPECTED_SHA256 =
  '5d13be18ed4bddeabe68e099732c421ec061b306f939222ffc91ed257783309f';

const ZIP_PREFIX = 'MediaTek USB VCOM drivers/Drivers/';
const EXTRACT_PATHS = [
  'Driver - USB VCOM Driver (binary)/mtk_sp_usb2ser.inf',
  'Driver - USB VCOM Driver (binary)/usbser.sys',
  'USB VCOM Driver/Win7/usb2ser_Win7.inf',
  'USB VCOM Driver/Win7/usb2ser_Win764.inf',
];

async function exists(p) {
  try {
    await access(p);
    return true;
  } catch {
    return false;
  }
}

async function overlayFlip2Inf() {
  const src = join(COMPANION, 'vcom-driver-win', FLIP2_INF);
  if (await exists(src)) {
    await copyFile(src, join(OUT, FLIP2_INF));
    return true;
  }
  return false;
}

async function ready() {
  return (
    (await exists(join(OUT, FLIP2_INF))) && (await exists(join(OUT, 'usbser.sys')))
  );
}

async function main() {
  if (await ready()) {
    console.log('vcom-driver-win: already present at', OUT);
    return;
  }

  let unzipper;
  try {
    unzipper = require('unzipper');
  } catch {
    console.error('Missing unzipper — run: cd companion && npm install');
    process.exit(1);
  }

  console.log('Fetching', URL);
  const res = await fetch(URL, {
    redirect: 'follow',
    headers: {
      'User-Agent': 'flip2-companion-fetch/1.0',
      Referer: REFERER,
    },
  });
  if (!res.ok) throw new Error('HTTP ' + res.status);
  const buf = Buffer.from(await res.arrayBuffer());
  if (buf.length < 500_000) {
    throw new Error(
      'Download too small (' +
        buf.length +
        ' bytes) — mirror may have returned HTML; open ' +
        URL +
        ' in a browser with Referer ' +
        REFERER,
    );
  }
  const sha = createHash('sha256').update(buf).digest('hex');
  if (sha !== EXPECTED_SHA256) {
    console.warn(
      'vcom-driver-win: SHA-256 mismatch (got ' +
        sha +
        '; expected ' +
        EXPECTED_SHA256 +
        ') — extracting anyway; update pin in fetch-vcom-driver-win.mjs if intentional',
    );
  }

  let flip2Backup = null;
  if (await exists(join(OUT, FLIP2_INF))) {
    flip2Backup = await readFile(join(OUT, FLIP2_INF));
  }

  await rm(OUT, { recursive: true, force: true });
  await mkdir(OUT, { recursive: true });

  if (flip2Backup) {
    await writeFile(join(OUT, FLIP2_INF), flip2Backup);
  }

  const directory = await unzipper.Open.buffer(buf);
  const want = new Map();
  for (const rel of EXTRACT_PATHS) {
    const zipPath = ZIP_PREFIX + rel;
    const base = rel.split('/').pop();
    want.set(zipPath, base);
  }

  for (const entry of directory.files) {
    const norm = entry.path.replace(/\\/g, '/');
    const base = want.get(norm);
    if (!base) continue;
    const dest = join(OUT, base);
    await pipeline(entry.stream(), createWriteStream(dest));
  }

  const usbser = join(OUT, 'usbser.sys');
  if (!(await exists(usbser))) {
    throw new Error('Zip missing usbser.sys from binary folder');
  }

  if (!(await exists(join(OUT, FLIP2_INF)))) {
    const ok = await overlayFlip2Inf();
    if (!ok) {
      throw new Error(
        'Missing ' +
          FLIP2_INF +
          ' — commit companion/vcom-driver-win/' +
          FLIP2_INF +
          ' in the repo',
      );
    }
  }

  const notice = join(OUT, 'THIRD_PARTY_NOTICE.txt');
  await writeFile(
    notice,
    [
      'MediaTek USB VCOM drivers (usb2ser_*.inf, usbser.sys)',
      'Copyright MediaTek Inc. — retrieved via third-party mirror:',
      URL,
      '',
      'Not affiliated with MediaTek or spflashtool.com.',
      'Install preloader VCOM (0e8d:2000): Device Manager → Update driver → Browse my computer →',
      'Let me pick from a list → Have Disk → Browse → ' + FLIP2_INF + ' in this folder.',
      'Zip SHA-256 at pack time: ' + sha,
      '',
    ].join('\n'),
    'utf8',
  );

  console.log('vcom-driver-win: wrote', OUT);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
