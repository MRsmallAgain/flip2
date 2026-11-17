#!/usr/bin/env node
/**
 * Download UsbDk (redistributable) into companion/preloader-drivers-win/
 * for electron-builder extraResources. Safe to re-run; skips if MSI exists.
 * MTK USB VCOM is not redistributable here — see bundled README.txt.
 */
import { createWriteStream } from 'fs';
import { mkdir, access, writeFile } from 'fs/promises';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { pipeline } from 'stream/promises';

const __dir = dirname(fileURLToPath(import.meta.url));
const COMPANION = join(__dir, '..');
const OUT = join(COMPANION, 'preloader-drivers-win');
const USBDK_URL =
  'https://github.com/daynix/UsbDk/releases/download/v1.00-22/UsbDk_1.0.22_x64.msi';
const USBDK_NAME = 'UsbDk_1.0.22_x64.msi';

const README = `Preloader / mtkclient helpers (Windows)
=============================================

Bundled with TCL Flip2 Manager for the rooting step (MTK preloader 0e8d:2000).

1. UsbDk (UsbDk_1.0.22_x64.msi)
   Optional but recommended for mtkclient and some USB access patterns.
   In the app: Rooting → Install UsbDk, or double-click the MSI (admin).

2. MediaTek USB VCOM driver (NOT bundled)
   Companion auto-connects to the preloader over a serial COM port. On Windows
   that port only appears after the MediaTek USB VCOM driver is installed.

   Typical steps:
   - Download MediaTek SP Flash Tool or the official VCOM driver package from
     MediaTek / your device vendor (not redistributed in this app).
   - Device Manager → update driver for the unknown MTK device (0e8d:2000)
     or "Install from disk" using the vendor .inf.

   Google USB Driver (adb) does NOT provide VCOM — it is separate from adb.

3. Google platform-tools
   Bundled separately under resources\\platform-tools\\ (adb for Prepare).

After installing VCOM: unplug USB, remove/reinsert battery, replug USB, then
Start watching again in the rooting step.
`;

async function exists(p) {
  try {
    await access(p);
    return true;
  } catch {
    return false;
  }
}

async function main() {
  const msi = join(OUT, USBDK_NAME);
  await mkdir(OUT, { recursive: true });
  await writeFile(join(OUT, 'README.txt'), README, 'utf8');

  if (await exists(msi)) {
    console.log('preloader-drivers-win: already present at', OUT);
    return;
  }

  console.log('Fetching', USBDK_URL);
  const res = await fetch(USBDK_URL, { redirect: 'follow' });
  if (!res.ok) throw new Error('HTTP ' + res.status);

  await pipeline(res.body, createWriteStream(msi));
  if (!(await exists(msi))) {
    throw new Error('Failed to write ' + USBDK_NAME);
  }
  console.log('preloader-drivers-win: wrote', OUT);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
