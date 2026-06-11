/**
 * @file types.ts — dependency-free DTOs shared between main, preload, renderer.
 */

export interface BackupInfo {
  name: string;
  path: string;
  sizeBytes: number;
  createdMs: number;
}

export interface BackupRunResult {
  ok: boolean;
  skipped?: boolean;
  info?: BackupInfo;
  error?: string;
}

export interface BackupTestResult {
  ok: boolean;
  fileCount: number;
  hasPrefs: boolean;
  error?: string;
}

/** Status of the embedded Convex backend, reported to the renderer. */
export interface BackendStatus {
  state: 'starting' | 'ready' | 'error';
  /** Client URL the renderer's ConvexReactClient should connect to. */
  url: string;
  /** Site URL (HTTP actions / file serving). */
  siteUrl: string;
  error?: string;
}

export type ThemeSetting = 'system' | 'light' | 'dark';

/** Per-install user preferences (persisted by the main process). */
export interface Preferences {
  /** Bumped whenever the schema changes; migrations run on load. */
  version: number;
  theme: ThemeSetting;
  /** Default directory for Markdown exports. */
  exportDir: string;
  // ----- Backup standard -----
  autoBackupEnabled: boolean;
  backupPath: string;
  backupRetentionDays: number;
  /** ms epoch of the last successful backup (debounce + UI readout). */
  lastBackupMs: number;
  // ----- UX state -----
  windowWidth: number;
  windowHeight: number;
  sidebarWidth: number;
  lastPageId: string;
}
