import { app, BrowserWindow, dialog, ipcMain, Menu, shell, type MenuItemConstructorOptions } from 'electron';
import { readFile, writeFile } from 'node:fs/promises';
import { basename, extname, join } from 'node:path';
import { electronApp, optimizer, is } from '@electron-toolkit/utils';
import { addRecent, clearRecents, getRecents } from './recents';
import { installPdfService, isPdfServiceInstalled, pdfServicePath, captureDir } from './printer';
import { autosaveDir, writeAutosave, clearAutosave, listAutosaves } from './autosave';
import { registerAssetProtocolScheme, registerAssetProtocolHandler, readAsset, assetPath } from './assets';
import { detectQpdf, encryptWithQpdf, type QpdfPermissions } from './security';
import { convertToStandard, detectGhostscript, optimizePdf, type StandardTarget } from './standards';
import { combinePdfs, splitPdfPerPage, extractPages, parseRangeString } from './pdfops';
import { checkForUpdates, scheduleStartupCheck } from './updater';
import { crashReportsDir, startCrashReporter } from './crashreport';
import {
  convertViaLibreOffice,
  findLibreOffice,
  imagesToPdf,
  urlToPdf,
  writeTempPdf
} from './convert';
import { tmpdir } from 'node:os';

registerAssetProtocolScheme();

let mainWindow: BrowserWindow | null = null;

/** Add to recents AND rebuild the menu so the Open Recent submenu reflects it. */
function rememberRecent(path: string, name: string): void {
  addRecent(path, name);
  try {
    buildMenu();
  } catch {
    // buildMenu can throw during very early init before the function exists in scope
  }
}
function forgetRecents(): void {
  clearRecents();
  try {
    buildMenu();
  } catch {
    /* ignore */
  }
}

