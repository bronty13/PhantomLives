import { contextBridge, ipcRenderer, type IpcRendererEvent } from 'electron';
import type {
  ScanOptions,
  ScanProgress,
  ScanStats,
  SortSpec,
  FileFilter,
  NodeRow,
  RectNode,
  ResolvedCachePreset,
  DeleteResult,
  BackupInfo,
  SnapshotInfo,
  ExportFormat,
  DuplicateScanResult,
  DuplicateProgress
} from '../shared/types';

interface Prefs {
  version: number;
  scanOptions: ScanOptions;
  sizeMetric: 'alloc' | 'logical';
  permanentDeleteEnabled: boolean;
  exportDir: string;
  autoBackupEnabled: boolean;
  backupPath: string;
  backupRetentionDays: number;
  lastBackupMs: number;
  lastScanRoot: string;
  windowWidth: number;
  windowHeight: number;
}

type Unsub = () => void;
function on<T>(channel: string, cb: (payload: T) => void): Unsub {
  const h = (_e: IpcRendererEvent, payload: T): void => cb(payload);
  ipcRenderer.on(channel, h);
  return () => ipcRenderer.removeListener(channel, h);
}

const api = {
  ping: (): Promise<{ pong: boolean; version: string; platform: string; electron: string; osUser: string }> =>
    ipcRenderer.invoke('purpletree:ping'),

  pickDirectory: (): Promise<string | null> => ipcRenderer.invoke('purpletree:pick-directory'),
  autoscanPath: (): Promise<string | null> => ipcRenderer.invoke('purpletree:autoscan-path'),

  // Scan
  startScan: (rootPath: string, opts: ScanOptions): Promise<string> =>
    ipcRenderer.invoke('purpletree:scan-start', rootPath, opts),
  cancelScan: (scanId: string): Promise<void> => ipcRenderer.invoke('purpletree:scan-cancel', scanId),

  getChildren: (
    scanId: string,
    nodeId: number,
    sort: SortSpec,
    limit: number,
    offset: number
  ): Promise<NodeRow[]> =>
    ipcRenderer.invoke('purpletree:get-children', scanId, nodeId, sort, limit, offset),
  getTopFiles: (scanId: string, n: number, filter?: FileFilter): Promise<NodeRow[]> =>
    ipcRenderer.invoke('purpletree:get-top-files', scanId, n, filter),
  getBreadcrumb: (scanId: string, nodeId: number): Promise<NodeRow[]> =>
    ipcRenderer.invoke('purpletree:get-breadcrumb', scanId, nodeId),
  getTreemap: (
    scanId: string,
    focusId: number,
    width: number,
    height: number,
    depth?: number
  ): Promise<RectNode[]> =>
    ipcRenderer.invoke('purpletree:get-treemap', scanId, focusId, width, height, depth),
  getSummary: (scanId: string): Promise<{ stats: ScanStats; rootRow: NodeRow } | null> =>
    ipcRenderer.invoke('purpletree:get-summary', scanId),
  getRoot: (scanId: string): Promise<NodeRow | null> => ipcRenderer.invoke('purpletree:get-root', scanId),
  setSizeMetric: (metric: 'alloc' | 'logical'): Promise<void> =>
    ipcRenderer.invoke('purpletree:set-size-metric', metric),

  // Duplicates
  findDuplicates: (scanId: string): Promise<boolean> => ipcRenderer.invoke('purpletree:dup-find', scanId),
  cancelDuplicates: (scanId: string): Promise<void> => ipcRenderer.invoke('purpletree:dup-cancel', scanId),

  // Delete
  trash: (paths: string[]): Promise<DeleteResult> => ipcRenderer.invoke('purpletree:delete-trash', paths),
  permanentDelete: (paths: string[]): Promise<DeleteResult> =>
    ipcRenderer.invoke('purpletree:delete-permanent', paths),
  reveal: (path: string): Promise<void> => ipcRenderer.invoke('purpletree:reveal', path),
  openPath: (path: string): Promise<string> => ipcRenderer.invoke('purpletree:open-path', path),

  // Cache cleanup
  scanCachePresets: (): Promise<ResolvedCachePreset[]> => ipcRenderer.invoke('purpletree:cache-scan'),
  cleanCache: (paths: string[]): Promise<DeleteResult> => ipcRenderer.invoke('purpletree:cache-clean', paths),

  // Export
  exportReport: (scanId: string, format: ExportFormat): Promise<string | null> =>
    ipcRenderer.invoke('purpletree:export', scanId, format),

  // Preferences
  prefsGet: (): Promise<Prefs> => ipcRenderer.invoke('purpletree:prefs-get'),
  prefsSet: (patch: Partial<Prefs>): Promise<Prefs> => ipcRenderer.invoke('purpletree:prefs-set', patch),
  prefsReset: (): Promise<Prefs> => ipcRenderer.invoke('purpletree:prefs-reset'),

  // Backup
  backupList: (): Promise<BackupInfo[]> => ipcRenderer.invoke('purpletree:backup-list'),
  backupRun: (): Promise<{ ok: boolean; skipped?: boolean; info?: BackupInfo; error?: string }> =>
    ipcRenderer.invoke('purpletree:backup-run'),
  backupTest: (path: string): Promise<{ ok: boolean; fileCount: number; hasPrefs: boolean; error?: string }> =>
    ipcRenderer.invoke('purpletree:backup-test', path),
  backupRestore: (path: string): Promise<{ ok: boolean; error?: string }> =>
    ipcRenderer.invoke('purpletree:backup-restore', path),
  backupReveal: (): Promise<string> => ipcRenderer.invoke('purpletree:backup-reveal'),
  backupPickDir: (): Promise<string | null> => ipcRenderer.invoke('purpletree:backup-pick-dir'),

  // Snapshots
  snapshotList: (): Promise<SnapshotInfo[]> => ipcRenderer.invoke('purpletree:snapshot-list'),
  snapshotSave: (scanId: string): Promise<boolean> => ipcRenderer.invoke('purpletree:snapshot-save', scanId),
  snapshotLoad: (scanId: string): Promise<{ scanId: string } | null> =>
    ipcRenderer.invoke('purpletree:snapshot-load', scanId),

  // Events (main -> renderer)
  onScanProgress: (cb: (p: ScanProgress) => void): Unsub => on('purpletree:scan-progress', cb),
  onScanComplete: (cb: (s: ScanStats) => void): Unsub => on('purpletree:scan-complete', cb),
  onScanError: (cb: (e: { scanId: string; message: string }) => void): Unsub =>
    on('purpletree:scan-error', cb),
  onScanCancelled: (cb: (e: { scanId: string }) => void): Unsub =>
    on('purpletree:scan-cancelled', cb),
  onDupProgress: (cb: (e: { scanId: string; progress: DuplicateProgress }) => void): Unsub =>
    on('purpletree:dup-progress', cb),
  onDupDone: (cb: (e: { scanId: string; result: DuplicateScanResult }) => void): Unsub =>
    on('purpletree:dup-done', cb),
  onDupError: (cb: (e: { scanId: string; message: string }) => void): Unsub =>
    on('purpletree:dup-error', cb),

  // Menu events
  onMenu: (cb: (action: string) => void): Unsub => {
    const unsubs = [
      on('purpletree:menu-open-folder', () => cb('open-folder')),
      on('purpletree:menu-export', () => cb('export')),
      on('purpletree:menu-settings', () => cb('settings')),
      on('purpletree:menu-toggle-sidebar', () => cb('toggle-sidebar'))
    ];
    return () => unsubs.forEach((u) => u());
  }
};

contextBridge.exposeInMainWorld('purpleTree', api);
export type PurpleTreeApi = typeof api;
