// Dev helper: make sure the embedded wheel template exists and is reasonably fresh
// before starting the creator dev server. Rebuilds + re-embeds the wheel player if
// the built output is missing or older than any wheel-player/shared source file.

import { execSync } from 'node:child_process';
import { existsSync, statSync, readdirSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, '..');
const built = resolve(root, 'dist-wheel/index.html');
const template = resolve(root, 'src/creator/generated/wheelTemplate.ts');

function newestMtime(dir) {
  let newest = 0;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) newest = Math.max(newest, newestMtime(p));
    else newest = Math.max(newest, statSync(p).mtimeMs);
  }
  return newest;
}

const srcNewest = Math.max(
  newestMtime(resolve(root, 'src/wheel-player')),
  newestMtime(resolve(root, 'src/shared')),
);

const stale =
  !existsSync(built) ||
  !existsSync(template) ||
  statSync(built).mtimeMs < srcNewest;

if (stale) {
  console.log('[ensure-wheel] (re)building wheel template…');
  execSync('npm run build:wheel && npm run embed:wheel', { cwd: root, stdio: 'inherit' });
} else {
  console.log('[ensure-wheel] wheel template is up to date.');
}
