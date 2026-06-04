import {
  app,
  BrowserWindow,
  dialog,
  ipcMain,
  Menu,
  shell,
  type MenuItemConstructorOptions
} from 'electron';
import { writeFile, mkdir, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { userInfo } from 'node:os';
import { electronApp, optimizer, is } from '@electron-toolkit/utils';
import { checkForUpdates, scheduleStartupCheck } from './updater';
import { getPreferences, setPreferences, resetPreferences, type Preferences } from './prefs';
import * as controller from './scan/scanController';
import { trashPaths, permanentDelete } from './safety/deleteService';
import { scanCachePresets } from './cache/cacheScan';
import { serializeReport, type ReportMeta } from './export/report';
import {
  runOnLaunch,
  runBackup,
  listBackups,
  testBackup,
  restoreBackup
} from './backup/backupService';
import { listSnapshots } from './scan/snapshot';
import type { ScanOptions, SortSpec, FileFilter, ExportFormat } from '../shared/types';

// Electron derives app.getName() from package.json's top-level `name`
// ("purple-tree") when no top-level `productName` is present — which would
// show "About purple-tree" etc. in the macOS app menu. Pin the display name to
// match the bundle/title/About box.
app.setName('Purple Tree');

let mainWindow: BrowserWindow | null = null;

function sendToRenderer(channel: string, payload: unknown): void {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send(channel, payload);
  }
}

