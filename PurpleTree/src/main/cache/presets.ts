/**
 * @file presets.ts — load + token-expand the declarative cache presets.
 *
 * Token expansion happens here in main (it owns os.homedir / process.env);
 * the renderer only ever sees resolved, existence-checked absolute paths.
 * The pure helpers (`expandTokens`, `filterByPlatform`) are unit-tested.
 */
import { app } from 'electron';
import { existsSync, readFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import type { CachePreset } from '../../shared/types';
import { expandTokens, filterByPlatform, type TokenEnv } from './tokens';

export type { TokenEnv } from './tokens';

/** The token map for this machine. */
export function machineEnv(): TokenEnv {
  return {
    HOME: homedir(),
    LOCALAPPDATA: process.env.LOCALAPPDATA ?? join(homedir(), 'AppData', 'Local'),
    TMPDIR: tmpdir()
  };
}

/** Path to the bundled presets file (dev tree or packaged resources). */
function presetsFilePath(): string {
  const rel = join('resources', 'cache-presets.json');
  return app.isPackaged ? join(process.resourcesPath, rel) : join(app.getAppPath(), rel);
}

let cached: CachePreset[] | null = null;

export function loadCachePresets(): CachePreset[] {
  if (cached) return cached;
  try {
    cached = JSON.parse(readFileSync(presetsFilePath(), 'utf8')) as CachePreset[];
  } catch (err) {
    console.error('[PurpleTree] failed to load cache presets:', err);
    cached = [];
  }
  return cached;
}

/** A preset with tokens expanded and paths narrowed to those that exist. */
export interface ResolvedPresetPaths {
  id: string;
  label: string;
  description: string;
  riskLevel: CachePreset['riskLevel'];
  paths: string[];
}

export function resolvePresetPaths(
  platform: NodeJS.Platform = process.platform,
  env: TokenEnv = machineEnv()
): ResolvedPresetPaths[] {
  return filterByPlatform(loadCachePresets(), platform).map((p) => ({
    id: p.id,
    label: p.label,
    description: p.description,
    riskLevel: p.riskLevel,
    paths: p.paths.map((t) => expandTokens(t, env)).filter((abs) => existsSync(abs))
  }));
}
