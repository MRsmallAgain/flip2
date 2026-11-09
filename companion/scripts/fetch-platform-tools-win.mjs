#!/usr/bin/env node
/**
 * Download Google platform-tools (Windows) into companion/platform-tools-win/
 * for electron-builder extraResources. Safe to re-run; skips if adb.exe exists.
 */
import { createWriteStream } from 'fs';
import { mkdir, access, rm } from 'fs/promises';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { pipeline } from 'stream/promises';
import { createRequire } from 'module';

const require = createRequire(import.meta.url);
const __dir = dirname(fileURLToPath(import.meta.url));
const COMPANION = join(__dir, '..');
const OUT = join(COMPANION, 'platform-tools-win');
const URL = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip';

const NEED = ['adb.exe', 'AdbWinApi.dll', 'AdbWinUsbApi.dll'];

async function exists(p) {
  try {
    await access(p);
    return true;
  } catch {
    return false;
  }
}

async function main() {
  const adb = join(OUT, 'adb.exe');
  if (await exists(adb)) {
    console.log('platform-tools-win: already present at', OUT);
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
  const res = await fetch(URL, { redirect: 'follow' });
  if (!res.ok) throw new Error('HTTP ' + res.status);
  const buf = Buffer.from(await res.arrayBuffer());

  await rm(OUT, { recursive: true, force: true });
  await mkdir(OUT, { recursive: true });

  const directory = await unzipper.Open.buffer(buf);
  for (const entry of directory.files) {
    const raw = entry.path.replace(/\\/g, '/');
    const parts = raw.split('/');
    const base = parts[parts.length - 1];
    if (!NEED.includes(base) && base !== 'fastboot.exe') continue;
    const dest = join(OUT, base);
    await pipeline(entry.stream(), createWriteStream(dest));
  }

  for (const f of NEED) {
    if (!(await exists(join(OUT, f)))) {
      throw new Error('Zip missing ' + f);
    }
  }
  console.log('platform-tools-win: wrote', OUT);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
