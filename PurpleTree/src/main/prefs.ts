/**
 * @file prefs.ts — per-install user preferences.
 *
 * Persists to `<userData>/purple-tree-prefs.json` via electron-store. The
 * schema is versioned so migrations can run across releases without losing
 * user customisations.
 */
import Store from 'electron-store';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { DEFAULT_SCAN_OPTIONS, type ScanOptions, type SizeMetric } from '../shared/types';

export interface Preferences {
  /** Bumped whenever the schema changes; migrations run on load. */
  version: number;
  /** Default options applied to new scans. */
  scanOptions: ScanOptions;
  /** Which size to display: on-disk allocated (default) or logical content. */
  sizeMetric: SizeMetric;
  /** Allow the guarded permanent-delete action (off = trash only). */
  permanentDeleteEnabled: boolean;
  /** Default directory for exported reports. */
  exportDir: string;
  // ----- Backup standard -----
  autoBackupEnabled: boolean;
  backupPath: string;
  backupRetentionDays: number;
  /** ms epoch of the last successful backup (debounce + UI readout). */
  lastBackupMs: number;
  // ----- UX state -----
  /** Last folder the user scanned (pre-fills the folder picker). */
  lastScanRoot: string;
  /** Main window size, restored on next launch. */
  windowWidth: number;
  windowHeight: number;
}

function defaultExportDir(): string {
  return join(homedir(), 'Downloads', 'Purple Tree');
}
function defaultBackupPath(): string {
  return join(homedir(), 'Downloads', 'Purple Tree backup');
}

const DEFAULTS: Preferences = {
  version: 3,
  scanOptions: { ...DEFAULT_SCAN_OPTIONS },
  sizeMetric: 'alloc',
  permanentDeleteEnabled: false,
  exportDir: defaultExportDir(),
  autoBackupEnabled: true,
  backupPath: defaultBackupPath(),
  backupRetentionDays: 14,
  lastBackupMs: 0,
  lastScanRoot: '',
  windowWidth: 1340,
  windowHeight: 860
};

let store: Store<Preferences> | null = null;
function getStore(): Store<Preferences> {
  if (!store) {
    store = new Store<Preferences>({ name: 'purple-tree-prefs', defaults: DEFAULTS });
    migrate(store);
  }
  return store;
}

function migrate(s: Store<Preferences>): void {
  const v = s.get('version', 0);
  if (v < 1) {
    s.set('scanOptions', s.get('scanOptions', DEFAULTS.scanOptions) ?? DEFAULTS.scanOptions);
    s.set('permanentDeleteEnabled', s.get('permanentDeleteEnabled', false) ?? false);
    s.set('exportDir', s.get('exportDir', DEFAULTS.exportDir) ?? DEFAULTS.exportDir);
    s.set('autoBackupEnabled', s.get('autoBackupEnabled', true) ?? true);
    s.set('backupPath', s.get('backupPath', DEFAULTS.backupPath) ?? DEFAULTS.backupPath);
    s.set('backupRetentionDays', s.get('backupRetentionDays', 14) ?? 14);
    s.set('lastBackupMs', s.get('lastBackupMs', 0) ?? 0);
    s.set('version', 1);
  }
  if (v < 2) {
    s.set('lastScanRoot', s.get('lastScanRoot', '') ?? '');
    s.set('windowWidth', s.get('windowWidth', DEFAULTS.windowWidth) ?? DEFAULTS.windowWidth);
    s.set('windowHeight', s.get('windowHeight', DEFAULTS.windowHeight) ?? DEFAULTS.windowHeight);
    s.set('version', 2);
  }
  if (v < 3) {
    s.set('sizeMetric', s.get('sizeMetric', DEFAULTS.sizeMetric) ?? DEFAULTS.sizeMetric);
    s.set('version', 3);
  }
}

export function getPreferences(): Preferences {
  const s = getStore();
  return {
    version: s.get('version', DEFAULTS.version),
    scanOptions: s.get('scanOptions', DEFAULTS.scanOptions),
    sizeMetric: s.get('sizeMetric', DEFAULTS.sizeMetric),
    permanentDeleteEnabled: s.get('permanentDeleteEnabled', DEFAULTS.permanentDeleteEnabled),
    exportDir: s.get('exportDir', DEFAULTS.exportDir),
    autoBackupEnabled: s.get('autoBackupEnabled', DEFAULTS.autoBackupEnabled),
    backupPath: s.get('backupPath', DEFAULTS.backupPath),
    backupRetentionDays: s.get('backupRetentionDays', DEFAULTS.backupRetentionDays),
    lastBackupMs: s.get('lastBackupMs', DEFAULTS.lastBackupMs),
    lastScanRoot: s.get('lastScanRoot', DEFAULTS.lastScanRoot),
    windowWidth: s.get('windowWidth', DEFAULTS.windowWidth),
    windowHeight: s.get('windowHeight', DEFAULTS.windowHeight)
  };
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
