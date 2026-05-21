import { app, protocol, net } from 'electron';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

/**
 * Resolve the on-disk location of a bundled asset under resources/.
 *
 * - In packaged builds, electron-builder copies the `resources/` directory
 *   into the app bundle's resources via `extraResources` in package.json;
 *   `process.resourcesPath` points to that directory.
 * - In development, the project root has a top-level `resources/` directory
 *   relative to the running cwd (we start from project root via electron-vite).
 */
export function assetPath(...parts: string[]): string {
  const candidates = app.isPackaged
    ? [join(process.resourcesPath, 'resources', ...parts), join(process.resourcesPath, ...parts)]
    : [join(process.cwd(), 'resources', ...parts), join(__dirname, '..', '..', 'resources', ...parts)];
  for (const c of candidates) {
    if (existsSync(c)) return c;
  }
  return candidates[0];
}

export function readAsset(...parts: string[]): Buffer {
  return readFileSync(assetPath(...parts));
}

/** Must be called BEFORE `app.whenReady()` resolves protocol handlers. */
export function registerAssetProtocolScheme(): void {
  protocol.registerSchemesAsPrivileged([
    {
      scheme: 'pp-asset',
      privileges: {
        standard: true,
        secure: true,
        supportFetchAPI: true,
        bypassCSP: true,
        corsEnabled: true,
        stream: true
      }
    }
  ]);
}

/** Call after `app.whenReady()`. Handles pp-asset://<relpath> URLs. */
export function registerAssetProtocolHandler(): void {
  protocol.handle('pp-asset', (request) => {
    try {
      const url = new URL(request.url);
      // url.host is empty for pp-asset:///path; treat host + pathname as relpath.
      const rel = decodeURIComponent((url.host ? `${url.host}/` : '') + url.pathname.replace(/^\/+/, ''));
      const safe = rel.split('/').filter((p) => p && p !== '..' && p !== '.');
      const file = assetPath(...safe);
      if (!existsSync(file)) {
        return new Response(`Not found: ${rel}`, { status: 404 });
      }
      return net.fetch(pathToFileURL(file).toString());
    } catch (err) {
      return new Response(`Bad asset request: ${(err as Error).message}`, { status: 400 });
    }
  });
}
