import { contextBridge, ipcRenderer, type IpcRendererEvent } from 'electron';
import type { LoadedFile, PageCmd, RecentFile, RotateCmd, ZoomCmd } from '../shared/types';

const api = {
  ping: (): Promise<{
    pong: boolean;
    version: string;
    platform: string;
    electron: string;
  }> => ipcRenderer.invoke('purplepdf:ping'),

  /** Read a bundled resource (under resources/) as raw bytes. */
  assetBytes: (rel: string): Promise<ArrayBuffer> =>
    ipcRenderer.invoke('purplepdf:asset-bytes', rel),
  /** Resolve a bundled resource to a URL the renderer can use (pp-asset://). */
  assetUrl: (rel: string): string => {
    const safe = rel.split('/').filter((p) => p && p !== '..' && p !== '.').join('/');
    return `pp-asset://local/${safe}`;
  },

  openDialog: (): Promise<void> => ipcRenderer.invoke('purplepdf:open-dialog'),

  readFile: (filePath: string): Promise<LoadedFile> =>
    ipcRenderer.invoke('purplepdf:read-file', filePath),

  getRecents: (): Promise<RecentFile[]> => ipcRenderer.invoke('purplepdf:get-recents'),
  clearRecents: (): Promise<RecentFile[]> => ipcRenderer.invoke('purplepdf:clear-recents'),

  saveBytes: (path: string, bytes: ArrayBuffer): Promise<{ ok: boolean; path: string }> =>
    ipcRenderer.invoke('purplepdf:save-bytes', { path, bytes }),
  saveAsDialog: (defaultPath: string): Promise<string | null> =>
    ipcRenderer.invoke('purplepdf:save-as-dialog', defaultPath),

  printerStatus: (): Promise<{
    platform: string;
    installed: boolean;
    path: string;
    captureDir: string;
  }> => ipcRenderer.invoke('purplepdf:printer-status'),
  installPrinter: (): Promise<{
    ok: boolean;
    path: string;
    alreadyInstalled: boolean;
    reason?: string;
  }> => ipcRenderer.invoke('purplepdf:install-printer'),

  converterStatus: (): Promise<{ libreoffice: string | null }> =>
    ipcRenderer.invoke('purplepdf:converter-status'),
  pickImages: (): Promise<string[]> => ipcRenderer.invoke('purplepdf:pick-images'),
  pickOffice: (): Promise<string[]> => ipcRenderer.invoke('purplepdf:pick-office'),
  imagesToPdf: (images: string[], defaultName?: string): Promise<string | null> =>
    ipcRenderer.invoke('purplepdf:images-to-pdf', { images, defaultName }),
  urlToPdf: (url: string, defaultName?: string): Promise<string | null> =>
    ipcRenderer.invoke('purplepdf:url-to-pdf', { url, defaultName }),
  officeToPdf: (inputPath: string): Promise<string | null> =>
    ipcRenderer.invoke('purplepdf:office-to-pdf', inputPath),
  pdfToOffice: (
    bytes: ArrayBuffer,
    targetExt: 'docx' | 'xlsx' | 'pptx',
    sourceName: string
  ): Promise<string | null> =>
    ipcRenderer.invoke('purplepdf:pdf-to-office', { bytes, targetExt, sourceName }),

  securityStatus: (): Promise<{ qpdfVersion: string | null; ghostscriptVersion: string | null }> =>
    ipcRenderer.invoke('purplepdf:security-status'),
  protectPdf: (args: {
    bytes: ArrayBuffer;
    sourceName: string;
    userPassword: string;
    ownerPassword: string;
    permissions: { print: boolean; copy: boolean; modify: boolean; annotate: boolean };
  }): Promise<string | null> => ipcRenderer.invoke('purplepdf:protect-pdf', args),

  convertToStandard: (args: {
    bytes: ArrayBuffer;
    sourceName: string;
    target: 'PDF/A-1b' | 'PDF/A-2b' | 'PDF/A-3b' | 'PDF/X-3';
  }): Promise<string | null> => ipcRenderer.invoke('purplepdf:convert-standard', args),

  combinePdfs: (): Promise<string | null> => ipcRenderer.invoke('purplepdf:combine-pdfs'),
  splitPdf: (args: {
    bytes: ArrayBuffer;
    sourceName: string;
    mode: 'per-page' | 'ranges';
    ranges?: string;
  }): Promise<{ outDir: string; files: string[] } | null> =>
    ipcRenderer.invoke('purplepdf:split-pdf', args),

  pickDirectory: (): Promise<string | null> => ipcRenderer.invoke('purplepdf:pick-directory'),

  autosaveWrite: (args: {
    bytes: ArrayBuffer;
    sourcePath: string | null;
    sourceName: string;
  }): Promise<string> => ipcRenderer.invoke('purplepdf:autosave-write', args),
  autosaveClear: (args: { sourcePath: string | null; sourceName: string }): Promise<void> =>
    ipcRenderer.invoke('purplepdf:autosave-clear', args),

  optimizePdf: (args: {
    bytes: ArrayBuffer;
    sourceName: string;
    quality?: 'screen' | 'ebook' | 'printer' | 'prepress';
  }): Promise<string | null> => ipcRenderer.invoke('purplepdf:optimize-pdf', args),

  onOpenFile: (cb: (path: string) => void): (() => void) => {
    const h = (_e: IpcRendererEvent, p: string): void => cb(p);
    ipcRenderer.on('purplepdf:open-file', h);
    return () => ipcRenderer.removeListener('purplepdf:open-file', h);
  },
  onCloseTab: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:close-tab', h);
    return () => ipcRenderer.removeListener('purplepdf:close-tab', h);
  },
  onFind: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:find', h);
    return () => ipcRenderer.removeListener('purplepdf:find', h);
  },
  onSave: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:save', h);
    return () => ipcRenderer.removeListener('purplepdf:save', h);
  },
  onSaveAs: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:save-as', h);
    return () => ipcRenderer.removeListener('purplepdf:save-as', h);
  },
  onNewFrom: (cb: (kind: 'images' | 'url' | 'office') => void): (() => void) => {
    const h = (_e: IpcRendererEvent, kind: 'images' | 'url' | 'office'): void => cb(kind);
    ipcRenderer.on('purplepdf:new-from', h);
    return () => ipcRenderer.removeListener('purplepdf:new-from', h);
  },
  onExportAs: (cb: (kind: 'docx' | 'xlsx' | 'pptx') => void): (() => void) => {
    const h = (_e: IpcRendererEvent, kind: 'docx' | 'xlsx' | 'pptx'): void => cb(kind);
    ipcRenderer.on('purplepdf:export-as', h);
    return () => ipcRenderer.removeListener('purplepdf:export-as', h);
  },
  onExportForm: (cb: (kind: 'json' | 'csv') => void): (() => void) => {
    const h = (_e: IpcRendererEvent, kind: 'json' | 'csv'): void => cb(kind);
    ipcRenderer.on('purplepdf:export-form', h);
    return () => ipcRenderer.removeListener('purplepdf:export-form', h);
  },
  onProtect: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:protect', h);
    return () => ipcRenderer.removeListener('purplepdf:protect', h);
  },
  onRemoveMetadata: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:remove-metadata', h);
    return () => ipcRenderer.removeListener('purplepdf:remove-metadata', h);
  },
  onAddSignature: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:add-signature', h);
    return () => ipcRenderer.removeListener('purplepdf:add-signature', h);
  },
  onRedactTool: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:redact-tool', h);
    return () => ipcRenderer.removeListener('purplepdf:redact-tool', h);
  },
  onProperties: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:properties', h);
    return () => ipcRenderer.removeListener('purplepdf:properties', h);
  },
  onConvertStandard: (
    cb: (target: 'PDF/A-1b' | 'PDF/A-2b' | 'PDF/A-3b' | 'PDF/X-3') => void
  ): (() => void) => {
    const h = (
      _e: IpcRendererEvent,
      target: 'PDF/A-1b' | 'PDF/A-2b' | 'PDF/A-3b' | 'PDF/X-3'
    ): void => cb(target);
    ipcRenderer.on('purplepdf:convert-standard', h);
    return () => ipcRenderer.removeListener('purplepdf:convert-standard', h);
  },
  onA11yCheck: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:a11y-check', h);
    return () => ipcRenderer.removeListener('purplepdf:a11y-check', h);
  },
  onUndo: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:undo', h);
    return () => ipcRenderer.removeListener('purplepdf:undo', h);
  },
  onRedo: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:redo', h);
    return () => ipcRenderer.removeListener('purplepdf:redo', h);
  },
  onZoom: (cb: (cmd: ZoomCmd) => void): (() => void) => {
    const h = (_e: IpcRendererEvent, cmd: ZoomCmd): void => cb(cmd);
    ipcRenderer.on('purplepdf:zoom', h);
    return () => ipcRenderer.removeListener('purplepdf:zoom', h);
  },
  onRotate: (cb: (cmd: RotateCmd) => void): (() => void) => {
    const h = (_e: IpcRendererEvent, cmd: RotateCmd): void => cb(cmd);
    ipcRenderer.on('purplepdf:rotate', h);
    return () => ipcRenderer.removeListener('purplepdf:rotate', h);
  },
  onPage: (cb: (cmd: PageCmd) => void): (() => void) => {
    const h = (_e: IpcRendererEvent, cmd: PageCmd): void => cb(cmd);
    ipcRenderer.on('purplepdf:page', h);
    return () => ipcRenderer.removeListener('purplepdf:page', h);
  },
  onCombinePdfs: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:combine-pdfs', h);
    return () => ipcRenderer.removeListener('purplepdf:combine-pdfs', h);
  },
  onSplitPdf: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:split-pdf', h);
    return () => ipcRenderer.removeListener('purplepdf:split-pdf', h);
  },
  onOptimizePdf: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:optimize-pdf', h);
    return () => ipcRenderer.removeListener('purplepdf:optimize-pdf', h);
  },
  onWatermark: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:watermark', h);
    return () => ipcRenderer.removeListener('purplepdf:watermark', h);
  },
  onHeaderFooter: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:header-footer', h);
    return () => ipcRenderer.removeListener('purplepdf:header-footer', h);
  },
  onAutoCrop: (cb: (scope: 'current' | 'all') => void): (() => void) => {
    const h = (_e: IpcRendererEvent, scope: 'current' | 'all'): void => cb(scope);
    ipcRenderer.on('purplepdf:auto-crop', h);
    return () => ipcRenderer.removeListener('purplepdf:auto-crop', h);
  },
  onCompare: (cb: () => void): (() => void) => {
    const h = (): void => cb();
    ipcRenderer.on('purplepdf:compare', h);
    return () => ipcRenderer.removeListener('purplepdf:compare', h);
  },
  onOcr: (cb: (scope: 'current' | 'all') => void): (() => void) => {
    const h = (_e: IpcRendererEvent, scope: 'current' | 'all'): void => cb(scope);
    ipcRenderer.on('purplepdf:ocr', h);
    return () => ipcRenderer.removeListener('purplepdf:ocr', h);
  },
  pickPdf: (): Promise<string | null> => ipcRenderer.invoke('purplepdf:pick-pdf'),
  onExportImage: (
    cb: (args: { scope: 'current' | 'all'; format: 'png' | 'jpeg' }) => void
  ): (() => void) => {
    const h = (
      _e: IpcRendererEvent,
      args: { scope: 'current' | 'all'; format: 'png' | 'jpeg' }
    ): void => cb(args);
    ipcRenderer.on('purplepdf:export-image', h);
    return () => ipcRenderer.removeListener('purplepdf:export-image', h);
  }
};

contextBridge.exposeInMainWorld('purplePDF', api);

export type PurplePDFApi = typeof api;
