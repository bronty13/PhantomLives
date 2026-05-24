import { useEffect, useState } from 'react';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import { Sidebar, type ViewKey } from './components/Sidebar';
import { InboxView } from './views/Inbox/InboxView';
import { SettingsView } from './views/Settings/SettingsView';
import { ManualView } from './views/Manual/ManualView';
import { BundleWorkspace } from './views/Bundle/BundleWorkspace';
import { ingestBundle, type IngestResult } from './data/bundles';
import { db } from './data/db';

interface IngestStatus {
  kind: 'idle' | 'busy' | 'ok' | 'error';
  message: string;
}

export default function App() {
  const [view, setView] = useState<ViewKey>('inbox');
  const [sidebarVisible, setSidebarVisible] = useState(true);
  // When non-null, the per-bundle workspace overlays the main view.
  const [openBundleUid, setOpenBundleUid] = useState<string | null>(null);
  // Inbox listens on this counter and refreshes whenever it increments.
  const [refreshSignal, setRefreshSignal] = useState(0);
  const [ingestStatus, setIngestStatus] = useState<IngestStatus>({ kind: 'idle', message: '' });
  const [dragHover, setDragHover] = useState(false);
  // tauri-plugin-sql runs migrations only on the first JS-side
  // Database.load(). The Phase 1 Rust commands open the DB via rusqlite
  // independently, so if we don't trigger Database.load() first, those
  // commands see an empty DB and fail with "no such table: bundles."
  // Gate the entire UI on this until migrations have run.
  const [dbReady, setDbReady] = useState(false);
  const [dbError, setDbError] = useState<string | null>(null);

  // Force-trigger migrations before rendering anything that invokes Rust
  // commands. db() returns a memoised Database promise on first call.
  useEffect(() => {
    db()
      .then(() => setDbReady(true))
      .catch((e) => setDbError(String(e)));
  }, []);

  // Watched-folder ingest emits `bundle-ingested` from the Rust side.
  // Bump the refresh signal so the Inbox re-queries, and quietly surface
  // a toast so the user knows something just landed.
  useEffect(() => {
    let unlisten: UnlistenFn | undefined;
    (async () => {
      unlisten = await listen<IngestResult>('bundle-ingested', (event) => {
        setRefreshSignal((n) => n + 1);
        const r = event.payload;
        setIngestStatus({
          kind: 'ok',
          message: `Watched folder: ingested ${r.title || r.uid} (${r.fileCount} files).`,
        });
      });
    })();
    return () => { unlisten?.(); };
  }, []);

  // Cmd+S / Ctrl+S toggles the sidebar (same shortcut Molly uses).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const mod = e.metaKey || e.ctrlKey;
      if (mod && (e.key === 's' || e.key === 'S')) {
        e.preventDefault();
        setSidebarVisible((v) => !v);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  // Tauri 2 OS-level drag-drop. The window's dragDropEnabled is true in
  // tauri.conf.json so the OS routes drop events here instead of the
  // webview. Each .zip path runs through ingest_bundle; success refreshes
  // the Inbox + jumps to the bundle workspace.
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    (async () => {
      const win = getCurrentWindow();
      const fn = await win.onDragDropEvent(async (event) => {
        const payload = event.payload;
        if (payload.type === 'enter' || payload.type === 'over') {
          setDragHover(true);
          return;
        }
        if (payload.type === 'leave') {
          setDragHover(false);
          return;
        }
        if (payload.type === 'drop') {
          setDragHover(false);
          const zipPaths = (payload.paths ?? []).filter((p: string) =>
            p.toLowerCase().endsWith('.zip'),
          );
          if (zipPaths.length === 0) {
            setIngestStatus({ kind: 'error', message: 'No .zip files in the dropped set.' });
            return;
          }
          let lastUid: string | null = null;
          for (const p of zipPaths) {
            setIngestStatus({ kind: 'busy', message: `Verifying ${shortName(p)}…` });
            try {
              const r = await ingestBundle(p);
              lastUid = r.uid;
              setIngestStatus({
                kind: 'ok',
                message: `Ingested ${r.title || r.uid} (${r.fileCount} files, ${r.manifestSource === 'manifest_json' ? 'manifest.json' : 'Molly.log fallback'}).`,
              });
            } catch (e) {
              setIngestStatus({ kind: 'error', message: `Failed: ${e}` });
            }
          }
          setRefreshSignal((n) => n + 1);
          if (lastUid) {
            // Jump to the workspace of the last successfully ingested bundle.
            setOpenBundleUid(lastUid);
          }
        }
      });
      unlisten = fn;
    })();
    return () => { unlisten?.(); };
  }, []);

  const closeBundle = () => setOpenBundleUid(null);

  if (dbError) {
    return (
      <div className="p-8 max-w-2xl">
        <h1 className="display-font text-3xl mb-2" style={{ color: '#c4252e' }}>Database failed to open</h1>
        <p className="text-sm mb-3" style={{ color: 'rgb(var(--surface-muted))' }}>
          SideMolly couldn't initialise the SQLite database. Migrations did not run.
        </p>
        <pre className="text-xs sm-card whitespace-pre-wrap">{dbError}</pre>
      </div>
    );
  }
  if (!dbReady) {
    return (
      <div className="h-full flex items-center justify-center" style={{ background: 'rgb(var(--surface-base))' }}>
        <div className="display-font text-2xl" style={{ color: 'rgb(var(--surface-accent))' }}>
          SideMolly · loading…
        </div>
      </div>
    );
  }

  return (
    <div
      className="flex h-full relative"
      style={{
        background: 'rgb(var(--surface-base))',
        outline: dragHover ? '3px dashed rgb(var(--surface-accent) / 0.6)' : 'none',
        outlineOffset: -3,
      }}
    >
      <Sidebar active={view} onSelect={(k) => { setView(k); setOpenBundleUid(null); }} visible={sidebarVisible} />
      <main className="flex-1 overflow-y-auto">
        {openBundleUid ? (
          <BundleWorkspace uid={openBundleUid} onBack={closeBundle} />
        ) : view === 'inbox' ? (
          <InboxView refreshSignal={refreshSignal} onOpen={setOpenBundleUid} />
        ) : view === 'settings' ? (
          <SettingsView />
        ) : (
          <ManualView />
        )}
      </main>

      {ingestStatus.kind !== 'idle' && (
        <IngestBanner status={ingestStatus} onDismiss={() => setIngestStatus({ kind: 'idle', message: '' })} />
      )}
    </div>
  );
}

