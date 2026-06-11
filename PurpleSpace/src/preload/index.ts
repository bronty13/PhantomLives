import { contextBridge, ipcRenderer } from 'electron';
import type {
  BackendStatus,
  BackupInfo,
  BackupRunResult,
  BackupTestResult,
  Preferences
} from '../shared/types';

type Unsub = () => void;

const api = {
  ping: (): Promise<{ pong: true; version: string }> => ipcRenderer.invoke('ps:ping'),

  // Embedded Convex backend lifecycle
  getBackendStatus: (): Promise<BackendStatus> => ipcRenderer.invoke('ps:backend-status'),
  onBackendStatus: (cb: (s: BackendStatus) => void): Unsub => {
    const fn = (_e: unknown, s: BackendStatus): void => cb(s);
    ipcRenderer.on('ps:backend-status', fn);
    return () => ipcRenderer.removeListener('ps:backend-status', fn);
  },

  // Preferences
  prefsGet: (): Promise<Preferences> => ipcRenderer.invoke('ps:prefs-get'),
  prefsSet: (patch: Partial<Preferences>): Promise<Preferences> =>
    ipcRenderer.invoke('ps:prefs-set', patch),
  prefsReset: (): Promise<Preferences> => ipcRenderer.invoke('ps:prefs-reset'),

  // Backup standard
  backupList: (): Promise<BackupInfo[]> => ipcRenderer.invoke('ps:backup-list'),
  backupRun: (): Promise<BackupRunResult> => ipcRenderer.invoke('ps:backup-run'),
  backupTest: (path: string): Promise<BackupTestResult> => ipcRenderer.invoke('ps:backup-test', path),
  backupRestore: (path: string): Promise<BackupRunResult> =>
    ipcRenderer.invoke('ps:backup-restore', path),
  backupReveal: (): Promise<string> => ipcRenderer.invoke('ps:backup-reveal'),
  backupPickDir: (): Promise<string | null> => ipcRenderer.invoke('ps:backup-pick-dir'),
  backupPickZip: (): Promise<string | null> => ipcRenderer.invoke('ps:backup-pick-zip'),

  // Markdown export → ~/Downloads/PurpleSpace/ (repo default-output rule)
  exportMarkdown: (title: string, markdown: string): Promise<string | null> =>
    ipcRenderer.invoke('ps:export-markdown', title, markdown),

  openExternal: (url: string): Promise<void> => ipcRenderer.invoke('ps:open-external', url),

  // Native menu events (File → New Page, View → Toggle Dark Mode, …)
  onMenu: (cb: (action: string) => void): Unsub => {
    const fn = (_e: unknown, action: string): void => cb(action);
    ipcRenderer.on('ps:menu', fn);
    return () => ipcRenderer.removeListener('ps:menu', fn);
  }
};

contextBridge.exposeInMainWorld('purpleSpace', api);

export type PurpleSpaceApi = typeof api;
