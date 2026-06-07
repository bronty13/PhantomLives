#!/usr/bin/env node
// Wrap the single-file build into a distributable ZIP. The user unzips and opens
// index.html directly from file:// — no server, fully offline.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import JSZip from 'jszip';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');
const indexPath = resolve(ROOT, 'dist/index.html');

if (!existsSync(indexPath)) {
  console.error('! dist/index.html not found — run `vite build` first.');
  process.exit(1);
}

const html = readFileSync(indexPath);
const zip = new JSZip();
zip.file('index.html', html);

const buf = await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE', compressionOptions: { level: 9 } });
const outPath = resolve(ROOT, 'dist/CalendarMaker-app.zip');
writeFileSync(outPath, buf);
console.log(`✓ ${outPath} (${(buf.length / 1024 / 1024).toFixed(2)} MB; index.html ${(html.length / 1024 / 1024).toFixed(2)} MB)`);
