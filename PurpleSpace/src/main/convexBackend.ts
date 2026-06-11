/**
 * @file convexBackend.ts — lifecycle of the embedded Convex backend.
 *
 * Purple Space runs the open-source `convex-local-backend` binary (bundled
 * in Contents/Resources/resources/) as a child process — no Convex account,
 * no docker, fully offline. Everything persistent lives under the app's
 * userData dir:
 *
 *   convex-config.json                   instance name/secret + admin key
 *   convex/convex_local_backend.sqlite3  the database
 *   convex/convex_local_storage/         file storage (images, covers)
 *   logs/convex-backend.log              backend stdout/stderr
 *
 * The instance secret is generated per install; the admin key is derived
 * deterministically from (name, secret) via the binary's own
 * `keygen admin-key` subcommand. `scripts/deploy-functions.sh` reads the
 * same config file to push convex/ functions to the running backend.
 *
 * If something already answers on our port (e.g. a backend orphaned by a
 * force-killed app — same data dir, same config), we adopt it instead of
 * spawning a second one.
 */
import { app } from 'electron';
import { spawn, execFile, type ChildProcess } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { createWriteStream, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import type { BackendStatus } from '../shared/types';

/** Keep in sync with scripts/fetch-backend.sh (BACKEND_TAG). */
export const BACKEND_TAG = 'precompiled-2026-06-09-b6aaa1a';

const PORT = 47800;
const SITE_PORT = 47801;
const INSTANCE_NAME = 'purple-space';
const READY_TIMEOUT_MS = 60_000;

export interface ConvexConfig {
  instanceName: string;
  instanceSecret: string;
  adminKey: string;
  port: number;
  sitePort: number;
  backendTag: string;
}

let child: ChildProcess | null = null;
let status: BackendStatus = {
  state: 'starting',
  url: `http://127.0.0.1:${PORT}`,
  siteUrl: `http://127.0.0.1:${SITE_PORT}`
};
let statusListener: ((s: BackendStatus) => void) | null = null;

export function getStatus(): BackendStatus {
  return status;
}

export function onStatusChange(cb: (s: BackendStatus) => void): void {
  statusListener = cb;
}

function setStatus(next: Partial<BackendStatus>): void {
  status = { ...status, ...next };
  statusListener?.(status);
}

export function binaryPath(): string {
  return app.isPackaged
    ? join(process.resourcesPath, 'resources', 'convex-local-backend')
    : join(app.getAppPath(), 'resources', 'convex-local-backend');
}

function configPath(): string {
  return join(app.getPath('userData'), 'convex-config.json');
}

function keygenAdminKey(bin: string, name: string, secret: string): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(
      bin,
      ['keygen', 'admin-key', '--instance-name', name, '--instance-secret', secret],
      { timeout: 30_000 },
      (err, stdout) => {
        if (err) return reject(err);
        const key = stdout.trim().split('\n').pop()?.trim();
        if (!key) return reject(new Error('keygen produced no output'));
        resolve(key);
      }
    );
  });
}

/** Load or create the per-install instance config (secret + admin key). */
export async function ensureConfig(): Promise<ConvexConfig> {
  const path = configPath();
  if (existsSync(path)) {
    const cfg = JSON.parse(readFileSync(path, 'utf8')) as ConvexConfig;
    if (cfg.instanceSecret && cfg.adminKey) return cfg;
  }
  mkdirSync(app.getPath('userData'), { recursive: true });
  const instanceSecret = randomBytes(32).toString('hex');
  const adminKey = await keygenAdminKey(binaryPath(), INSTANCE_NAME, instanceSecret);
  const cfg: ConvexConfig = {
    instanceName: INSTANCE_NAME,
    instanceSecret,
    adminKey,
    port: PORT,
    sitePort: SITE_PORT,
    backendTag: BACKEND_TAG
  };
  writeFileSync(path, JSON.stringify(cfg, null, 2));
  return cfg;
}

async function isUp(port: number): Promise<boolean> {
  try {
    const res = await fetch(`http://127.0.0.1:${port}/version`, {
      signal: AbortSignal.timeout(1500)
    });
    return res.ok || res.status < 500;
  } catch {
    return false;
  }
}

/** Start (or adopt) the backend; resolves when it answers HTTP. */
export async function startBackend(): Promise<BackendStatus> {
  try {
    const bin = binaryPath();
    if (!existsSync(bin)) {
      throw new Error(
        `convex-local-backend missing at ${bin} — run scripts/fetch-backend.sh and rebuild`
      );
    }
    const cfg = await ensureConfig();

    // Adopt an already-listening backend (orphan from a force-killed app:
    // same data dir + config, so it is exactly the server we want).
    if (await isUp(cfg.port)) {
      setStatus({ state: 'ready' });
      return status;
    }

    const dataDir = join(app.getPath('userData'), 'convex');
    const logsDir = join(app.getPath('userData'), 'logs');
    mkdirSync(dataDir, { recursive: true });
    mkdirSync(logsDir, { recursive: true });
    const log = createWriteStream(join(logsDir, 'convex-backend.log'), { flags: 'a' });
    log.write(`\n--- backend start ${new Date().toISOString()} (${BACKEND_TAG}) ---\n`);

    child = spawn(
      bin,
      [
        '--interface', '127.0.0.1',
        '--port', String(cfg.port),
        '--site-proxy-port', String(cfg.sitePort),
        '--convex-origin', `http://127.0.0.1:${cfg.port}`,
        '--convex-site', `http://127.0.0.1:${cfg.sitePort}`,
        '--instance-name', cfg.instanceName,
        '--instance-secret', cfg.instanceSecret,
        '--local-storage', join(dataDir, 'convex_local_storage'),
        '--disable-beacon',
        join(dataDir, 'convex_local_backend.sqlite3')
      ],
      { cwd: dataDir, stdio: ['ignore', 'pipe', 'pipe'] }
    );
    child.stdout?.pipe(log);
    child.stderr?.pipe(log);
    child.on('exit', (code) => {
      child = null;
      if (status.state !== 'ready') {
        setStatus({ state: 'error', error: `backend exited with code ${code} during startup` });
      }
    });

    const deadline = Date.now() + READY_TIMEOUT_MS;
    while (Date.now() < deadline) {
      if (await isUp(cfg.port)) {
        setStatus({ state: 'ready' });
        return status;
      }
      if (!child) break; // crashed during startup
      await new Promise((r) => setTimeout(r, 250));
    }
    if (status.state !== 'error') {
      setStatus({ state: 'error', error: 'backend did not become ready in time' });
    }
    return status;
  } catch (err) {
    setStatus({ state: 'error', error: err instanceof Error ? err.message : String(err) });
    return status;
  }
}

/** Graceful stop on app quit. */
export function stopBackend(): void {
  if (child) {
    child.kill('SIGTERM');
    child = null;
  }
}