function createMainWindow(): BrowserWindow {
  const win = new BrowserWindow({
    width: 1280,
    height: 840,
    minWidth: 900,
    minHeight: 600,
    show: false,
    autoHideMenuBar: false,
    title: 'Purple PDF',
    backgroundColor: '#1a0b2e',
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      sandbox: false,
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  win.on('ready-to-show', () => win.show());

  win.webContents.setWindowOpenHandler((details) => {
    shell.openExternal(details.url);
    return { action: 'deny' };
  });

  if (is.dev && process.env['ELECTRON_RENDERER_URL']) {
    win.loadURL(process.env['ELECTRON_RENDERER_URL']);
  } else {
    win.loadFile(join(__dirname, '../renderer/index.html'));
  }

  return win;
}

function sendToRenderer<T>(channel: string, payload: T): void {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send(channel, payload);
  }
}

async function openFilesDialog(): Promise<void> {
  if (!mainWindow) return;
  const result = await dialog.showOpenDialog(mainWindow, {
    title: 'Open PDF',
    properties: ['openFile', 'multiSelections'],
    filters: [{ name: 'PDF Documents', extensions: ['pdf'] }]
  });
  if (result.canceled) return;
  for (const p of result.filePaths) {
    sendToRenderer('purplepdf:open-file', p);
  }
}

async function installAndReport(showDialog: boolean): Promise<void> {
  const result = await installPdfService(showDialog);
  if (!showDialog) return;
  if (!mainWindow) return;
  if (result.ok) {
    await dialog.showMessageBox(mainWindow, {
      type: 'info',
      message: 'Print to Purple PDF installed',
      detail:
        result.alreadyInstalled
          ? `Already installed at:\n${result.path}\n\nIn any application's Print dialog, open the "PDF" dropdown and choose "Print to Purple PDF".`
          : `Installed at:\n${result.path}\n\nIn any application's Print dialog, open the "PDF" dropdown and choose "Print to Purple PDF". Captured documents are saved to:\n${captureDir()}`,
      buttons: ['OK']
    });
  } else {
    await dialog.showMessageBox(mainWindow, {
      type: 'error',
      message: 'Could not install Print to Purple PDF',
      detail: result.reason ?? 'Unknown error',
      buttons: ['OK']
    });
  }
}

function buildRecentSubmenu(): MenuItemConstructorOptions[] {
  const recents = getRecents();
  if (recents.length === 0) {
    return [{ label: 'No Recent Files', enabled: false }];
  }
  const items: MenuItemConstructorOptions[] = recents.slice(0, 10).map((r) => ({
    label: r.name,
    sublabel: r.path,
    click: () => sendToRenderer('purplepdf:open-file', r.path)
  }));
  items.push({ type: 'separator' });
  items.push({
    label: 'Clear Recent Files',
    click: () => forgetRecents()
  });
  return items;
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
          label: 'Open…',
          accelerator: 'CmdOrCtrl+O',
          click: () => void openFilesDialog()
        },
        {
          label: 'Open Recent',
          submenu: buildRecentSubmenu()
        },
        { type: 'separator' },
        {
          label: 'Save',
          accelerator: 'CmdOrCtrl+S',
          click: () => sendToRenderer('purplepdf:save', null)
        },
        {
          label: 'Save As…',
          accelerator: 'CmdOrCtrl+Shift+S',
          click: () => sendToRenderer('purplepdf:save-as', null)
        },
        { type: 'separator' },
        {
          label: 'New from',
          submenu: [
            {
              label: 'Images…',
              click: () => sendToRenderer('purplepdf:new-from', 'images')
            },
            {
              label: 'Web Page…',
              click: () => sendToRenderer('purplepdf:new-from', 'url')
            },
            {
              label: 'Word / Excel / PowerPoint…',
              click: () => sendToRenderer('purplepdf:new-from', 'office')
            },
            { type: 'separator' },
            {
              label: 'Scanner (Image Capture)…',
              click: () => void shell.openExternal('imagecapture://')
            }
          ]
        },
        {
          label: 'Export As',
          submenu: [
            {
              label: 'Word (.docx)…',
              click: () => sendToRenderer('purplepdf:export-as', 'docx')
            },
            {
              label: 'Excel (.xlsx)…',
              click: () => sendToRenderer('purplepdf:export-as', 'xlsx')
            },
            {
              label: 'PowerPoint (.pptx)…',
              click: () => sendToRenderer('purplepdf:export-as', 'pptx')
            },
            { type: 'separator' },
            {
              label: 'Current Page as PNG…',
              click: () =>
                sendToRenderer('purplepdf:export-image', { scope: 'current', format: 'png' })
            },
            {
              label: 'Current Page as JPEG…',
              click: () =>
                sendToRenderer('purplepdf:export-image', { scope: 'current', format: 'jpeg' })
            },
            {
              label: 'All Pages as PNG…',
              click: () =>
                sendToRenderer('purplepdf:export-image', { scope: 'all', format: 'png' })
            },
            {
              label: 'All Pages as JPEG…',
              click: () =>
                sendToRenderer('purplepdf:export-image', { scope: 'all', format: 'jpeg' })
            },
            { type: 'separator' },
            {
              label: 'Form Data (.json)…',
              click: () => sendToRenderer('purplepdf:export-form', 'json')
            },
            {
              label: 'Form Data (.csv)…',
              click: () => sendToRenderer('purplepdf:export-form', 'csv')
            }
          ]
        },
        { type: 'separator' },
        {
          label: 'Install Print to Purple PDF…',
          click: () => void installAndReport(true)
        },
        {
          label: 'Reveal Print Captures',
          click: () => void shell.openPath(captureDir())
        },
        {
          label: 'Reveal Autosave Folder',
          click: () => void shell.openPath(autosaveDir())
        },
        { type: 'separator' },
        {
          label: 'Combine PDFs…',
          click: () => sendToRenderer('purplepdf:combine-pdfs', null)
        },
        {
          label: 'Split PDF…',
          click: () => sendToRenderer('purplepdf:split-pdf', null)
        },
        {
          label: 'Optimize PDF…',
          click: () => sendToRenderer('purplepdf:optimize-pdf', null)
        },
        {
          label: 'Add Watermark…',
          click: () => sendToRenderer('purplepdf:watermark', null)
        },
        {
          label: 'Header / Footer / Bates…',
          click: () => sendToRenderer('purplepdf:header-footer', null)
        },
        {
          label: 'Compare with Another PDF…',
          click: () => sendToRenderer('purplepdf:compare', null)
        },
        { type: 'separator' },
        {
          label: 'Close Tab',
          accelerator: 'CmdOrCtrl+W',
          click: () => sendToRenderer('purplepdf:close-tab', null)
        },
        isMac ? { role: 'close' } : { role: 'quit' }
      ]
    },
    {
      label: 'Edit',
      submenu: [
        {
          label: 'Undo',
          accelerator: 'CmdOrCtrl+Z',
          click: () => sendToRenderer('purplepdf:undo', null)
        },
        {
          label: 'Redo',
          accelerator: 'CmdOrCtrl+Shift+Z',
          click: () => sendToRenderer('purplepdf:redo', null)
        },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        { type: 'separator' },
        {
          label: 'Find…',
          accelerator: 'CmdOrCtrl+F',
          click: () => sendToRenderer('purplepdf:find', null)
        }
      ]
    },
    {
      label: 'Document',
      submenu: [
        {
          label: 'Document Properties…',
          accelerator: 'CmdOrCtrl+I',
          click: () => sendToRenderer('purplepdf:properties', null)
        },
        { type: 'separator' },
        {
          label: 'Protect with Password…',
          accelerator: 'CmdOrCtrl+Shift+P',
          click: () => sendToRenderer('purplepdf:protect', null)
        },
        {
          label: 'Remove Document Metadata',
          click: () => sendToRenderer('purplepdf:remove-metadata', null)
        },
        { type: 'separator' },
        {
          label: 'Auto-Crop Margins (Current Page)',
          click: () => sendToRenderer('purplepdf:auto-crop', 'current')
        },
        {
          label: 'Auto-Crop Margins (All Pages)',
          click: () => sendToRenderer('purplepdf:auto-crop', 'all')
        },
        { type: 'separator' },
        {
          label: 'OCR Current Page',
          click: () => sendToRenderer('purplepdf:ocr', 'current')
        },
        {
          label: 'OCR All Pages',
          click: () => sendToRenderer('purplepdf:ocr', 'all')
        },
        { type: 'separator' },
        {
          label: 'Add Signature…',
          accelerator: 'CmdOrCtrl+Shift+S',
          click: () => sendToRenderer('purplepdf:add-signature', null)
        },
        {
          label: 'Visual Redaction Tool',
          click: () => sendToRenderer('purplepdf:redact-tool', null)
        },
        { type: 'separator' },
        {
          label: 'Convert to Standard',
          submenu: [
            {
              label: 'PDF/A-1b…',
              click: () => sendToRenderer('purplepdf:convert-standard', 'PDF/A-1b')
            },
            {
              label: 'PDF/A-2b…',
              click: () => sendToRenderer('purplepdf:convert-standard', 'PDF/A-2b')
            },
            {
              label: 'PDF/A-3b…',
              click: () => sendToRenderer('purplepdf:convert-standard', 'PDF/A-3b')
            },
            {
              label: 'PDF/X-3…',
              click: () => sendToRenderer('purplepdf:convert-standard', 'PDF/X-3')
            }
          ]
        },
        {
          label: 'Accessibility Check',
          accelerator: 'CmdOrCtrl+Shift+A',
          click: () => sendToRenderer('purplepdf:a11y-check', null)
        }
      ]
    },
    {
      label: 'View',
      submenu: [
        {
          label: 'Zoom In',
          accelerator: 'CmdOrCtrl+=',
          click: () => sendToRenderer('purplepdf:zoom', 'in')
        },
        {
          label: 'Zoom Out',
          accelerator: 'CmdOrCtrl+-',
          click: () => sendToRenderer('purplepdf:zoom', 'out')
        },
        {
          label: 'Actual Size',
          accelerator: 'CmdOrCtrl+0',
          click: () => sendToRenderer('purplepdf:zoom', 'reset')
        },
        {
          label: 'Fit Width',
          accelerator: 'CmdOrCtrl+1',
          click: () => sendToRenderer('purplepdf:zoom', 'fit-width')
        },
        {
          label: 'Fit Page',
          accelerator: 'CmdOrCtrl+2',
          click: () => sendToRenderer('purplepdf:zoom', 'fit-page')
        },
        { type: 'separator' },
        {
          label: 'Rotate Clockwise',
          accelerator: 'CmdOrCtrl+R',
          click: () => sendToRenderer('purplepdf:rotate', 'cw')
        },
        {
          label: 'Rotate Counterclockwise',
          accelerator: 'CmdOrCtrl+Shift+R',
          click: () => sendToRenderer('purplepdf:rotate', 'ccw')
        },
        { type: 'separator' },
        { role: 'togglefullscreen' },
        { type: 'separator' },
        { role: 'reload' },
        { role: 'toggleDevTools' }
      ]
    },
    {
      label: 'Go',
      submenu: [
        {
          label: 'Next Page',
          accelerator: 'CmdOrCtrl+Right',
          click: () => sendToRenderer('purplepdf:page', 'next')
        },
        {
          label: 'Previous Page',
          accelerator: 'CmdOrCtrl+Left',
          click: () => sendToRenderer('purplepdf:page', 'prev')
        },
        {
          label: 'First Page',
          accelerator: 'CmdOrCtrl+Up',
          click: () => sendToRenderer('purplepdf:page', 'first')
        },
        {
          label: 'Last Page',
          accelerator: 'CmdOrCtrl+Down',
          click: () => sendToRenderer('purplepdf:page', 'last')
        }
      ]
    },
    { role: 'windowMenu' },
    {
      role: 'help',
      submenu: [
        {
          label: 'Purple PDF User Manual',
          click: () =>
            void shell.openExternal(
              'https://github.com/bronty13/PhantomLives/blob/main/PurplePDF/docs/USER_MANUAL.md'
            )
        },
        {
          label: 'Keyboard Shortcuts',
          accelerator: 'CmdOrCtrl+/',
          click: () => showShortcutsDialog()
        },
        { type: 'separator' },
        {
          label: 'Check for Updates…',
          click: () => void checkForUpdates(mainWindow, true)
        },
        {
          label: 'Show Crash Reports Folder',
          click: () => void shell.openPath(crashReportsDir())
        },
        {
          label: 'Report an Issue…',
          click: () =>
            void shell.openExternal(
              'https://github.com/bronty13/PhantomLives/issues/new'
            )
        },
        { type: 'separator' },
        {
          label: 'About Purple PDF',
          click: () => showAboutDialog()
        }
      ]
    }
  ];

  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

