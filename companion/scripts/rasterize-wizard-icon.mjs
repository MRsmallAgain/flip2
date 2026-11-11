#!/usr/bin/env node
/**
 * Rasterize wizard/assets/logo.svg (header phone) into companion/icons/ for
 * Electron window + electron-builder (Windows/Linux need PNG, not SVG).
 */
import { readFileSync, writeFileSync, mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { Resvg } from '@resvg/resvg-js';

const __dir = dirname(fileURLToPath(import.meta.url));
const COMPANION = join(__dir, '..');
const SVG = join(COMPANION, '..', 'wizard', 'assets', 'logo.svg');
const OUT_DIR = join(COMPANION, 'icons');

function render(size) {
  const svg = readFileSync(SVG, 'utf8');
  const resvg = new Resvg(svg, {
    fitTo: { mode: 'width', value: size },
  });
  return resvg.render().asPng();
}

mkdirSync(OUT_DIR, { recursive: true });
writeFileSync(join(OUT_DIR, 'icon.png'), render(512));
writeFileSync(join(OUT_DIR, 'icon-32.png'), render(32));
console.log('Wrote', join(OUT_DIR, 'icon.png'), 'and icon-32.png from', SVG);