function createMainWindow(): BrowserWindow {
  const prefs = getPreferences();
  const win = new BrowserWindow({
    width: prefs.windowWidth,
    height: prefs.windowHeight,
    minWidth: 960,
    minHeight: 600,
    show: false,
    autoHideMenuBar: false,
    title: 'Purple Tree',
    backgroundColor: '#1a0b2e',
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      sandbox: false,
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  win.on('ready-to-show', () => win.show());
  // Remember the window size between launches (size only — not position, to
  // avoid restoring off-screen when displays change).
  win.on('close', () => {
    if (win.isDestroyed()) return;
    const [w, h] = win.getSize();
    setPreferences({ windowWidth: w, windowHeight: h });
  });
  win.webContents.setWindowOpenHandler((details) => {
    void shell.openExternal(details.url);
    return { action: 'deny' };
  });

  if (is.dev && process.env['ELECTRON_RENDERER_URL']) {
    win.loadURL(process.env['ELECTRON_RENDERER_URL']);
  } else {
    win.loadFile(join(__dirname, '../renderer/index.html'));
  }
  return win;
}

async function pickDirectory(): Promise<string | null> {
  if (!mainWindow) return null;
  const last = getPreferences().lastScanRoot;
  const r = await dialog.showOpenDialog(mainWindow, {
    title: 'Choose a folder to scan',
    properties: ['openDirectory', 'createDirectory'],
    ...(last ? { defaultPath: last } : {})
  });
  if (r.canceled || r.filePaths.length === 0) return null;
  return r.filePaths[0];
}

function buildMenu(): void {
  const isMac = process.platform === 'darwin';
  const template: MenuItemConstructorOptions[] = [
    ...(isMac
      ? ([
          {
            label: app.name,
            submenu: [
              { role: 'about' },
              { type: 'separator' },
              { role: 'services' },
              { type: 'separator' },
              { role: 'hide' },
              { role: 'hideOthers' },
              { role: 'unhide' },
              { type: 'separator' },
              { role: 'quit' }
            ]
          }
        ] as MenuItemConstructorOptions[])
      : []),
    {
      label: 'File',
      submenu: [
        {
          label: 'Open Folder…',
          accelerator: 'CmdOrCtrl+O',
          click: () => sendToRenderer('purpletree:menu-open-folder', null)
        },
        {
          label: 'Export Report…',
          accelerator: 'CmdOrCtrl+E',
          click: () => sendToRenderer('purpletree:menu-export', null)
        },
        { type: 'separator' },
        {
          label: process.platform === 'darwin' ? 'Settings…' : 'Settings…',
          accelerator: 'CmdOrCtrl+,',
          click: () => sendToRenderer('purpletree:menu-settings', null)
        },
        { type: 'separator' },
        isMac ? { role: 'close' } : { role: 'quit' }
      ]
    },
    {
      label: 'Edit',
      submenu: [{ role: 'cut' }, { role: 'copy' }, { role: 'paste' }]
    },
    {
      label: 'View',
      submenu: [
        {
          label: 'Toggle Sidebar',
          accelerator: 'CmdOrCtrl+Ctrl+S',
          click: () => sendToRenderer('purpletree:menu-toggle-sidebar', null)
        },
        { type: 'separator' },
        { role: 'reload' },
        { role: 'toggleDevTools' },
        { type: 'separator' },
        { role: 'togglefullscreen' }
      ]
    },
    { role: 'windowMenu' },
    {
      role: 'help',
      submenu: [
        {
          label: 'Purple Tree User Manual',
          click: () =>
            void shell.openExternal(
              'https://github.com/bronty13/PhantomLives/blob/main/PurpleTree/docs/USER_MANUAL.md'
            )
        },
        {
          label: 'Check for Updates…',
          click: () => void checkForUpdates(mainWindow, true)
        },
        {
          label: 'Report an Issue…',
          click: () => void shell.openExternal('https://github.com/bronty13/PhantomLives/issues/new')
        },
        { type: 'separator' },
        { label: 'About Purple Tree', click: () => showAboutDialog() }
      ]
    }
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

function showAboutDialog(): void {
  if (!mainWindow) return;
  void dialog.showMessageBox(mainWindow, {
    type: 'info',
    message: 'Purple Tree',
    detail:
      `Version ${app.getVersion()}\n` +
      `Electron ${process.versions.electron} • Node ${process.versions.node}\n` +
      `Platform ${process.platform} (${process.arch})\n\n` +
      'A cross-platform disk-space analyzer and file-cleanup utility.\n' +
      '© Robert Olen. Licensed for personal use.',
    buttons: ['OK']
  });
}

function registerIpc(): void {
  ipcMain.handle('purpletree:ping', () => {
    let osUser = '';
    try {
      osUser = userInfo().username || '';
    } catch {
      osUser = '';
    }
    return {
      pong: true,
      version: app.getVersion(),
      platform: process.platform,
      electron: process.versions.electron,
      osUser
    };
  });

  ipcMain.handle('purpletree:pick-directory', () => pickDirectory());

  // Debug-only: lets the renderer auto-start a scan of $PT_AUTOSCAN on launch
  // (bypasses the folder picker) so the full GUI pipeline can be reproduced
  // headlessly. Returns null in normal use.
  ipcMain.handle('purpletree:autoscan-path', () => process.env.PT_AUTOSCAN ?? null);

  // ----- Scan -----
  ipcMain.handle('purpletree:scan-start', (_e, rootPath: string, opts: ScanOptions) => {
    setPreferences({ lastScanRoot: rootPath });
    return controller.startScan(rootPath, opts);
  });
  ipcMain.handle('purpletree:scan-cancel', (_e, scanId: string) => controller.cancelScan(scanId));

  ipcMain.handle(
    'purpletree:get-children',
    (_e, scanId: string, nodeId: number, sort: SortSpec, limit: number, offset: number) =>
      controller.getChildren(scanId, nodeId, sort, limit, offset)
  );
  ipcMain.handle('purpletree:get-top-files', (_e, scanId: string, n: number, filter?: FileFilter) =>
    controller.getTopFiles(scanId, n, filter)
  );
  ipcMain.handle('purpletree:get-breadcrumb', (_e, scanId: string, nodeId: number) =>
    controller.getBreadcrumb(scanId, nodeId)
  );
  ipcMain.handle(
    'purpletree:get-treemap',
    (_e, scanId: string, focusId: number, w: number, h: number, depth?: number) =>
      controller.getTreemap(scanId, focusId, w, h, depth)
  );
  ipcMain.handle(
    'purpletree:get-sunburst',
    (_e, scanId: string, focusId: number, depth?: number) =>
      controller.getSunburst(scanId, focusId, depth)
  );
  ipcMain.handle('purpletree:get-summary', (_e, scanId: string) => controller.getSummary(scanId));
  ipcMain.handle('purpletree:get-root', (_e, scanId: string) => controller.getRoot(scanId));

  ipcMain.handle('purpletree:set-size-metric', (_e, metric: 'alloc' | 'logical') => {
    setPreferences({ sizeMetric: metric });
    controller.setSizeMetric(metric);
  });

  // ----- Duplicates -----
  ipcMain.handle('purpletree:dup-find', (_e, scanId: string) => controller.findDuplicates(scanId));
  ipcMain.handle('purpletree:dup-cancel', (_e, scanId: string) =>
    controller.cancelDuplicates(scanId)
  );

  // ----- Delete -----
  ipcMain.handle('purpletree:delete-trash', (_e, paths: string[]) => {
    const { backupPath } = getPreferences();
    return trashPaths(paths, backupPath);
  });
  ipcMain.handle('purpletree:delete-permanent', (_e, paths: string[]) => {
    const prefs = getPreferences();
    if (!prefs.permanentDeleteEnabled) {
      return {
        ok: false,
        removed: [],
        failed: paths.map((p) => ({ path: p, reason: 'Permanent delete is disabled in Settings' }))
      };
    }
    return permanentDelete(paths, prefs.backupPath);
  });

  ipcMain.handle('purpletree:reveal', (_e, p: string) => {
    shell.showItemInFolder(p);
  });
  ipcMain.handle('purpletree:open-path', (_e, p: string) => shell.openPath(p));

  // ----- Cache cleanup -----
  ipcMain.handle('purpletree:cache-scan', () => scanCachePresets());
  ipcMain.handle('purpletree:cache-clean', async (_e, paths: string[]) => {
    // Trash the *contents* of cache directories (and any direct file paths),
    // so the parent cache folder itself survives. Always trash, never
    // permanent — even if the global permanent-delete toggle is on.
    const targets: string[] = [];
    for (const p of paths) {
      try {
        const entries = await readdir(p, { withFileTypes: true });
        for (const e of entries) targets.push(join(p, e.name));
      } catch {
        targets.push(p); // not a directory (or unreadable) — trash as-is
      }
    }
    const { backupPath } = getPreferences();
    return trashPaths(targets, backupPath);
  });

  // ----- Export -----
  ipcMain.handle(
    'purpletree:export',
    async (_e, scanId: string, format: ExportFormat): Promise<string | null> => {
      if (!mainWindow) return null;
      const summary = controller.getSummary(scanId);
      if (!summary) return null;
      const prefs = getPreferences();
      await mkdir(prefs.exportDir, { recursive: true }).catch(() => undefined);
      const safeRoot = summary.stats.rootPath.replace(/[^A-Za-z0-9._-]+/g, '_').slice(-40);
      const defaultPath = join(prefs.exportDir, `purpletree-${safeRoot}.${format}`);
      const save = await dialog.showSaveDialog(mainWindow, {
        title: 'Export Report',
        defaultPath,
        filters: [{ name: format.toUpperCase(), extensions: [format] }]
      });
      if (save.canceled || !save.filePath) return null;
      const rows = controller.getExportRows(scanId);
      const meta: ReportMeta = {
        rootPath: summary.stats.rootPath,
        generatedMs: Date.now(),
        totalBytes: summary.stats.totalBytes,
        totalFiles: summary.stats.totalFiles
      };
      await writeFile(save.filePath, serializeReport(rows, meta, format), 'utf8');
      return save.filePath;
    }
  );

  // ----- Preferences -----
  ipcMain.handle('purpletree:prefs-get', (): Preferences => getPreferences());
  ipcMain.handle('purpletree:prefs-set', (_e, patch: Partial<Preferences>) => setPreferences(patch));
  ipcMain.handle('purpletree:prefs-reset', () => resetPreferences());

  // ----- Backup -----
  ipcMain.handle('purpletree:backup-list', () => listBackups());
  ipcMain.handle('purpletree:backup-run', () => runBackup(true));
  ipcMain.handle('purpletree:backup-test', (_e, p: string) => testBackup(p));
  ipcMain.handle('purpletree:backup-restore', (_e, p: string) => restoreBackup(p));
  ipcMain.handle('purpletree:backup-reveal', () => shell.openPath(getPreferences().backupPath));
  ipcMain.handle('purpletree:backup-pick-dir', async (): Promise<string | null> => {
    if (!mainWindow) return null;
    const r = await dialog.showOpenDialog(mainWindow, {
      title: 'Choose a backup folder',
      properties: ['openDirectory', 'createDirectory']
    });
    if (r.canceled || r.filePaths.length === 0) return null;
    return r.filePaths[0];
  });

  // ----- Snapshots -----
  ipcMain.handle('purpletree:snapshot-list', () => listSnapshots());
  ipcMain.handle('purpletree:snapshot-save', (_e, scanId: string) => controller.saveSnapshot(scanId));
  ipcMain.handle('purpletree:snapshot-load', (_e, scanId: string) => controller.loadSnapshot(scanId));
}

app.whenReady().then(() => {
  electronApp.setAppUserModelId('com.bronty13.purpletree');
  controller.initController(sendToRenderer, getPreferences().sizeMetric);

  app.on('browser-window-created', (_, window) => {
    optimizer.watchWindowShortcuts(window);
  });

  registerIpc();
  buildMenu();
  mainWindow = createMainWindow();
  scheduleStartupCheck(() => mainWindow);

  // Launch-time auto-backup (debounced, never throws).
  void runOnLaunch();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      mainWindow = createMainWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
