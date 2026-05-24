import { useEffect, useState } from 'react';
import { useAsyncRefresh, listPlaceholder } from '../../lib/useAsyncRefresh';
import { useBundleJobs } from '../../lib/useBundleJobs';
import {
  composePostBundle, getBundle, getBundleThumbnails, getPostBundleStatus,
  personaChipColor, bundleTypeEmoji, verifyStatusBadge,
  revealPostBundle, revealWorkingDir,
  type BundleDetail, type PostBundleStatus,
} from '../../data/bundles';
import { OverviewTab } from './OverviewTab';
import { EditTab } from './EditTab';
import { DistributeTab } from './DistributeTab';
import { PostTab } from './PostTab';
import { DocDrawer, type DocKind } from './DocDrawer';

interface Props {
  uid: string;
  onBack: () => void;
  /** Bumped on every `job-updated` Tauri event so the EditTab refreshes. */
  jobSignal: number;
}

type WorkspaceTab = 'overview' | 'edit' | 'distribute' | 'post';
// Flavor-specific Post Runners (Content/Custom/FanSite) land in Phases 8-10.

export function BundleWorkspace({ uid, onBack, jobSignal }: Props) {
  const [tab, setTab] = useState<WorkspaceTab>('overview');
  const [detail, setDetail] = useState<BundleDetail | null>(null);
  const [docKind, setDocKind] = useState<DocKind | null>(null);
  // Map<inZipPath, "data:image/jpeg;base64,…"> for the Files pane.
  // Fetched in parallel with the bundle detail so it's available by
  // the time the user sees the file list.
  const [thumbs, setThumbs] = useState<Record<string, string>>({});

  const [refreshSeq, setRefreshSeq] = useState(0);
  const { loading, error } = useAsyncRefresh(async (alive) => {
    const [d, t] = await Promise.all([
      getBundle(uid),
      getBundleThumbnails(uid).catch(() => ({} as Record<string, string>)),
    ]);
    if (!alive()) return;
    setDetail(d);
    setThumbs(t);
  }, [uid, refreshSeq]);

  // Hook subscription has to run unconditionally — calling it after
  // the placeholder early-return would violate Rules of Hooks on the
  // transition from loading → loaded (caught 2026-05-24, white screen
  // on launch of v0.9.0). useBundleJobs handles empty uid by returning
  // an EMPTY snapshot.
  const jobs = useBundleJobs(uid);

  const placeholder = listPlaceholder({
    loading, error, isEmpty: detail == null, emptyText: 'Bundle not found.',
  });
  if (placeholder) {
    return (
      <div className="p-8">
        <BackBar onBack={onBack} />
        <div className="sm-card mt-4">{placeholder}</div>
      </div>
    );
  }

  const { summary, manifest, files } = detail!;
  const chip = personaChipColor(summary.personaCode);
  const verify = verifyStatusBadge(summary.verifyStatus);
  const imageCount = files.filter((f) => f.kind === 'image').length;
  const videoCount = files.filter((f) => f.kind === 'video').length;

  return (
    <div className="max-w-5xl mx-auto" style={{ position: 'relative' }}>
      {/* Sticky chrome — stays visible while the user scrolls Step 1-4
          on the Edit tab, so they always know which bundle they're in,
          where the workspace is, and what the job queue is doing. */}
      <header
        className="px-8 pt-6 pb-4"
        style={{
          position: 'sticky',
          top: 0,
          zIndex: 20,
          background: 'rgb(var(--surface-base))',
          borderBottom: '1px solid rgb(var(--surface-border))',
        }}
      >
        <div className="flex items-center justify-between">
          <BackBar onBack={onBack} />
          <SendToMollyButton uid={uid} jobs={jobs} />
        </div>

        <div className="mt-3 flex items-start gap-4">
          <div className="text-4xl">{bundleTypeEmoji(summary.bundleType)}</div>
          <div className="flex-1 min-w-0">
            <h1 className="display-font text-3xl truncate" style={{ color: 'rgb(var(--surface-accent))' }}>
              {summary.title || '(no title)'}
            </h1>
            <div className="mt-1 flex items-center gap-2 text-xs flex-wrap" style={{ color: 'rgb(var(--surface-muted))' }}>
              <span
                className="px-1.5 py-0.5 rounded font-semibold"
                style={{ background: chip.bg, color: chip.fg }}
              >
                {chip.label}
              </span>
              <span>·</span>
              <code>{summary.uid}</code>
              <span>·</span>
              <span style={{ color: verify.tone, fontWeight: 600 }}>
                {verify.glyph} {summary.verifyStatus}
              </span>
              <span>·</span>
              <span>{summary.fileCount} file{summary.fileCount === 1 ? '' : 's'}</span>
              {imageCount > 0 && <><span>·</span><span>🖼 {imageCount}</span></>}
              {videoCount > 0 && <><span>·</span><span>🎬 {videoCount}</span></>}
            </div>
            <div className="mt-2 flex items-center gap-2 text-xs">
              <span style={{ color: 'rgb(var(--surface-muted))' }}>Workspace:</span>
              <code
                className="font-mono truncate flex-1 min-w-0"
                title={`~/Library/Application Support/com.phantomlives.sidemolly/work/${summary.uid}/`}
                style={{ color: 'rgb(var(--surface-muted))' }}
              >
                …/work/{summary.uid}/
              </code>
              <button
                type="button"
                className="sm-button secondary text-xs"
                onClick={() => revealWorkingDir(summary.uid).catch(() => {})}
                title="Reveal bundle workspace in Finder"
              >
                📁 Reveal
              </button>
            </div>
          </div>
          <StatusPill jobs={jobs} />
        </div>

        <nav className="mt-4 flex gap-2 text-sm">
          <TabPill label="Overview"   icon="📄" active={tab === 'overview'} onClick={() => setTab('overview')} />
          <TabPill label="Edit"       icon="✂️" active={tab === 'edit'}     onClick={() => setTab('edit')} />
          <TabPill label="Distribute" icon="📦" active={tab === 'distribute'} onClick={() => setTab('distribute')} />
          <TabPill label="Post"       icon="🚀" active={tab === 'post'} onClick={() => setTab('post')} />
        </nav>
      </header>

      <div className="px-8 py-6">
        {tab === 'overview' && (
          <OverviewTab
            summary={summary}
            manifest={manifest}
            files={files}
            thumbs={thumbs}
            onOpenDoc={setDocKind}
          />
        )}
        {tab === 'edit' && (
          <EditTab
            summary={summary}
            files={files}
            refreshSignal={jobSignal}
            jobs={jobs}
            onFileUpdated={() => setRefreshSeq((n) => n + 1)}
          />
        )}
        {tab === 'distribute' && (
          <DistributeTab summary={summary} refreshSignal={jobSignal} />
        )}
        {tab === 'post' && (
          <PostTab summary={summary} />
        )}
      </div>

      <DocDrawer uid={summary.uid} kind={docKind} manifest={manifest} onClose={() => setDocKind(null)} />
    </div>
  );
}

