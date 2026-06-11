/**
 * @file index.ts — Purple Space main process.
 *
 * Launch order matters:
 *   1. auto-backup (zips App Support while the Convex SQLite is quiescent)
 *   2. start the embedded Convex backend
 *   3. open the window (renderer waits for backend-ready status)
 */
import { app, BrowserWindow, Menu, dialog, ipcMain, shell, nativeTheme } from 'electron';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { mkdir, writeFile } from 'node:fs/promises';
import { is } from '@electron-toolkit/utils';
import { getPreferences, setPreferences, resetPreferences, type Preferences } from './prefs';
import {
  runOnLaunch,
  runBackup,
  listBackups,
  testBackup,
  restoreBackup
} from './backup/backupService';
import { startBackend, stopBackend, getStatus, onStatusChange } from './convexBackend';

app.setName('Purple Space');

let mainWindow: BrowserWindow | null = null;

function createWindow(): void {
  const prefs = getPreferences();
  mainWindow = new BrowserWindow({
    width: prefs.windowWidth,
    height: prefs.windowHeight,
    minWidth: 880,
    minHeight: 560,
    show: false,
    title: 'Purple Space',
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 14, y: 18 },
    backgroundColor: nativeTheme.shouldUseDarkColors ? '#191621' : '#FAF8F3',
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  mainWindow.on('ready-to-show', () => mainWindow?.show());
  mainWindow.on('resized', () => {
    if (!mainWindow) return;
    const [width, height] = mainWindow.getSize();
    setPreferences({ windowWidth: width, windowHeight: height });
  });
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    void shell.openExternal(url);
    return { action: 'deny' };
  });

  if (is.dev && process.env.ELECTRON_RENDERER_URL) {
    void mainWindow.loadURL(process.env.ELECTRON_RENDERER_URL);
  } else {
    void mainWindow.loadFile(join(__dirname, '../renderer/index.html'));
  }
}

function sendMenu(action: string): void {
  mainWindow?.webContents.send('ps:menu', action);
}

function buildMenu(): void {
  const menu = Menu.buildFromTemplate([
    {
      label: 'Purple Space',
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        {
          label: 'Settings…',
          accelerator: 'Cmd+,',
          click: () => sendMenu('settings')
        },
        { type: 'separator' },
        { role: 'hide' },
        { role: 'hideOthers' },
        { role: 'unhide' },
        { type: 'separator' },
        { role: 'quit' }
      ]
    },
    {
      label: 'File',
      submenu: [
        { label: 'New Page', accelerator: 'Cmd+N', click: () => sendMenu('new-page') },
        { label: 'New Database', accelerator: 'Cmd+Shift+N', click: () => sendMenu('new-database') },
        { type: 'separator' },
        { label: 'Export Page as Markdown…', accelerator: 'Cmd+E', click: () => sendMenu('export-markdown') },
        { type: 'separator' },
        { role: 'close' }
      ]
    },
    { role: 'editMenu' },
    {
      label: 'View',
      submenu: [
        { label: 'Quick Switcher…', accelerator: 'Cmd+P', click: () => sendMenu('quick-switcher') },
        { type: 'separator' },
        { label: 'Toggle Dark Mode', accelerator: 'Cmd+Shift+L', click: () => sendMenu('toggle-theme') },
        { type: 'separator' },
        { role: 'reload' },
        { role: 'toggleDevTools' },
        { type: 'separator' },
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' }
      ]
    },
    { role: 'windowMenu' }
  ]);
  Menu.setApplicationMenu(menu);
}

function registerIpc(): void {
  ipcMain.handle('ps:ping', () => ({ pong: true as const, version: app.getVersion() }));

  ipcMain.handle('ps:backend-status', () => getStatus());

  ipcMain.handle('ps:prefs-get', () => getPreferences());
  ipcMain.handle('ps:prefs-set', (_e, patch: Partial<Preferences>) => setPreferences(patch));
  ipcMain.handle('ps:prefs-reset', () => resetPreferences());

  ipcMain.handle('ps:backup-list', () => listBackups());
  ipcMain.handle('ps:backup-run', () => runBackup(true));
  ipcMain.handle('ps:backup-test', (_e, p: string) => testBackup(p));
  ipcMain.handle('ps:backup-restore', async (_e, p: string) => {
    // The backend must not be writing the SQLite file while we swap it out.
    stopBackend();
    const result = await restoreBackup(p);
    if (result.ok) {
      app.relaunch();
      app.exit(0);
    } else {
      void startBackend();
    }
    return result;
  });
  ipcMain.handle('ps:backup-reveal', async () => {
    const { backupPath } = getPreferences();
    await mkdir(backupPath, { recursive: true });
    return shell.openPath(backupPath);
  });
  ipcMain.handle('ps:backup-pick-dir', async () => {
    if (!mainWindow) return null;
    const res = await dialog.showOpenDialog(mainWindow, {
      properties: ['openDirectory', 'createDirectory']
    });
    return res.canceled || !res.filePaths.length ? null : res.filePaths[0];
  });
  ipcMain.handle('ps:backup-pick-zip', async () => {
    if (!mainWindow) return null;
    const res = await dialog.showOpenDialog(mainWindow, {
      properties: ['openFile'],
      filters: [{ name: 'Backup archive', extensions: ['zip'] }],
      defaultPath: getPreferences().backupPath
    });
    return res.canceled || !res.filePaths.length ? null : res.filePaths[0];
  });

  ipcMain.handle('ps:export-markdown', async (_e, title: string, markdown: string) => {
    const dir = getPreferences().exportDir || join(homedir(), 'Downloads', 'PurpleSpace');
    await mkdir(dir, { recursive: true });
    const safe = (title.trim() || 'Untitled').replace(/[/\\:]+/g, '-').slice(0, 120);
    const path = join(dir, `${safe}.md`);
    await writeFile(path, markdown, 'utf8');
    return path;
  });

  ipcMain.handle('ps:open-external', (_e, url: string) => {
    if (/^https?:\/\//.test(url)) void shell.openExternal(url);
  });
}

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });

  app.whenReady().then(async () => {
    registerIpc();
    buildMenu();

    // 1. Backup first — the Convex SQLite file is still quiescent.
    await runOnLaunch();

    // 2. Backend up (async — renderer shows a splash until ready).
    onStatusChange((s) => mainWindow?.webContents.send('ps:backend-status', s));
    void startBackend();

    // 3. Window.
    createWindow();

    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow();
    });
  });

  app.on('window-all-closed', () => {
    app.quit();
  });

  app.on('will-quit', () => {
    stopBackend();
  });
}
