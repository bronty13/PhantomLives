import { useCallback, useEffect, useRef, useState } from 'react';
import type { NodeRow, ScanProgress, ScanStats, RectNode, ExportFormat } from '../../shared/types';
import { formatBytes, formatCount, formatDuration, formatRate } from './features/common/format';
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
  sizeMetric: 'alloc' | 'logical';
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
  const [cancelling, setCancelling] = useState(false);
  const [refreshKey, setRefreshKey] = useState(0);
  const [elapsedMs, setElapsedMs] = useState(0);
  const [rate, setRate] = useState(0);
  const scanIdRef = useRef<string | null>(null);
  const scanStartRef = useRef<number>(0);
  const rateSampleRef = useRef<{ t: number; files: number } | null>(null);

  const metric = prefs?.sizeMetric ?? 'alloc';
  const toggleMetric = async (): Promise<void> => {
    const next = metric === 'alloc' ? 'logical' : 'alloc';
    await api.setSizeMetric(next);
    loadPrefs();
    if (scanIdRef.current) {
      const r = await api.getRoot(scanIdRef.current);
      setRoot(r);
    }
    setRefreshKey((k) => k + 1);
  };

  const loadPrefs = useCallback(() => {
    void api.prefsGet().then((p) => setPrefs(p as unknown as Prefs));
  }, []);

  const startScanOf = useCallback(async (dir: string) => {
    const opts = (await api.prefsGet()).scanOptions;
    const id = await api.startScan(dir, opts);
    scanIdRef.current = id;
    scanStartRef.current = Date.now();
    rateSampleRef.current = null;
    setScanId(id);
    setStatus('scanning');
    setProgress(null);
    setRate(0);
    setElapsedMs(0);
    setCancelling(false);
    setView('explorer');
  }, []);

  const chooseFolder = useCallback(async () => {
    const dir = await api.pickDirectory();
    if (dir) await startScanOf(dir);
  }, [startScanOf]);

  useEffect(() => {
    loadPrefs();
    // Debug: auto-start a scan when launched with PT_AUTOSCAN (no-op normally).
    void api.autoscanPath().then((p) => {
      if (p) void startScanOf(p);
    });
    const offProg = api.onScanProgress((p) => {
      if (p.scanId !== scanIdRef.current) return;
      const now = Date.now();
      const prev = rateSampleRef.current;
      if (prev && now > prev.t) {
        const inst = ((p.filesScanned - prev.files) * 1000) / (now - prev.t);
        setRate((r) => (r <= 0 ? inst : r * 0.7 + inst * 0.3)); // smooth (EMA)
      }
      rateSampleRef.current = { t: now, files: p.filesScanned };
      setElapsedMs(now - scanStartRef.current);
      setProgress(p);
    });
    const offDone = api.onScanComplete((s) => {
      if (s.scanId !== scanIdRef.current) return;
      setCancelling(false);
      setStats(s);
      void api.getRoot(s.scanId).then((r) => {
        setRoot(r);
        setFocusId(0);
        setStatus('ready');
      });
    });
    const offErr = api.onScanError((e) => {
      if (e.scanId === scanIdRef.current) {
        setCancelling(false);
        setStatus('error');
        setToast(`Scan failed: ${e.message}`);
      }
    });
    const offCancelled = api.onScanCancelled((e) => {
      if (e.scanId !== scanIdRef.current) return;
      setCancelling(false);
      scanIdRef.current = null;
      setStatus('empty');
      setToast('Scan cancelled.');
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
      offCancelled();
      offMenu();
    };
  }, [chooseFolder, loadPrefs, startScanOf]);

  // Keep the elapsed clock ticking during scanning even when progress events
  // pause (e.g. the final tree-build phase emits none).
  useEffect(() => {
    if (status !== 'scanning') return;
    const iv = setInterval(() => setElapsedMs(Date.now() - scanStartRef.current), 500);
    return () => clearInterval(iv);
  }, [status]);

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
        {status === 'ready' && root && (
          <span className="topbar-stats">
            {formatBytes(root.aggSize)} · {formatCount(root.fileCount)} files
            {stats && stats.permDeniedCount > 0 && ` · ${stats.permDeniedCount} skipped`}
            {stats?.partial && ' · partial'}
          </span>
        )}
        {status === 'ready' && (
          <button
            title="Toggle between on-disk (allocated) and logical (content) size"
            onClick={() => void toggleMetric()}
          >
            {metric === 'alloc' ? 'On-disk' : 'Logical'}
          </button>
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
                    <p className="scan-rate">
                      {formatDuration(elapsedMs)} elapsed · {formatRate(rate)} files/sec
                      {progress.permDeniedCount > 0 && ` · ${formatCount(progress.permDeniedCount)} skipped`}
                    </p>
                    <p className="scan-path" title={progress.currentPath}>
                      {progress.currentPath}
                    </p>
                  </>
                )}
                <button
                  disabled={cancelling}
                  onClick={() => {
                    if (!scanId) return;
                    setCancelling(true);
                    void api.cancelScan(scanId);
                  }}
                >
                  {cancelling ? 'Cancelling…' : 'Cancel'}
                </button>
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
            <div className="explorer" key={`${scanId}-${refreshKey}`}>
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
            <LargeOldFilesView key={refreshKey} scanId={scanId} allowPermanent={allowPermanent} />
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
