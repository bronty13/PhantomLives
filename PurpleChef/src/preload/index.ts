/**
 * @file preload/index.ts — typed IPC bridge exposed as window.purpleChef.
 */
import { contextBridge, ipcRenderer } from 'electron';
import type { BackupInfo, MatchResult, Preferences, SaveData } from '../shared/types';

export interface PurpleChefApi {
  version: () => Promise<string>;
  getPrefs: () => Promise<Preferences>;
  getDefaultPrefs: () => Promise<Preferences>;
  setPrefs: (patch: Partial<Preferences>) => Promise<Preferences>;
  getSave: () => Promise<SaveData>;
  recordResult: (result: MatchResult) => Promise<{ save: SaveData; newTrophyIds: string[] }>;
  backup: {
    run: () => Promise<{ ok: boolean; skipped?: boolean; error?: string }>;
    list: () => Promise<BackupInfo[]>;
    test: (path: string) => Promise<{ ok: boolean; fileCount: number; hasSave: boolean; error?: string }>;
    restore: (path: string) => Promise<{ ok: boolean; error?: string }>;
    reveal: () => Promise<void>;
    revealFile: (path: string) => Promise<void>;
    chooseDir: () => Promise<Preferences | null>;
  };
}

const api: PurpleChefApi = {
  version: () => ipcRenderer.invoke('app:version'),
  getPrefs: () => ipcRenderer.invoke('prefs:get'),
  getDefaultPrefs: () => ipcRenderer.invoke('prefs:defaults'),
  setPrefs: (patch) => ipcRenderer.invoke('prefs:set', patch),
  getSave: () => ipcRenderer.invoke('save:get'),
  recordResult: (result) => ipcRenderer.invoke('save:record', result),
  backup: {
    run: () => ipcRenderer.invoke('backup:run'),
    list: () => ipcRenderer.invoke('backup:list'),
    test: (path) => ipcRenderer.invoke('backup:test', path),
    restore: (path) => ipcRenderer.invoke('backup:restore', path),
    reveal: () => ipcRenderer.invoke('backup:reveal'),
    revealFile: (path) => ipcRenderer.invoke('backup:revealFile', path),
    chooseDir: () => ipcRenderer.invoke('backup:chooseDir')
  }
};

contextBridge.exposeInMainWorld('purpleChef', api);
