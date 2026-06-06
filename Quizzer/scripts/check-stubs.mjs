// Guardrail: fail if either committed player-template stub has been left as a built
// blob (the ~900 KB output of `npm run build`). Run before committing — pairs with
// `npm run restore:stubs`. A standalone node check (not a vitest test) so the default
// `npm test` is unaffected by the post-build state of these generated files.

import { readFileSync, statSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const gen = resolve(__dirname, '..', 'src/creator/generated');
const LIMIT = 2048; // canonical stubs are ~500 bytes; built blobs are ~900 KB.

const files = ['playerTemplate.ts', 'wheelTemplate.ts'];
let bad = false;

for (const f of files) {
  const p = resolve(gen, f);
  const size = statSync(p).size;
  const hasMarker = readFileSync(p, 'utf8').includes('<!--QUIZ_PAYLOAD-->');
  if (size > LIMIT) {
    console.error(`✗ ${f} is ${size} bytes (> ${LIMIT}). Run "npm run restore:stubs" before committing.`);
    bad = true;
  } else if (!hasMarker) {
    console.error(`✗ ${f} is missing the <!--QUIZ_PAYLOAD--> marker — stub looks corrupt.`);
    bad = true;
  } else {
    console.log(`✓ ${f} (${size} bytes, stub OK).`);
  }
}

process.exit(bad ? 1 : 0);