function IngestBanner({ status, onDismiss }: { status: IngestStatus; onDismiss: () => void }) {
  const tone =
    status.kind === 'ok'    ? { bg: '#deffee', border: '#1f9d55', fg: '#0f5d33' } :
    status.kind === 'error' ? { bg: '#ffe4e4', border: '#c4252e', fg: '#7a0000' } :
                              { bg: 'rgb(var(--surface-card))', border: 'rgb(var(--surface-border))', fg: 'rgb(var(--surface-text))' };
  return (
    <div
      className="absolute bottom-6 right-6 max-w-md text-sm px-4 py-3 rounded-xl shadow-md flex items-start gap-3"
      style={{ background: tone.bg, border: `1px solid ${tone.border}`, color: tone.fg as string }}
    >
      <span className="font-semibold shrink-0">
        {status.kind === 'busy' ? '⏳' : status.kind === 'ok' ? '✓' : '⚠'}
      </span>
      <span className="flex-1 min-w-0">{status.message}</span>
      {status.kind !== 'busy' && (
        <button type="button" onClick={onDismiss} className="text-xs" style={{ color: tone.fg }}>✕</button>
      )}
    </div>
  );
}

function shortName(path: string): string {
  const last = path.split(/[/\\]/).pop() ?? path;
  return last.length > 40 ? last.slice(0, 37) + '…' : last;
}
