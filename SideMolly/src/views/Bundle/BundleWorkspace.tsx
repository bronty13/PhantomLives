import { useState } from 'react';
import { useAsyncRefresh, listPlaceholder } from '../../lib/useAsyncRefresh';
import { getBundle, getBundleThumbnails, personaChipColor, bundleTypeEmoji, verifyStatusBadge,
         type BundleDetail } from '../../data/bundles';
import { OverviewTab } from './OverviewTab';
import { DocDrawer, type DocKind } from './DocDrawer';

interface Props {
  uid: string;
  onBack: () => void;
}

type WorkspaceTab = 'overview';
// Edit / Distribute / Post tabs land in Phases 3-10.

export function BundleWorkspace({ uid, onBack }: Props) {
  const [tab] = useState<WorkspaceTab>('overview');
  const [detail, setDetail] = useState<BundleDetail | null>(null);
  const [docKind, setDocKind] = useState<DocKind | null>(null);
  // Map<inZipPath, "data:image/jpeg;base64,…"> for the Files pane.
  // Fetched in parallel with the bundle detail so it's available by
  // the time the user sees the file list.
  const [thumbs, setThumbs] = useState<Record<string, string>>({});

  const { loading, error } = useAsyncRefresh(async (alive) => {
    const [d, t] = await Promise.all([
      getBundle(uid),
      getBundleThumbnails(uid).catch(() => ({} as Record<string, string>)),
    ]);
    if (!alive()) return;
    setDetail(d);
    setThumbs(t);
  }, [uid]);

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

  return (
    <div className="p-8 max-w-5xl">
      <BackBar onBack={onBack} />

      <header className="mt-4 flex items-start gap-4">
        <div className="text-4xl">{bundleTypeEmoji(summary.bundleType)}</div>
        <div className="flex-1 min-w-0">
          <h1 className="display-font text-3xl truncate" style={{ color: 'rgb(var(--surface-accent))' }}>
            {summary.title || '(no title)'}
          </h1>
          <div className="mt-1 flex items-center gap-2 text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
            <span
              className="px-1.5 py-0.5 rounded font-semibold"
              style={{ background: chip.bg, color: chip.fg }}
            >
              {chip.label}
            </span>
            <span>·</span>
            <code>{summary.uid}</code>
            <span>·</span>
            <span style={{ color: verify.tone, fontWeight: 600 }}>{verify.glyph} {summary.verifyStatus}</span>
            <span>·</span>
            <span>{summary.bundleType}</span>
            <span>·</span>
            <span>{summary.fileCount} file{summary.fileCount === 1 ? '' : 's'}</span>
          </div>
        </div>
      </header>

      <nav className="mt-6 flex gap-2 text-sm">
        <TabPill label="Overview" icon="📄" active={tab === 'overview'} />
        <TabPill label="Files"      icon="📁" active={false} disabled />
        <TabPill label="Edit"       icon="✂️"  active={false} disabled />
        <TabPill label="Distribute" icon="📦" active={false} disabled />
        <TabPill label="Post"       icon="🚀" active={false} disabled />
      </nav>

      <div className="mt-4">
        {tab === 'overview' && (
          <OverviewTab
            summary={summary}
            manifest={manifest}
            files={files}
            thumbs={thumbs}
            onOpenDoc={setDocKind}
          />
        )}
      </div>

      <DocDrawer uid={summary.uid} kind={docKind} manifest={manifest} onClose={() => setDocKind(null)} />
    </div>
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

function TabPill({ label, icon, active, disabled }: {
  label: string; icon: string; active: boolean; disabled?: boolean;
}) {
  return (
    <span
      title={disabled ? 'Coming in a later phase' : undefined}
      className="px-3 py-1.5 rounded-lg text-sm"
      style={{
        background: active ? 'rgb(var(--surface-accent) / 0.12)' : 'rgb(var(--surface-card))',
        color: active ? 'rgb(var(--surface-accent))' : disabled ? 'rgb(var(--surface-muted))' : 'rgb(var(--surface-text))',
        border: '1px solid rgb(var(--surface-border))',
        fontWeight: active ? 600 : 500,
        opacity: disabled ? 0.55 : 1,
      }}
    >
      <span className="mr-1.5">{icon}</span>
      {label}
    </span>
  );
}