function StatusPill({ jobs }: { jobs: ReturnType<typeof useBundleJobs> }) {
  const { pending, running, done, failed, busy } = jobs;
  const runningCount = running ? 1 : 0;
  const total = pending.length + runningCount + done.length + failed.length;

  if (!busy && failed.length === 0 && done.length === 0) {
    return (
      <span
        className="text-xs px-2 py-1 rounded-full font-semibold whitespace-nowrap"
        style={{
          background: 'rgb(var(--surface-card))',
          color: 'rgb(var(--surface-muted))',
          border: '1px solid rgb(var(--surface-border))',
        }}
        title="No jobs yet for this bundle"
      >
        ✓ idle
      </span>
    );
  }
  if (busy) {
    return (
      <span
        className="text-xs px-2 py-1 rounded-full font-semibold whitespace-nowrap flex items-center gap-1"
        style={{
          background: '#fff4d6',
          color: '#7a5b00',
          border: '1px solid #d4a000',
        }}
        title={running ? `Running: ${running.kind}` : 'Jobs queued'}
      >
        <span className="inline-block animate-spin">⚙️</span>
        {runningCount + pending.length} active · {done.length}/{total} done
        {failed.length > 0 && <span style={{ color: '#7a0000' }}>· ⚠ {failed.length}</span>}
      </span>
    );
  }
  if (failed.length > 0) {
    return (
      <span
        className="text-xs px-2 py-1 rounded-full font-semibold whitespace-nowrap"
        style={{ background: '#ffe4e4', color: '#7a0000', border: '1px solid #c4252e' }}
      >
        ⚠ {failed.length} failed · {done.length}/{total} done
      </span>
    );
  }
  return (
    <span
      className="text-xs px-2 py-1 rounded-full font-semibold whitespace-nowrap"
      style={{ background: '#deffee', color: '#0f5d33', border: '1px solid #0f5d33' }}
    >
      ✓ {done.length} done
    </span>
  );
}

