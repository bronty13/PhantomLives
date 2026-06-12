/**
 * @file store.ts — JSON persistence for preferences and the save file
 * (score history, trophies, lifetime totals). Plain files in userData:
 *   purple-chef-prefs.json
 *   purple-chef-save.json
 */
import { app } from 'electron';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { EMPTY_SAVE, foldResult, evaluatePrizes } from '../shared/prizes';
import type { MatchResult, Preferences, SaveData } from '../shared/types';

const PREFS_FILE = 'purple-chef-prefs.json';
const SAVE_FILE = 'purple-chef-save.json';

function defaultBackupPath(): string {
  return join(homedir(), 'Downloads', 'Purple Chef backup');
}

export const DEFAULT_PREFS: Preferences = {
  version: 1,
  soundEnabled: true,
  musicEnabled: true,
  chefName: 'Chef You',
  autoBackupEnabled: true,
  backupPath: defaultBackupPath(),
  backupRetentionDays: 14,
  lastBackupMs: 0,
  windowWidth: 1440,
  windowHeight: 920
};

function fileOf(name: string): string {
  return join(app.getPath('userData'), name);
}

function readJson<T>(name: string, fallback: T): T {
  try {
    return { ...fallback, ...JSON.parse(readFileSync(fileOf(name), 'utf8')) };
  } catch {
    return structuredClone(fallback);
  }
}

function writeJson(name: string, data: unknown): void {
  mkdirSync(app.getPath('userData'), { recursive: true });
  writeFileSync(fileOf(name), JSON.stringify(data, null, 2));
}

let prefsCache: Preferences | null = null;
let saveCache: SaveData | null = null;

export function getPreferences(): Preferences {
  if (!prefsCache) prefsCache = readJson(PREFS_FILE, DEFAULT_PREFS);
  return prefsCache;
}

export function setPreferences(patch: Partial<Preferences>): Preferences {
  const next = { ...getPreferences(), ...patch, version: DEFAULT_PREFS.version };
  prefsCache = next;
  writeJson(PREFS_FILE, next);
  return next;
}

export function getSave(): SaveData {
  if (!saveCache) saveCache = readJson(SAVE_FILE, EMPTY_SAVE);
  return saveCache;
}

export interface RecordOutcome {
  save: SaveData;
  newTrophyIds: string[];
}

/** Fold a finished match into the save file; returns newly earned trophy ids. */
export function recordResult(result: MatchResult): RecordOutcome {
  const before = getSave();
  const after = foldResult(before, result);
  const newTrophyIds = evaluatePrizes(result, { ...after, trophies: before.trophies }).map(
    (t) => t.id
  );
  saveCache = after;
  writeJson(SAVE_FILE, after);
  return { save: after, newTrophyIds };
}

/** Test hook: drop caches so a fresh read hits disk. */
export function resetStoreCaches(): void {
  prefsCache = null;
  saveCache = null;
}