function showAboutDialog(): void {
  if (!mainWindow) return;
  void dialog.showMessageBox(mainWindow, {
    type: 'info',
    message: 'Purple PDF',
    detail:
      `Version ${app.getVersion()}\n` +
      `Electron ${process.versions.electron} • Node ${process.versions.node}\n` +
      `Platform ${process.platform} (${process.arch})\n\n` +
      'A full-featured PDF reader and editor.\n' +
      '© Robert Olen. Licensed for personal use.',
    buttons: ['OK']
  });
}

function showShortcutsDialog(): void {
  if (!mainWindow) return;
  void dialog.showMessageBox(mainWindow, {
    type: 'info',
    message: 'Keyboard Shortcuts',
    detail: [
      'File',
      '  ⌘O  Open…           ⌘W  Close Tab',
      '  ⌘S  Save            ⌘⇧S Save As…',
      '',
      'Edit',
      '  ⌘Z  Undo             ⌘⇧Z Redo',
      '  ⌘C  Copy             ⌘V  Paste',
      '',
      'View',
      '  ⌘+/⌘-  Zoom In/Out   ⌘0  Actual Size',
      '  ⌘F  Find',
      '',
      'Navigation',
      '  ←/→ or PgUp/PgDn  Previous / Next Page',
      '  Home / End        First / Last Page',
      '',
      'Document',
      '  ⌘I   Document Properties',
      '  ⌘⇧A  Accessibility Check',
      '',
      'Annotation Tools (when canvas focused)',
      '  V Select   H Highlight   U Underline   S Strikethrough',
      '  N Note     P Pen/Marker  R Rectangle   T Text Box',
      '  G Signature   X Redact',
      '  [ / ]  Decrease / Increase tool size',
      '',
      'Help',
      '  ⌘/   Show this dialog'
    ].join('\n'),
    buttons: ['OK']
  });
}

