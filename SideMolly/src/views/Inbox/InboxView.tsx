import { useMemo, useState, type ReactNode } from 'react';
import { useAsyncRefresh, listPlaceholder } from '../../lib/useAsyncRefresh';
import { listBundles, setBundleCompleted, deleteBundle,
         personaChipColor, bundleTypeEmoji, verifyStatusBadge,
         type BundleSummary } from '../../data/bundles';
import { applyInboxFilters, isCompleted, DEFAULT_INBOX_FILTERS,
         type InboxFilters, type StatusFilter, type SortOrder } from '../../lib/inboxFilters';

interface Props {
  /** Tick this whenever an ingest succeeds so the list refreshes. */
  refreshSignal: number;
  onOpen: (uid: string) => void;
}

const TYPE_OPTS: { value: string; label: string }[] = [
  { value: 'content', label: '🎬' },
  { value: 'custom', label: '🎁' },
  { value: 'fansite', label: '📅' },
  { value: 'youtube', label: '▶️' },
];
const PERSONA_OPTS = ['CoC', 'PoA', 'Sa'];

export function InboxView({ refreshSignal, onOpen }: Props) {
  const [rows, setRows] = useState<BundleSummary[]>([]);
  const [filters, setFilters] = useState<InboxFilters>(DEFAULT_INBOX_FILTERS);
  // Two-step delete confirm: holds the uid awaiting a Yes/Cancel.
  const [confirmDelete, setConfirmDelete] = useState<string | null>(null);
  const [busyUid, setBusyUid] = useState<string | null>(null);

  const { loading, error, refresh } = useAsyncRefresh(async (alive) => {
    const r = await listBundles();
    if (!alive()) return;
    setRows(r);
  }, [refreshSignal]);

  const visible = useMemo(() => applyInboxFilters(rows, filters), [rows, filters]);

  const set = <K extends keyof InboxFilters>(key: K, value: InboxFilters[K]) =>
    setFilters((f) => ({ ...f, [key]: value }));

  async function runAction(uid: string, fn: () => Promise<void>) {
    setBusyUid(uid);
    try {
      await fn();
      await refresh();
    } finally {
      setBusyUid(null);
      setConfirmDelete(null);
    }
  }

  const emptyText =
    filters.status === 'completed' ? 'No completed bundles yet.' :
    filters.status === 'active'    ? 'No active bundles. Drop a Molly bundle ZIP here.' :
                                     'No bundles yet. Drop a Molly bundle ZIP here.';
  const placeholder = listPlaceholder({
    loading, error, isEmpty: visible.length === 0,
    emptyText: rows.length === 0 ? 'No bundles yet. Drop a Molly bundle ZIP here.' : emptyText,
  });

  return (
    <div className="p-8 max-w-5xl">
      <h1 className="display-font text-4xl mb-1" style={{ color: 'rgb(var(--surface-accent))' }}>
        Inbox
      </h1>
      <p className="text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
        Drop a Molly bundle ZIP anywhere on the window — SideMolly will verify it against
        its <code>hashes.json</code> and parse the manifest. Mark a bundle <strong>complete</strong> to
        tuck it away once you're done.
      </p>

      {/* ── Filter toolbar ───────────────────────────────────────────── */}
      <div className="mt-5 flex flex-col gap-3">
        <div className="flex items-center gap-3 flex-wrap">
          <Segmented<StatusFilter>
            value={filters.status}
            onChange={(v) => set('status', v)}
            options={[
              { value: 'active', label: 'Active' },
              { value: 'completed', label: 'Completed' },
              { value: 'all', label: 'All' },
            ]}
          />
          <div className="flex-1" />
          <input
            type="search"
            className="sm-input w-56"
            placeholder="🔎 Search title or UID…"
            value={filters.search}
            onChange={(e) => set('search', e.target.value)}
          />
        </div>

        <div className="flex items-center gap-x-5 gap-y-2 flex-wrap text-xs"
             style={{ color: 'rgb(var(--surface-muted))' }}>
          <div className="flex items-center gap-1.5">
            <span className="font-semibold">Type</span>
            <Chip active={filters.type === 'all'} onClick={() => set('type', 'all')}>All</Chip>
            {TYPE_OPTS.map((t) => (
              <Chip key={t.value} active={filters.type === t.value}
                    onClick={() => set('type', filters.type === t.value ? 'all' : t.value)}>
                {t.label}
              </Chip>
            ))}
          </div>

          <div className="flex items-center gap-1.5">
            <span className="font-semibold">Persona</span>
            <Chip active={filters.persona === 'all'} onClick={() => set('persona', 'all')}>All</Chip>
            {PERSONA_OPTS.map((p) => (
              <Chip key={p} active={filters.persona === p}
                    onClick={() => set('persona', filters.persona === p ? 'all' : p)}>
                {p}
              </Chip>
            ))}
          </div>

          <div className="flex items-center gap-1.5">
            <span className="font-semibold">Sort</span>
            <select
              className="sm-input py-1 text-xs"
              value={filters.sort}
              onChange={(e) => set('sort', e.target.value as SortOrder)}
            >
              <option value="newest">Newest</option>
              <option value="oldest">Oldest</option>
            </select>
          </div>

          <div className="flex items-center gap-1.5">
            <span className="font-semibold">Date</span>
            <input type="date" className="sm-input py-1 text-xs" value={filters.dateFrom}
                   onChange={(e) => set('dateFrom', e.target.value)} aria-label="From date" />
            <span>–</span>
            <input type="date" className="sm-input py-1 text-xs" value={filters.dateTo}
                   onChange={(e) => set('dateTo', e.target.value)} aria-label="To date" />
          </div>

          <div className="flex-1" />
          <span className="tabular-nums">{visible.length} of {rows.length}</span>
        </div>
      </div>

      {/* ── List ─────────────────────────────────────────────────────── */}
      <div className="mt-5">
        {placeholder ? (
          <div className="sm-card">{placeholder}</div>
        ) : (
          <ul className="flex flex-col gap-2">
            {visible.map((b) => (
              <BundleRow
                key={b.uid}
                bundle={b}
                busy={busyUid === b.uid}
                confirming={confirmDelete === b.uid}
                onOpen={onOpen}
                onComplete={() => runAction(b.uid, () => setBundleCompleted(b.uid, true))}
                onReactivate={() => runAction(b.uid, () => setBundleCompleted(b.uid, false))}
                onAskDelete={() => setConfirmDelete(b.uid)}
                onCancelDelete={() => setConfirmDelete(null)}
                onConfirmDelete={() => runAction(b.uid, () => deleteBundle(b.uid))}
              />
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

// ── Small toolbar primitives ──────────────────────────────────────────

function Segmented<T extends string>({ value, onChange, options }: {
  value: T;
  onChange: (v: T) => void;
  options: { value: T; label: string }[];
}) {
  return (
    <div className="inline-flex rounded-md overflow-hidden"
         style={{ border: '1px solid rgb(var(--surface-border))' }}>
      {options.map((o, i) => (
        <button
          key={o.value}
          type="button"
          onClick={() => onChange(o.value)}
          className="px-3 py-1 text-xs"
          style={{
            background: value === o.value ? 'rgb(var(--surface-accent) / 0.12)' : 'rgb(var(--surface-card))',
            color: value === o.value ? 'rgb(var(--surface-accent))' : 'rgb(var(--surface-text))',
            fontWeight: value === o.value ? 600 : 500,
            borderRight: i !== options.length - 1 ? '1px solid rgb(var(--surface-border))' : 'none',
          }}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

function Chip({ active, onClick, children }: {
  active: boolean;
  onClick: () => void;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="px-2 py-0.5 rounded-full text-xs"
      style={{
        background: active ? 'rgb(var(--surface-accent) / 0.12)' : 'rgb(var(--surface-card))',
        color: active ? 'rgb(var(--surface-accent))' : 'rgb(var(--surface-text))',
        border: '1px solid rgb(var(--surface-border))',
        fontWeight: active ? 600 : 500,
      }}
    >
      {children}
    </button>
  );
}

// ── Row ───────────────────────────────────────────────────────────────

interface RowProps {
  bundle: BundleSummary;
  busy: boolean;
  confirming: boolean;
  onOpen: (uid: string) => void;
  onComplete: () => void;
  onReactivate: () => void;
  onAskDelete: () => void;
  onCancelDelete: () => void;
  onConfirmDelete: () => void;
}

function BundleRow({
  bundle, busy, confirming, onOpen,
  onComplete, onReactivate, onAskDelete, onCancelDelete, onConfirmDelete,
}: RowProps) {
  const chip = personaChipColor(bundle.personaCode);
  const verify = verifyStatusBadge(bundle.verifyStatus);
  const done = isCompleted(bundle);

  return (
    <li className="sm-card flex items-center gap-3" style={{ opacity: busy ? 0.6 : 1 }}>
      {/* Clickable main area — opens the workspace, as before. */}
      <button
        type="button"
        onClick={() => onOpen(bundle.uid)}
        className="flex-1 min-w-0 text-left flex items-center gap-4 transition hover:translate-y-[-1px]"
      >
        <div className="text-2xl shrink-0">{bundleTypeEmoji(bundle.bundleType)}</div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <span className="font-semibold truncate">{bundle.title || '(no title)'}</span>
          </div>
          <div className="mt-0.5 text-xs flex items-center gap-2 flex-wrap"
               style={{ color: 'rgb(var(--surface-muted))' }}>
            <span className="px-1.5 py-0.5 rounded font-semibold"
                  style={{ background: chip.bg, color: chip.fg }}>{chip.label}</span>
            <span>·</span>
            <code>{bundle.uid}</code>
            <span>·</span>
            <span>{bundle.bundleType}</span>
            <span>·</span>
            <span>{bundle.fileCount} file{bundle.fileCount === 1 ? '' : 's'}</span>
            <span>·</span>
            <span>{bundle.ingestedAt}</span>
            {done && bundle.completedAt && (
              <>
                <span>·</span>
                <span style={{ color: '#1f9d55', fontWeight: 600 }}>
                  ✓ Completed {bundle.completedAt.slice(0, 10)}
                </span>
              </>
            )}
          </div>
        </div>
        <div className="shrink-0 text-sm" style={{ color: verify.tone, fontWeight: 600 }}>
          {verify.glyph} {bundle.verifyStatus}
        </div>
      </button>

      {/* Action cluster — siblings of the open button, so no click bleed. */}
      <div className="shrink-0 flex items-center gap-2">
        {confirming ? (
          <>
            <span className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Delete?</span>
            <button type="button" disabled={busy} onClick={onConfirmDelete}
                    className="sm-button danger text-xs">Yes</button>
            <button type="button" disabled={busy} onClick={onCancelDelete}
                    className="sm-button secondary text-xs">Cancel</button>
          </>
        ) : done ? (
          <>
            <button type="button" disabled={busy} onClick={onReactivate}
                    className="sm-button secondary text-xs">↩ Reactivate</button>
            <button type="button" disabled={busy} onClick={onAskDelete}
                    className="sm-button danger text-xs" title="Delete bundle">🗑</button>
          </>
        ) : (
          <>
            <button type="button" disabled={busy} onClick={onComplete}
                    className="sm-button secondary text-xs">✓ Complete</button>
            <button type="button" disabled={busy} onClick={onAskDelete}
                    className="sm-button secondary text-xs" title="Delete bundle"
                    style={{ color: '#d94a6a' }}>🗑</button>
          </>
        )}
      </div>
    </li>
  );
}
