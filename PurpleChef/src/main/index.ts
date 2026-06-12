/**
 * @file index.ts — Electron main process: window, IPC, launch-time backup.
 */
import { app, BrowserWindow, dialog, ipcMain, shell } from 'electron';
import { join } from 'node:path';
import { electronApp, optimizer, is } from '@electron-toolkit/utils';
import {
  listBackups,
  restoreBackup,
  runBackup,
  runOnLaunch,
  testBackup
} from './backup';
import { DEFAULT_PREFS, getPreferences, getSave, recordResult, setPreferences } from './store';
import type { MatchResult, Preferences } from '../shared/types';

function createWindow(): void {
  const prefs = getPreferences();
  const win = new BrowserWindow({
    width: prefs.windowWidth,
    height: prefs.windowHeight,
    minWidth: 1180,
    minHeight: 760,
    show: false,
    title: 'Purple Chef',
    backgroundColor: '#241b3a',
    autoHideMenuBar: true,
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      sandbox: false
    }
  });

  win.on('ready-to-show', () => win.show());
  win.on('resized', () => {
    const [w, h] = win.getSize();
    setPreferences({ windowWidth: w, windowHeight: h });
  });
  win.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });

  if (is.dev && process.env.ELECTRON_RENDERER_URL) {
    win.loadURL(process.env.ELECTRON_RENDERER_URL);
  } else {
    win.loadFile(join(__dirname, '../renderer/index.html'));
  }
}

app.whenReady().then(() => {
  electronApp.setAppUserModelId('com.bronty13.purplechef');
  app.on('browser-window-created', (_, window) => optimizer.watchWindowShortcuts(window));

  // ----- IPC -----
  ipcMain.handle('app:version', () => app.getVersion());
  ipcMain.handle('prefs:get', () => getPreferences());
  ipcMain.handle('prefs:defaults', () => DEFAULT_PREFS);
  ipcMain.handle('prefs:set', (_e, patch: Partial<Preferences>) => setPreferences(patch));
  ipcMain.handle('save:get', () => getSave());
  ipcMain.handle('save:record', (_e, result: MatchResult) => recordResult(result));

  ipcMain.handle('backup:run', () => runBackup(true));
  ipcMain.handle('backup:list', () => listBackups());
  ipcMain.handle('backup:test', (_e, path: string) => testBackup(path));
  ipcMain.handle('backup:restore', (_e, path: string) => restoreBackup(path));
  ipcMain.handle('backup:reveal', async () => {
    const { backupPath } = getPreferences();
    await shell.openPath(backupPath);
  });
  ipcMain.handle('backup:revealFile', (_e, path: string) => shell.showItemInFolder(path));
  ipcMain.handle('backup:chooseDir', async () => {
    const res = await dialog.showOpenDialog({
      properties: ['openDirectory', 'createDirectory'],
      defaultPath: getPreferences().backupPath
    });
    if (res.canceled || res.filePaths.length === 0) return null;
    return setPreferences({ backupPath: res.filePaths[0] });
  });

  createWindow();

  // Launch-time auto-backup (debounced; never blocks the window).
  runOnLaunch();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  app.quit();
});