app.whenReady().then(() => {
  startCrashReporter();
  electronApp.setAppUserModelId('com.bronty13.purplepdf');
  registerAssetProtocolHandler();

  app.on('browser-window-created', (_, window) => {
    optimizer.watchWindowShortcuts(window);
  });

  ipcMain.handle('purplepdf:asset-bytes', async (_evt, rel: string) => {
    const safe = String(rel).split('/').filter((p) => p && p !== '..' && p !== '.');
    const buf = readAsset(...safe);
    return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
  });

  ipcMain.handle('purplepdf:asset-path', async (_evt, rel: string) => {
    const safe = String(rel).split('/').filter((p) => p && p !== '..' && p !== '.');
    return assetPath(...safe);
  });

  ipcMain.handle('purplepdf:ping', () => ({
    pong: true,
    version: app.getVersion(),
    platform: process.platform,
    electron: process.versions.electron
  }));

  ipcMain.handle('purplepdf:open-dialog', () => openFilesDialog());

  ipcMain.handle('purplepdf:read-file', async (_evt, filePath: string) => {
    const buf = await readFile(filePath);
    const name = basename(filePath);
    rememberRecent(filePath, name);
    // ArrayBuffer survives IPC structured-clone
    return {
      path: filePath,
      name,
      data: buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength)
    };
  });

  ipcMain.handle('purplepdf:get-recents', () => getRecents());
  ipcMain.handle('purplepdf:clear-recents', () => {
    forgetRecents();
    return [];
  });

  ipcMain.handle('purplepdf:pick-directory', async (): Promise<string | null> => {
    if (!mainWindow) return null;
    const r = await dialog.showOpenDialog(mainWindow, {
      title: 'Choose a folder',
      properties: ['openDirectory', 'createDirectory']
    });
    if (r.canceled || r.filePaths.length === 0) return null;
    return r.filePaths[0];
  });

  ipcMain.handle(
    'purplepdf:save-bytes',
    async (_evt, args: { path: string; bytes: ArrayBuffer }) => {
      await writeFile(args.path, Buffer.from(args.bytes));
      rememberRecent(args.path, basename(args.path));
      return { ok: true, path: args.path };
    }
  );

  ipcMain.handle(
    'purplepdf:save-as-dialog',
    async (_evt, defaultPath: string): Promise<string | null> => {
      if (!mainWindow) return null;
      const result = await dialog.showSaveDialog(mainWindow, {
        title: 'Save PDF As',
        defaultPath,
        filters: [{ name: 'PDF Document', extensions: ['pdf'] }]
      });
      if (result.canceled || !result.filePath) return null;
      return result.filePath;
    }
  );

  ipcMain.handle('purplepdf:printer-status', async () => ({
    platform: process.platform,
    installed: await isPdfServiceInstalled(),
    path: pdfServicePath(),
    captureDir: captureDir()
  }));

  ipcMain.handle('purplepdf:install-printer', async () => installPdfService(true));

  // ----- P4: Creation & conversion -----
  ipcMain.handle('purplepdf:converter-status', () => ({
    libreoffice: findLibreOffice()
  }));

  ipcMain.handle(
    'purplepdf:pick-images',
    async (): Promise<string[]> => {
      if (!mainWindow) return [];
      const result = await dialog.showOpenDialog(mainWindow, {
        title: 'Select images to combine into a PDF',
        properties: ['openFile', 'multiSelections'],
        filters: [
          {
            name: 'Images',
            extensions: [
              'jpg',
              'jpeg',
              'png',
              'heic',
              'heif',
              'tiff',
              'tif',
              'gif',
              'bmp',
              'webp'
            ]
          }
        ]
      });
      return result.canceled ? [] : result.filePaths;
    }
  );

  ipcMain.handle(
    'purplepdf:pick-pdf',
    async (): Promise<string | null> => {
      if (!mainWindow) return null;
      const r = await dialog.showOpenDialog(mainWindow, {
        title: 'Choose a PDF',
        properties: ['openFile'],
        filters: [{ name: 'PDF Document', extensions: ['pdf'] }]
      });
      if (r.canceled || r.filePaths.length === 0) return null;
      return r.filePaths[0];
    }
  );

  ipcMain.handle(
    'purplepdf:pick-office',
    async (): Promise<string[]> => {
      if (!mainWindow) return [];
      const result = await dialog.showOpenDialog(mainWindow, {
        title: 'Choose a Word / Excel / PowerPoint document to convert to PDF',
        properties: ['openFile'],
        filters: [
          {
            name: 'Office documents',
            extensions: [
              'docx',
              'doc',
              'rtf',
              'odt',
              'xlsx',
              'xls',
              'ods',
              'csv',
              'pptx',
              'ppt',
              'odp'
            ]
          }
        ]
      });
      return result.canceled ? [] : result.filePaths;
    }
  );

  ipcMain.handle(
    'purplepdf:images-to-pdf',
    async (_evt, args: { images: string[]; defaultName?: string }): Promise<string | null> => {
      if (!mainWindow) return null;
      const save = await dialog.showSaveDialog(mainWindow, {
        title: 'Save combined PDF',
        defaultPath: args.defaultName ?? 'Combined.pdf',
        filters: [{ name: 'PDF Document', extensions: ['pdf'] }]
      });
      if (save.canceled || !save.filePath) return null;
      await imagesToPdf(args.images, save.filePath);
      rememberRecent(save.filePath, basename(save.filePath));
      return save.filePath;
    }
  );

  ipcMain.handle(
    'purplepdf:url-to-pdf',
    async (_evt, args: { url: string; defaultName?: string }): Promise<string | null> => {
      if (!mainWindow) return null;
      const save = await dialog.showSaveDialog(mainWindow, {
        title: 'Save captured web page as PDF',
        defaultPath: args.defaultName ?? 'Web Page.pdf',
        filters: [{ name: 'PDF Document', extensions: ['pdf'] }]
      });
      if (save.canceled || !save.filePath) return null;
      await urlToPdf(args.url, save.filePath);
      rememberRecent(save.filePath, basename(save.filePath));
      return save.filePath;
    }
  );

  ipcMain.handle(
    'purplepdf:office-to-pdf',
    async (_evt, inputPath: string): Promise<string | null> => {
      if (!mainWindow) return null;
      const defaultName = `${basename(inputPath, extname(inputPath))}.pdf`;
      const save = await dialog.showSaveDialog(mainWindow, {
        title: 'Save converted PDF',
        defaultPath: defaultName,
        filters: [{ name: 'PDF Document', extensions: ['pdf'] }]
      });
      if (save.canceled || !save.filePath) return null;
      const outDir = tmpdir();
      const produced = await convertViaLibreOffice(inputPath, outDir, 'pdf');
      // Move produced file into the user-chosen location.
      const { rename, copyFile, unlink: rmFile } = await import('node:fs/promises');
      try {
        await rename(produced, save.filePath);
      } catch {
        await copyFile(produced, save.filePath);
        await rmFile(produced).catch(() => undefined);
      }
      rememberRecent(save.filePath, basename(save.filePath));
      return save.filePath;
    }
  );

  ipcMain.handle(
    'purplepdf:pdf-to-office',
    async (
      _evt,
      args: { bytes: ArrayBuffer; targetExt: 'docx' | 'xlsx' | 'pptx'; sourceName: string }
    ): Promise<string | null> => {
      if (!mainWindow) return null;
      const defaultName = `${basename(args.sourceName, extname(args.sourceName))}.${args.targetExt}`;
      const filterName =
        args.targetExt === 'docx'
          ? 'Word Document'
          : args.targetExt === 'xlsx'
            ? 'Excel Spreadsheet'
            : 'PowerPoint Presentation';
      const save = await dialog.showSaveDialog(mainWindow, {
        title: `Export as ${filterName}`,
        defaultPath: defaultName,
        filters: [{ name: filterName, extensions: [args.targetExt] }]
      });
      if (save.canceled || !save.filePath) return null;
      const tempPdf = await writeTempPdf(args.bytes);
      try {
        const produced = await convertViaLibreOffice(tempPdf, tmpdir(), args.targetExt);
        const { rename, copyFile, unlink: rmFile } = await import('node:fs/promises');
        try {
          await rename(produced, save.filePath);
        } catch {
          await copyFile(produced, save.filePath);
          await rmFile(produced).catch(() => undefined);
        }
        return save.filePath;
      } finally {
        const { unlink: rmFile } = await import('node:fs/promises');
        rmFile(tempPdf).catch(() => undefined);
      }
    }
  );

  ipcMain.handle('purplepdf:security-status', async () => ({
    qpdfVersion: await detectQpdf(),
    ghostscriptVersion: await detectGhostscript()
  }));

  ipcMain.handle(
    'purplepdf:protect-pdf',
    async (
      _evt,
      args: {
        bytes: ArrayBuffer;
        sourceName: string;
        userPassword: string;
        ownerPassword: string;
        permissions: QpdfPermissions;
      }
    ): Promise<string | null> => {
      if (!mainWindow) return null;
      const base = basename(args.sourceName, extname(args.sourceName));
      const defaultName = `${base}-protected.pdf`;
      const save = await dialog.showSaveDialog(mainWindow, {
        title: 'Save protected PDF',
        defaultPath: defaultName,
        filters: [{ name: 'PDF Document', extensions: ['pdf'] }]
      });
      if (save.canceled || !save.filePath) return null;
      await encryptWithQpdf({
        bytes: new Uint8Array(args.bytes),
        userPassword: args.userPassword,
        ownerPassword: args.ownerPassword,
        permissions: args.permissions,
        outputPath: save.filePath
      });
      rememberRecent(save.filePath, basename(save.filePath));
      return save.filePath;
    }
  );

  ipcMain.handle(
    'purplepdf:convert-standard',
    async (
      _evt,
      args: { bytes: ArrayBuffer; sourceName: string; target: StandardTarget }
    ): Promise<string | null> => {
      if (!mainWindow) return null;
      const base = basename(args.sourceName, extname(args.sourceName));
      const suffix = args.target.replace(/\//g, '').toLowerCase();
      const save = await dialog.showSaveDialog(mainWindow, {
        title: `Convert to ${args.target}`,
        defaultPath: `${base}-${suffix}.pdf`,
        filters: [{ name: 'PDF Document', extensions: ['pdf'] }]
      });
      if (save.canceled || !save.filePath) return null;
      await convertToStandard({
        bytes: new Uint8Array(args.bytes),
        target: args.target,
        outputPath: save.filePath
      });
      rememberRecent(save.filePath, basename(save.filePath));
      return save.filePath;
    }
  );

  // ----- Combine multiple PDFs into one -----
  ipcMain.handle('purplepdf:combine-pdfs', async (): Promise<string | null> => {
    if (!mainWindow) return null;
    const pick = await dialog.showOpenDialog(mainWindow, {
      title: 'Select PDFs to combine (in order)',
      properties: ['openFile', 'multiSelections'],
      filters: [{ name: 'PDF Document', extensions: ['pdf'] }]
    });
    if (pick.canceled || pick.filePaths.length === 0) return null;
    if (pick.filePaths.length < 2) {
      await dialog.showMessageBox(mainWindow, {
        type: 'info',
        message: 'Pick at least 2 PDFs to combine.'
      });
      return null;
    }
    const save = await dialog.showSaveDialog(mainWindow, {
      title: 'Save combined PDF as',
      defaultPath: 'Combined.pdf',
      filters: [{ name: 'PDF Document', extensions: ['pdf'] }]
    });
    if (save.canceled || !save.filePath) return null;
    try {
      const res = await combinePdfs(pick.filePaths, save.filePath);
      rememberRecent(save.filePath, basename(save.filePath));
      await dialog.showMessageBox(mainWindow, {
        type: 'info',
        message: 'Combined PDFs',
        detail: `Wrote ${res.pageCount} pages from ${res.inputCount} files to:\n${save.filePath}`,
        buttons: ['OK']
      });
      return save.filePath;
    } catch (err) {
      await dialog.showMessageBox(mainWindow, {
        type: 'error',
        message: 'Combine failed',
        detail: err instanceof Error ? err.message : String(err)
      });
      return null;
    }
  });

  // ----- Split the active PDF: per-page or by ranges -----
  ipcMain.handle(
    'purplepdf:split-pdf',
    async (
      _evt,
      args: { bytes: ArrayBuffer; sourceName: string; mode: 'per-page' | 'ranges'; ranges?: string }
    ): Promise<{ outDir: string; files: string[] } | null> => {
      if (!mainWindow) return null;
      const base = basename(args.sourceName, extname(args.sourceName)) || 'Document';
      if (args.mode === 'per-page') {
        const pick = await dialog.showOpenDialog(mainWindow, {
          title: 'Choose a folder to write the split PDFs into',
          properties: ['openDirectory', 'createDirectory']
        });
        if (pick.canceled || pick.filePaths.length === 0) return null;
        const outDir = pick.filePaths[0];
        const { writeFile: wf, mkdtemp } = await import('node:fs/promises');
        // Write source bytes to a temp file first so pdf-lib can load by path.
        const tdir = await mkdtemp(join(tmpdir(), 'ppdf-split-'));
        const tmpIn = join(tdir, 'source.pdf');
        await wf(tmpIn, Buffer.from(args.bytes));
        try {
          const files = await splitPdfPerPage(tmpIn, outDir, base);
          await dialog.showMessageBox(mainWindow, {
            type: 'info',
            message: 'Split PDF',
            detail: `Wrote ${files.length} files to:\n${outDir}`,
            buttons: ['OK']
          });
          return { outDir, files };
        } catch (err) {
          await dialog.showMessageBox(mainWindow, {
            type: 'error',
            message: 'Split failed',
            detail: err instanceof Error ? err.message : String(err)
          });
          return null;
        }
      } else {
        const ranges = args.ranges ?? '';
        let parsed: Array<[number, number]>;
        try {
          parsed = parseRangeString(ranges);
        } catch (err) {
          await dialog.showMessageBox(mainWindow, {
            type: 'error',
            message: 'Invalid range',
            detail: err instanceof Error ? err.message : String(err)
          });
          return null;
        }
        const save = await dialog.showSaveDialog(mainWindow, {
          title: 'Save extracted pages as',
          defaultPath: `${base}-extract.pdf`,
          filters: [{ name: 'PDF Document', extensions: ['pdf'] }]
        });
        if (save.canceled || !save.filePath) return null;
        const { writeFile: wf, mkdtemp } = await import('node:fs/promises');
        const tdir = await mkdtemp(join(tmpdir(), 'ppdf-extract-'));
        const tmpIn = join(tdir, 'source.pdf');
        await wf(tmpIn, Buffer.from(args.bytes));
        try {
          const res = await extractPages(tmpIn, parsed, save.filePath);
          rememberRecent(save.filePath, basename(save.filePath));
          return { outDir: save.filePath, files: [res.outPath] };
        } catch (err) {
          await dialog.showMessageBox(mainWindow, {
            type: 'error',
            message: 'Extract failed',
            detail: err instanceof Error ? err.message : String(err)
          });
          return null;
        }
      }
    }
  );

  // ----- Optimize / compress current PDF via Ghostscript -----
  ipcMain.handle(
    'purplepdf:optimize-pdf',
    async (
      _evt,
      args: { bytes: ArrayBuffer; sourceName: string; quality?: 'screen' | 'ebook' | 'printer' | 'prepress' }
    ): Promise<string | null> => {
      if (!mainWindow) return null;
      const base = basename(args.sourceName, extname(args.sourceName)) || 'Document';
      const save = await dialog.showSaveDialog(mainWindow, {
        title: 'Save optimized PDF as',
        defaultPath: `${base} (optimized).pdf`,
        filters: [{ name: 'PDF Document', extensions: ['pdf'] }]
      });
      if (save.canceled || !save.filePath) return null;
      try {
        const res = await optimizePdf({
          bytes: new Uint8Array(args.bytes),
          outputPath: save.filePath,
          quality: args.quality ?? 'ebook'
        });
        rememberRecent(save.filePath, basename(save.filePath));
        const pct = res.before > 0 ? Math.round((1 - res.after / res.before) * 100) : 0;
        const fmt = (n: number): string => {
          if (n > 1024 * 1024) return `${(n / 1024 / 1024).toFixed(2)} MB`;
          if (n > 1024) return `${(n / 1024).toFixed(1)} KB`;
          return `${n} B`;
        };
        await dialog.showMessageBox(mainWindow, {
          type: 'info',
          message: 'Optimized PDF',
          detail: `${fmt(res.before)} → ${fmt(res.after)} (${pct >= 0 ? '-' : '+'}${Math.abs(pct)}%)\n\n${save.filePath}`,
          buttons: ['OK']
        });
        return save.filePath;
      } catch (err) {
        await dialog.showMessageBox(mainWindow, {
          type: 'error',
          message: 'Optimize failed',
          detail: err instanceof Error ? err.message : String(err)
        });
        return null;
      }
    }
  );

  // ----- Autosave -----
  ipcMain.handle(
    'purplepdf:autosave-write',
    async (
      _evt,
      args: { bytes: ArrayBuffer; sourcePath: string | null; sourceName: string }
    ): Promise<string> => {
      return await writeAutosave({
        bytes: new Uint8Array(args.bytes),
        sourcePath: args.sourcePath,
        sourceName: args.sourceName
      });
    }
  );
  ipcMain.handle(
    'purplepdf:autosave-clear',
    async (_evt, args: { sourcePath: string | null; sourceName: string }): Promise<void> => {
      await clearAutosave(args.sourcePath, args.sourceName);
    }
  );
  ipcMain.handle('purplepdf:autosave-list', async () => listAutosaves());

  buildMenu();
  mainWindow = createMainWindow();
  scheduleStartupCheck(() => mainWindow);

  // Offer to reopen any autosaved documents from a prior session.
  void (async () => {
    const list = await listAutosaves();
    if (list.length === 0 || !mainWindow) return;
    const names = list.slice(0, 5).map((m) => `  • ${m.sourceName}`).join('\n');
    const more = list.length > 5 ? `\n  …and ${list.length - 5} more` : '';
    const res = await dialog.showMessageBox(mainWindow, {
      type: 'question',
      message: 'Recover unsaved work?',
      detail: `Purple PDF found ${list.length} autosaved document(s):\n${names}${more}`,
      buttons: ['Open Autosave Folder', 'Discard All', 'Not Now'],
      defaultId: 0,
      cancelId: 2
    });
    if (res.response === 0) {
      void shell.openPath(autosaveDir());
    } else if (res.response === 1) {
      for (const m of list) {
        await clearAutosave(m.sourcePath, m.sourceName);
      }
    }
  })();

  // re-trigger from File > Install Print to Purple PDF…).
  void installPdfService(false);

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      mainWindow = createMainWindow();
    }
  });
});

// macOS file association: opening a .pdf via Finder
app.on('open-file', (event, filePath) => {
  event.preventDefault();
  if (mainWindow) {
    sendToRenderer('purplepdf:open-file', filePath);
  } else {
    app.whenReady().then(() => sendToRenderer('purplepdf:open-file', filePath));
  }
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
