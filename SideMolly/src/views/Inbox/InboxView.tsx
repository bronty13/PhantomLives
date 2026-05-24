import { useState } from 'react';
import { useAsyncRefresh, listPlaceholder } from '../../lib/useAsyncRefresh';
import { listBundles, personaChipColor, bundleTypeEmoji,
         verifyStatusBadge, type BundleSummary } from '../../data/bundles';

interface Props {
  /** Tick this whenever an ingest succeeds so the list refreshes. */
  refreshSignal: number;
  onOpen: (uid: string) => void;
}

export function InboxView({ refreshSignal, onOpen }: Props) {
  const [rows, setRows] = useState<BundleSummary[]>([]);
  const { loading, error } = useAsyncRefresh(async (alive) => {
    const r = await listBundles();
    if (!alive()) return;
    setRows(r);
  }, [refreshSignal]);

  const placeholder = listPlaceholder({
    loading, error, isEmpty: rows.length === 0,
    emptyText: 'No bundles yet. Drop a Molly bundle ZIP here.',
  });

  return (
    <div className="p-8 max-w-5xl">
      <h1 className="display-font text-4xl mb-1" style={{ color: 'rgb(var(--surface-accent))' }}>
        Inbox
      </h1>
      <p className="text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
        Drop a Molly bundle ZIP anywhere on the window — SideMolly will verify it against
        its <code>hashes.json</code> and parse the manifest.
      </p>

      <div className="mt-6">
        {placeholder ? (
          <div className="sm-card">{placeholder}</div>
        ) : (
          <ul className="flex flex-col gap-2">
            {rows.map((b) => <BundleRow key={b.uid} bundle={b} onOpen={onOpen} />)}
          </ul>
        )}
      </div>
    </div>
  );
}

function BundleRow({ bundle, onOpen }: { bundle: BundleSummary; onOpen: (uid: string) => void }) {
  const chip = personaChipColor(bundle.personaCode);
  const verify = verifyStatusBadge(bundle.verifyStatus);
  return (
    <li>
      <button
        type="button"
        onClick={() => onOpen(bundle.uid)}
        className="w-full text-left sm-card flex items-center gap-4 transition hover:translate-y-[-1px]"
      >
        <div className="text-2xl shrink-0">{bundleTypeEmoji(bundle.bundleType)}</div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <span className="font-semibold truncate">{bundle.title || '(no title)'}</span>
          </div>
          <div className="mt-0.5 text-xs flex items-center gap-2" style={{ color: 'rgb(var(--surface-muted))' }}>
            <span
              className="px-1.5 py-0.5 rounded font-semibold"
              style={{ background: chip.bg, color: chip.fg }}
            >
              {chip.label}
            </span>
            <span>·</span>
            <code>{bundle.uid}</code>
            <span>·</span>
            <span>{bundle.bundleType}</span>
            <span>·</span>
            <span>{bundle.fileCount} file{bundle.fileCount === 1 ? '' : 's'}</span>
            <span>·</span>
            <span>{bundle.ingestedAt}</span>
          </div>
        </div>
        <div className="shrink-0 text-sm" style={{ color: verify.tone, fontWeight: 600 }}>
          {verify.glyph} {bundle.verifyStatus}
        </div>
      </button>
    </li>
  );
}