function BackBar({ onBack }: { onBack: () => void }) {
  return (
    <button
      type="button"
      onClick={onBack}
      className="text-sm flex items-center gap-1"
      style={{ color: 'rgb(var(--surface-muted))' }}
    >
      ← Inbox
    </button>
  );
}

function TabPill({ label, icon, active, disabled, onClick }: {
  label: string; icon: string; active: boolean; disabled?: boolean;
  onClick?: () => void;
}) {
  const className = "px-3 py-1.5 rounded-lg text-sm transition";
  const style = {
    background: active ? 'rgb(var(--surface-accent) / 0.12)' : 'rgb(var(--surface-card))',
    color: active ? 'rgb(var(--surface-accent))' : disabled ? 'rgb(var(--surface-muted))' : 'rgb(var(--surface-text))',
    border: '1px solid rgb(var(--surface-border))',
    fontWeight: active ? 600 : 500,
    opacity: disabled ? 0.55 : 1,
    cursor: disabled ? 'default' : 'pointer',
  } as const;
  if (disabled || !onClick) {
    return (
      <span title={disabled ? 'Coming in a later phase' : undefined} className={className} style={style}>
        <span className="mr-1.5">{icon}</span>
        {label}
      </span>
    );
  }
  return (
    <button type="button" onClick={onClick} className={className} style={style}>
      <span className="mr-1.5">{icon}</span>
      {label}
    </button>
  );
}

/// Phase 11 — manual "📤 Send to Molly" surface in the sticky header.
/// Composes a deterministic <UID>-post.zip into ~/Downloads/Molly
/// post-bundles/, ready for Molly to ingest. Pill flips between:
///   📤 Send to Molly        (never composed)
///   ✓ Sent (size · mtime)   (composed at least once — re-compose
///                            via 🔄 button next to it)
///
/// Disables while any job for the bundle is in flight so we don't
/// snapshot a report mid-process.
function SendToMollyButton({ uid, jobs }:
  { uid: string; jobs: ReturnType<typeof useBundleJobs> }) {
  const [status, setStatus] = useState<PostBundleStatus | null>(null);
  const [busy, setBusy] = useState(false);
  const [hint, setHint] = useState<string | null>(null);

  const refresh = async () => {
    try { setStatus(await getPostBundleStatus(uid)); }
    catch { /* swallow — non-critical */ }
  };
  useEffect(() => { refresh(); /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [uid]);

  const compose = async () => {
    setBusy(true);
    setHint(null);
    try {
      const r = await composePostBundle(uid);
      setHint(`✓ ${r.targetCount} targets · ${r.artifactCount} artifacts · ${fmtKb(r.bytesWritten)}`);
      await refresh();
    } catch (e) {
      setHint(String(e));
    } finally {
      setBusy(false);
    }
  };

  const reveal = () => revealPostBundle(uid).catch((e) => alert(String(e)));

  const disabled = busy || jobs.busy;
  const label = status?.exists ? '🔄 Re-send to Molly' : '📤 Send to Molly';

  return (
    <div className="flex items-center gap-2">
      {status?.exists && (
        <button
          type="button"
          className="sm-button secondary text-xs"
          onClick={reveal}
          title={status.outputPath}
        >
          📁 ✓ Sent · {fmtKb(status.sizeBytes)}
        </button>
      )}
      <button
        type="button"
        className="sm-button text-xs"
        disabled={disabled}
        onClick={compose}
        title={
          jobs.busy ? 'Wait for the job queue to finish so the report reflects final state.' :
          status?.exists ? 'Recompose <UID>-post.zip — overwrites the existing one atomically.' :
          'Compose <UID>-post.zip into ~/Downloads/Molly post-bundles/'
        }
      >
        {busy ? '⏳ Composing…' : label}
      </button>
      {hint && (
        <span
          className="text-[10px] truncate"
          style={{ color: 'rgb(var(--surface-muted))', maxWidth: 280 }}
          title={hint}
        >
          {hint}
        </span>
      )}
    </div>
  );
}

function fmtKb(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}
