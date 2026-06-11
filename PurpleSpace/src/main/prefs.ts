/**
 * @file prefs.ts — per-install user preferences.
 *
 * Persists to `<userData>/purple-space-prefs.json` via electron-store. The
 * schema is versioned so migrations can run across releases without losing
 * user customisations.
 */
import Store from 'electron-store';
import { homedir } from 'node:os';
import { join } from 'node:path';
import type { Preferences } from '../shared/types';

export type { Preferences };

function defaultExportDir(): string {
  return join(homedir(), 'Downloads', 'PurpleSpace');
}
function defaultBackupPath(): string {
  return join(homedir(), 'Downloads', 'Purple Space backup');
}

const DEFAULTS: Preferences = {
  version: 1,
  theme: 'system',
  exportDir: defaultExportDir(),
  autoBackupEnabled: true,
  backupPath: defaultBackupPath(),
  backupRetentionDays: 14,
  lastBackupMs: 0,
  windowWidth: 1380,
  windowHeight: 900,
  sidebarWidth: 248,
  lastPageId: ''
};

let store: Store<Preferences> | null = null;
function getStore(): Store<Preferences> {
  if (!store) {
    store = new Store<Preferences>({ name: 'purple-space-prefs', defaults: DEFAULTS });
    migrate(store);
  }
  return store;
}

function migrate(s: Store<Preferences>): void {
  const v = s.get('version', 0);
  if (v < 1) {
    for (const [k, val] of Object.entries(DEFAULTS)) {
      if (k === 'version') continue;
      s.set(k as keyof Preferences, s.get(k as keyof Preferences, val as never) ?? (val as never));
    }
    s.set('version', 1);
  }
}

export function getPreferences(): Preferences {
  const s = getStore();
  const out = {} as Record<string, unknown>;
  for (const [k, val] of Object.entries(DEFAULTS)) {
    out[k] = s.get(k as keyof Preferences, val as never);
  }
  return out as unknown as Preferences;
}

/** Merge-set: only provided keys are overwritten (version is migration-managed). */
export function setPreferences(patch: Partial<Preferences>): Preferences {
  const s = getStore();
  for (const [k, v] of Object.entries(patch)) {
    if (k === 'version') continue;
    s.set(k as keyof Preferences, v as never);
  }
  return getPreferences();
}

export function resetPreferences(): Preferences {
  const s = getStore();
  for (const [k, v] of Object.entries(DEFAULTS)) {
    s.set(k as keyof Preferences, v as never);
  }
  return getPreferences();
}
