import { useCallback, useEffect, useRef, useState } from 'react';
import type { NodeRow, ScanProgress, ScanStats, RectNode, ExportFormat } from '../../shared/types';
import { formatBytes, formatCount } from './features/common/format';
import FolderTree from './features/tree/FolderTree';
import DetailList from './features/tree/DetailList';
import TreemapCanvas from './features/treemap/TreemapCanvas';
import Breadcrumb from './features/treemap/Breadcrumb';
import DuplicatesView from './features/duplicates/DuplicatesView';
import LargeOldFilesView from './features/largeold/LargeOldFilesView';
import CacheCleanupView from './features/cache/CacheCleanupView';
import SettingsModal from './features/settings/SettingsModal';

const api = window.purpleTree;
type View = 'explorer' | 'duplicates' | 'largeold' | 'cache';

interface Prefs {
  scanOptions: { followSymlinks: boolean; crossMountPoints: boolean; dedupHardLinks: boolean };
  permanentDeleteEnabled: boolean;
}

export default function App(): JSX.Element {
  const [prefs, setPrefs] = useState<Prefs | null>(null);
  const [scanId, setScanId] = useState<string | null>(null);
  const [status, setStatus] = useState<'empty' | 'scanning' | 'ready' | 'error'>('empty');
  const [progress, setProgress] = useState<ScanProgress | null>(null);
  const [stats, setStats] = useState<ScanStats | null>(null);
  const [root, setRoot] = useState<NodeRow | null>(null);
  const [focusId, setFocusId] = useState(0);
  const [view, setView] = useState<View>('explorer');
  const [sidebar, setSidebar] = useState(true);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [exportOpen, setExportOpen] = useState(false);
  const [toast, setToast] = useState('');
  const scanIdRef = useRef<string | null>(null);

  const loadPrefs = useCallback(() => {
    void api.prefsGet().then((p) => setPrefs(p as unknown as Prefs));
  }, []);

  const chooseFolder = useCallback(async () => {
    const dir = await api.pickDirectory();
    if (!dir) return;
    const opts = (await api.prefsGet()).scanOptions;
    const id = await api.startScan(dir, opts);
    scanIdRef.current = id;
    setScanId(id);
    setStatus('scanning');
    setProgress(null);
    setView('explorer');
  }, []);

  useEffect(() => {
    loadPrefs();
    const offProg = api.onScanProgress((p) => {
      if (p.scanId === scanIdRef.current) setProgress(p);
    });
    const offDone = api.onScanComplete((s) => {
      if (s.scanId !== scanIdRef.current) return;
      setStats(s);
      void api.getRoot(s.scanId).then((r) => {
        setRoot(r);
        setFocusId(0);
        setStatus('ready');
      });
    });
    const offErr = api.onScanError((e) => {
      if (e.scanId === scanIdRef.current) {
        setStatus('error');
        setToast(`Scan failed: ${e.message}`);
      }
    });
    const offMenu = api.onMenu((action) => {
      if (action === 'open-folder') void chooseFolder();
      else if (action === 'settings') setSettingsOpen(true);
      else if (action === 'export') setExportOpen(true);
      else if (action === 'toggle-sidebar') setSidebar((s) => !s);
    });
    return () => {
      offProg();
      offDone();
      offErr();
      offMenu();
    };
  }, [chooseFolder, loadPrefs]);

  const onPick = (node: RectNode): void => {
    if (node.isDir) setFocusId(node.id);
    else void api.reveal(node.path);
  };

  const doExport = async (format: ExportFormat): Promise<void> => {
    setExportOpen(false);
    if (!scanId) return;
    const path = await api.exportReport(scanId, format);
    if (path) setToast(`Exported to ${path}`);
  };

  const saveSnapshot = async (): Promise<void> => {
    if (!scanId) return;
    const ok = await api.snapshotSave(scanId);
    setToast(ok ? 'Snapshot saved.' : 'Could not save snapshot.');
  };

  const allowPermanent = prefs?.permanentDeleteEnabled ?? false;

  return (
    <div className="app">
      <div className="topbar">
        <button className="icon-btn" title="Toggle sidebar" onClick={() => setSidebar((s) => !s)}>
          ☰
        </button>
        <span className="brand">🟪 Purple Tree</span>
        <button className="btn-primary" onClick={() => void chooseFolder()}>
          {status === 'empty' ? 'Scan a Folder…' : 'New Scan…'}
        </button>
        {root && (
          <span className="root-label" title={root.path}>
            {root.path}
          </span>
        )}
        <div className="spacer" />
        {status === 'ready' && stats && (
          <span className="topbar-stats">
            {formatBytes(stats.totalBytes)} · {formatCount(stats.totalFiles)} files
            {stats.permDeniedCount > 0 && ` · ${stats.permDeniedCount} skipped`}
            {stats.partial && ' · partial'}
          </span>
        )}
        {status === 'ready' && (
          <div className="export-wrap">
            <button onClick={() => setExportOpen((o) => !o)}>Export ▾</button>
            {exportOpen && (
              <div className="export-pop">
                <button onClick={() => void doExport('csv')}>CSV</button>
                <button onClick={() => void doExport('html')}>HTML</button>
                <button onClick={() => void doExport('json')}>JSON</button>
              </div>
            )}
          </div>
        )}
        {status === 'ready' && <button onClick={() => void saveSnapshot()}>Save Snapshot</button>}
        <button className="icon-btn" title="Settings" onClick={() => setSettingsOpen(true)}>
          ⚙
        </button>
      </div>

      <div className="body">
        {sidebar && (
          <nav className="sidebar">
            <button className={view === 'explorer' ? 'active' : ''} onClick={() => setView('explorer')}>
              🗂 Explorer
            </button>
            <button
              className={view === 'duplicates' ? 'active' : ''}
              onClick={() => setView('duplicates')}
              disabled={status !== 'ready'}
            >
              👯 Duplicates
            </button>
            <button
              className={view === 'largeold' ? 'active' : ''}
              onClick={() => setView('largeold')}
              disabled={status !== 'ready'}
            >
              📦 Large &amp; Old
            </button>
            <button className={view === 'cache' ? 'active' : ''} onClick={() => setView('cache')}>
              🧹 Cache Cleanup
            </button>
          </nav>
        )}

        <main className="main">
          {status === 'empty' && view !== 'cache' && (
            <div className="empty-state">
              <div className="empty-card">
                <div className="empty-icon">🌳</div>
                <h1>Purple Tree</h1>
                <p>See what&apos;s using your disk space, find duplicates, and clean up safely.</p>
                <button className="btn-primary big" onClick={() => void chooseFolder()}>
                  Scan a Folder…
                </button>
              </div>
            </div>
          )}

          {status === 'scanning' && (
            <div className="empty-state">
              <div className="empty-card">
                <div className="spinner" />
                <h2>Scanning…</h2>
                {progress && (
                  <>
                    <p className="scan-counts">
                      {formatCount(progress.filesScanned)} files ·{' '}
                      {formatCount(progress.dirsScanned)} folders · {formatBytes(progress.bytes)}
                    </p>
                    <p className="scan-path" title={progress.currentPath}>
                      {progress.currentPath}
                    </p>
                  </>
                )}
                <button onClick={() => scanId && void api.cancelScan(scanId)}>Cancel</button>
              </div>
            </div>
          )}

          {status === 'error' && view !== 'cache' && (
            <div className="empty-state">
              <div className="empty-card">
                <div className="empty-icon">⚠️</div>
                <h2>Scan failed</h2>
                <button className="btn-primary" onClick={() => void chooseFolder()}>
                  Try another folder
                </button>
              </div>
            </div>
          )}

          {view === 'cache' && <CacheCleanupView />}

          {status === 'ready' && scanId && root && view === 'explorer' && (
            <div className="explorer">
              <Breadcrumb scanId={scanId} focusId={focusId} onNavigate={setFocusId} />
              <div className="explorer-body">
                <div className="explorer-tree">
                  <FolderTree scanId={scanId} root={root} focusId={focusId} onSelect={setFocusId} />
                </div>
                <div className="explorer-right">
                  <TreemapCanvas scanId={scanId} focusId={focusId} onPick={onPick} />
                  <DetailList
                    scanId={scanId}
                    focusId={focusId}
                    allowPermanent={allowPermanent}
                    onDrill={setFocusId}
                  />
                </div>
              </div>
            </div>
          )}

          {status === 'ready' && scanId && view === 'duplicates' && (
            <DuplicatesView scanId={scanId} allowPermanent={allowPermanent} />
          )}
          {status === 'ready' && scanId && view === 'largeold' && (
            <LargeOldFilesView scanId={scanId} allowPermanent={allowPermanent} />
          )}
        </main>
      </div>

      {settingsOpen && (
        <SettingsModal onClose={() => setSettingsOpen(false)} onPrefsChanged={loadPrefs} />
      )}
      {toast && (
        <div className="toast" onClick={() => setToast('')}>
          {toast}
        </div>
      )}
    </div>
  );
}
