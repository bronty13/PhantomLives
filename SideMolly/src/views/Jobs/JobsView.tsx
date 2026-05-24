import { useEffect, useState } from 'react';
import { listJobs, type JobRow, type JobStatus } from '../../data/bundles';

type FilterKey = 'all' | JobStatus;

const FILTERS: { key: FilterKey; label: string; glyph: string }[] = [
  { key: 'all',     label: 'All',     glyph: '·' },
  { key: 'pending', label: 'Pending', glyph: '⏳' },
  { key: 'running', label: 'Running', glyph: '⚙️' },
  { key: 'done',    label: 'Done',    glyph: '✓' },
  { key: 'failed',  label: 'Failed',  glyph: '⚠' },
];

interface Props {
  refreshSignal: number;
}

export function JobsView({ refreshSignal }: Props) {
  const [filter, setFilter] = useState<FilterKey>('all');
  const [rows, setRows] = useState<JobRow[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const r = await listJobs(filter === 'all' ? undefined : filter);
        if (alive) { setRows(r); setError(null); }
      } catch (e) {
        if (alive) setError(String(e));
      }
    })();
    return () => { alive = false; };
  }, [filter, refreshSignal]);

  const counts = countByStatus(rows);

  return (
    <div className="p-8 max-w-5xl">
      <h1 className="display-font text-4xl mb-1" style={{ color: 'rgb(var(--surface-accent))' }}>
        Jobs
      </h1>
      <p className="text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
        Background queue (Phase 4). One worker, polls every 2s. Currently dispatches
        video transcoding from the Bundle workspace → Edit tab.
      </p>

      <div className="flex gap-2 mt-5 mb-4 flex-wrap">
        {FILTERS.map((f) => (
          <button
            key={f.key}
            type="button"
            onClick={() => setFilter(f.key)}
            className="px-3 py-1.5 rounded-lg text-sm transition"
            style={{
              background: filter === f.key ? 'rgb(var(--surface-accent) / 0.12)' : 'rgb(var(--surface-card))',
              color: filter === f.key ? 'rgb(var(--surface-accent))' : 'rgb(var(--surface-text))',
              border: '1px solid rgb(var(--surface-border))',
              fontWeight: filter === f.key ? 600 : 500,
            }}
          >
            <span className="mr-1.5">{f.glyph}</span>
            {f.label}
            {f.key !== 'all' && counts[f.key] != null && (
              <span className="ml-1.5 text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
                {counts[f.key]}
              </span>
            )}
          </button>
        ))}
      </div>

      {error && (
        <div className="sm-card text-sm" style={{ color: '#c4252e', background: '#ffe4e4' }}>
          {error}
        </div>
      )}

      {rows.length === 0 ? (
        <div className="sm-card text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
          No jobs match this filter.
        </div>
      ) : (
        <ul className="flex flex-col gap-1.5">
          {rows.map((r) => <JobRowEl key={r.id} row={r} />)}
        </ul>
      )}
    </div>
  );
}

function JobRowEl({ row }: { row: JobRow }) {
  const [open, setOpen] = useState(false);
  const sp = statusPill(row.status);
  const has_error = row.status === 'failed' && row.lastError;

  return (
    <li className="sm-card text-sm">
      <div className="flex items-center gap-3">
        <span
          className="shrink-0 px-2 py-0.5 rounded text-xs font-semibold"
          style={{ background: sp.bg, color: sp.fg }}
        >
          {sp.glyph} {row.status}
        </span>
        <span className="font-semibold">{row.kind}</span>
        {row.bundleUid && (
          <code className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
            {row.bundleUid}
          </code>
        )}
        {row.sourceInZipPath && (
          <span className="font-mono text-xs truncate flex-1" style={{ color: 'rgb(var(--surface-muted))' }}>
            {row.sourceInZipPath}
          </span>
        )}
        <span className="shrink-0 text-xs ml-auto" style={{ color: 'rgb(var(--surface-muted))' }}>
          {row.updatedAt}
        </span>
        {(has_error || row.attempts > 1) && (
          <button
            type="button"
            onClick={() => setOpen((v) => !v)}
            className="shrink-0 text-xs ml-1"
            style={{ color: 'rgb(var(--surface-muted))' }}
          >
            {open ? '▾' : '▸'}
          </button>
        )}
      </div>
      {open && (
        <div className="mt-2 text-xs font-mono pl-2" style={{ color: 'rgb(var(--surface-muted))' }}>
          {row.attempts > 1 && <div>attempts: {row.attempts}</div>}
          {row.lastError && (
            <pre className="whitespace-pre-wrap" style={{ color: '#c4252e' }}>{row.lastError}</pre>
          )}
        </div>
      )}
    </li>
  );
}

function countByStatus(rows: JobRow[]): Record<JobStatus, number> {
  const c: Record<JobStatus, number> = { pending: 0, running: 0, done: 0, failed: 0 };
  for (const r of rows) c[r.status]++;
  return c;
}

function statusPill(s: JobStatus): { glyph: string; bg: string; fg: string } {
  switch (s) {
    case 'pending': return { glyph: '⏳', bg: 'rgb(var(--surface-base))', fg: 'rgb(var(--surface-muted))' };
    case 'running': return { glyph: '⚙️', bg: '#fff4d6',                  fg: '#7a5b00' };
    case 'done':    return { glyph: '✓',  bg: '#deffee',                  fg: '#0f5d33' };
    case 'failed':  return { glyph: '⚠',  bg: '#ffe4e4',                  fg: '#7a0000' };
  }
}
