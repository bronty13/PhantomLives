// Phase 12 — global Jobs panel.
//
// Cross-bundle queue view with operational controls:
//   - Pause / Resume the worker (writes app_settings.jobs_paused)
//   - Retry failed jobs
//   - Cancel pending jobs
//   - Bulk Clear done / failed
//   - Status filter pills (existing) + kind filter chip (new)
//   - Per-job expand: pretty-printed params + log entries scoped to job_id
//
// Subscribes to `job-updated` events so the list and counts stay in
// sync with the worker without manual refresh.

import { useCallback, useEffect, useMemo, useState } from 'react';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import {
  cancelPendingJob, clearJobsByStatus, getWorkerPaused, listJobs,
  listLogEntries, retryJob, revealJobOutput, setWorkerPaused,
  type JobRow, type JobStatus, type LogRow,
} from '../../data/bundles';

type StatusFilter = 'all' | JobStatus;

const STATUS_FILTERS: { key: StatusFilter; label: string; glyph: string }[] = [
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
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [kindFilter, setKindFilter] = useState<string>('all');
  const [rows, setRows] = useState<JobRow[]>([]);
  const [paused, setPaused] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async () => {
    try {
      const [r, p] = await Promise.all([
        listJobs(statusFilter === 'all' ? undefined : statusFilter),
        getWorkerPaused(),
      ]);
      setRows(r);
      setPaused(p);
      setError(null);
    } catch (e) { setError(String(e)); }
  }, [statusFilter]);

  // Initial + filter changes + job-updated events.
  useEffect(() => { refresh(); }, [refresh, refreshSignal]);
  useEffect(() => {
    let alive = true;
    let unlisten: UnlistenFn | undefined;
    (async () => {
      unlisten = await listen<unknown>('job-updated', () => {
        if (alive) refresh();
      });
    })();
    return () => { alive = false; unlisten?.(); };
  }, [refresh]);

  const allKinds = useMemo(() => {
    const set = new Set<string>();
    for (const r of rows) set.add(r.kind);
    return ['all', ...Array.from(set).sort()];
  }, [rows]);

  const visible = useMemo(
    () => kindFilter === 'all' ? rows : rows.filter((r) => r.kind === kindFilter),
    [rows, kindFilter],
  );

  const counts = useMemo(() => countByStatus(rows), [rows]);

  const togglePause = async () => {
    setBusy(true);
    try { await setWorkerPaused(!paused); await refresh(); }
    catch (e) { setError(String(e)); }
    finally { setBusy(false); }
  };

  const clearDone = async () => {
    if (!confirm(`Clear ${counts.done ?? 0} done job${(counts.done ?? 0) === 1 ? '' : 's'}?`)) return;
    setBusy(true);
    try { await clearJobsByStatus(['done']); await refresh(); }
    catch (e) { setError(String(e)); }
    finally { setBusy(false); }
  };

  const clearFailed = async () => {
    if (!confirm(`Clear ${counts.failed ?? 0} failed job${(counts.failed ?? 0) === 1 ? '' : 's'}?`)) return;
    setBusy(true);
    try { await clearJobsByStatus(['failed']); await refresh(); }
    catch (e) { setError(String(e)); }
    finally { setBusy(false); }
  };

  return (
    <div className="p-8 max-w-5xl">
      <div className="flex items-baseline justify-between gap-3 mb-1">
        <h1 className="display-font text-4xl" style={{ color: 'rgb(var(--surface-accent))' }}>
          Jobs
        </h1>
        <div className="flex items-center gap-2">
          <button
            type="button"
            className="sm-button text-sm"
            disabled={busy}
            onClick={togglePause}
            style={paused ? { background: '#fff4d6', color: '#7a5b00', border: '1px solid #d4a000' } : undefined}
            title={paused ? 'Worker is paused — claims no new jobs. Click to resume.' : 'Pause the worker. Currently-running job finishes; queue stops claiming new ones.'}
          >
            {paused ? '▶ Resume worker' : '⏸ Pause worker'}
          </button>
        </div>
      </div>

      <p className="text-sm mb-4" style={{ color: 'rgb(var(--surface-muted))' }}>
        Background queue. One worker, polls every 2s. Dispatches
        process_video / render_title / normalize_video / assemble_master
        / transcribe_video by kind.
        {paused && <span style={{ color: '#7a5b00' }}> · ⏸ paused</span>}
      </p>

      {/* Status filter pills */}
      <div className="flex gap-2 mb-3 flex-wrap">
        {STATUS_FILTERS.map((f) => (
          <button
            key={f.key}
            type="button"
            onClick={() => setStatusFilter(f.key)}
            className="px-3 py-1.5 rounded-lg text-sm transition"
            style={{
              background: statusFilter === f.key ? 'rgb(var(--surface-accent) / 0.12)' : 'rgb(var(--surface-card))',
              color: statusFilter === f.key ? 'rgb(var(--surface-accent))' : 'rgb(var(--surface-text))',
              border: '1px solid rgb(var(--surface-border))',
              fontWeight: statusFilter === f.key ? 600 : 500,
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

      {/* Kind filter + clear bulk */}
      <div className="flex flex-wrap items-center gap-2 mb-4 text-sm">
        <span className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Kind:</span>
        <select
          className="sm-input text-xs"
          style={{ width: 'auto' }}
          value={kindFilter}
          onChange={(e) => setKindFilter(e.target.value)}
        >
          {allKinds.map((k) => <option key={k} value={k}>{k}</option>)}
        </select>
        <div className="flex-1" />
        <button
          type="button"
          className="sm-button secondary text-xs"
          disabled={busy || !counts.done}
          onClick={clearDone}
          title="Bulk-delete every done row"
        >
          🗑 Clear done ({counts.done ?? 0})
        </button>
        <button
          type="button"
          className="sm-button secondary text-xs"
          disabled={busy || !counts.failed}
          onClick={clearFailed}
          title="Bulk-delete every failed row"
          style={counts.failed ? { color: '#7a0000' } : undefined}
        >
          🗑 Clear failed ({counts.failed ?? 0})
        </button>
      </div>

      {error && (
        <div className="sm-card text-sm" style={{ color: '#c4252e', background: '#ffe4e4' }}>
          {error}
        </div>
      )}

      {visible.length === 0 ? (
        <div className="sm-card text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
          No jobs match this filter.
        </div>
      ) : (
        <ul className="flex flex-col gap-1.5">
          {visible.map((r) => <JobRowEl key={r.id} row={r} onChange={refresh} />)}
        </ul>
      )}
    </div>
  );
}

function JobRowEl({ row, onChange }: { row: JobRow; onChange: () => void }) {
  const [open, setOpen] = useState(false);
  const sp = statusPill(row.status);
  const canReveal = row.status === 'done' && (
    row.kind === 'process_video' || row.kind === 'render_title' ||
    row.kind === 'normalize_video' || row.kind === 'assemble_master' ||
    row.kind === 'transcribe_video'
  );

  const reveal = () => revealJobOutput(row.id).catch((err) => alert(String(err)));

  const doRetry = async () => {
    try { await retryJob(row.id); onChange(); }
    catch (e) { alert(String(e)); }
  };

  const doCancel = async () => {
    if (!confirm(`Cancel pending job #${row.id} (${row.kind})?`)) return;
    try { await cancelPendingJob(row.id); onChange(); }
    catch (e) { alert(String(e)); }
  };

  return (
    <li className="sm-card text-sm">
      <div className="flex items-center gap-3">
        <span
          className="shrink-0 px-2 py-0.5 rounded text-xs font-semibold"
          style={{ background: sp.bg, color: sp.fg, minWidth: 64, textAlign: 'center' }}
        >
          {sp.glyph} {row.status}
        </span>
        <span className="font-semibold whitespace-nowrap">{row.kind}</span>
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
        <span className="shrink-0 text-xs ml-auto whitespace-nowrap" style={{ color: 'rgb(var(--surface-muted))' }}>
          {row.updatedAt}
        </span>
        {canReveal && (
          <button
            type="button"
            onClick={(e) => { e.stopPropagation(); reveal(); }}
            className="shrink-0 text-xs px-2 py-0.5 rounded ml-1"
            style={{
              color: 'rgb(var(--surface-accent))',
              border: '1px solid rgb(var(--surface-border))',
              background: 'rgb(var(--surface-card))',
            }}
            title="Reveal processed output in Finder"
          >
            📁
          </button>
        )}
        {row.status === 'failed' && (
          <button
            type="button"
            onClick={(e) => { e.stopPropagation(); doRetry(); }}
            className="shrink-0 text-xs px-2 py-0.5 rounded ml-1"
            style={{
              color: '#7a5b00',
              border: '1px solid #d4a000',
              background: '#fff4d6',
            }}
            title="Retry — flips status back to pending"
          >
            🔄 Retry
          </button>
        )}
        {row.status === 'pending' && (
          <button
            type="button"
            onClick={(e) => { e.stopPropagation(); doCancel(); }}
            className="shrink-0 text-xs px-2 py-0.5 rounded ml-1"
            style={{
              color: '#7a0000',
              border: '1px solid rgb(var(--surface-border))',
              background: 'rgb(var(--surface-card))',
            }}
            title="Cancel — deletes the pending row"
          >
            ✕
          </button>
        )}
        <button
          type="button"
          onClick={() => setOpen((v) => !v)}
          className="shrink-0 text-xs ml-1"
          style={{ color: 'rgb(var(--surface-muted))' }}
        >
          {open ? '▾' : '▸'}
        </button>
      </div>
      {open && <JobDetail row={row} />}
    </li>
  );
}

function JobDetail({ row }: { row: JobRow }) {
  const [logs, setLogs] = useState<LogRow[] | null>(null);

  useEffect(() => {
    let alive = true;
    // Pull the log entries scoped to this bundle, then filter by
    // job_id in JS. listLogEntries doesn't have a job-id-direct
    // filter — adding one later if this gets sluggish on long histories.
    (async () => {
      try {
        const all = row.bundleUid ? await listLogEntries(row.bundleUid, 500) : [];
        if (!alive) return;
        setLogs(all.filter((l) => l.jobId === row.id));
      } catch {
        if (alive) setLogs([]);
      }
    })();
    return () => { alive = false; };
  }, [row.id, row.bundleUid]);

  const prettyParams = useMemo(() => {
    try { return JSON.stringify(JSON.parse(row.paramsJson), null, 2); }
    catch { return row.paramsJson; }
  }, [row.paramsJson]);

  return (
    <div className="mt-2 grid grid-cols-1 lg:grid-cols-[1fr_1fr] gap-3">
      <div>
        <div className="text-[10px] font-semibold mb-1" style={{ color: 'rgb(var(--surface-muted))' }}>
          Params
        </div>
        <pre
          className="font-mono text-[10px] p-2 rounded overflow-auto"
          style={{
            background: 'rgb(var(--surface-base))',
            border: '1px solid rgb(var(--surface-border))',
            maxHeight: 240,
          }}
        >{prettyParams}</pre>
        <div className="text-[10px] mt-1" style={{ color: 'rgb(var(--surface-muted))' }}>
          id #{row.id} · {row.attempts} attempt{row.attempts === 1 ? '' : 's'} · created {row.createdAt}
        </div>
      </div>
      <div>
        <div className="text-[10px] font-semibold mb-1" style={{ color: 'rgb(var(--surface-muted))' }}>
          Log entries ({logs?.length ?? '…'})
        </div>
        {logs == null ? (
          <div className="text-[11px] italic" style={{ color: 'rgb(var(--surface-muted))' }}>Loading…</div>
        ) : logs.length === 0 ? (
          <div className="text-[11px] italic" style={{ color: 'rgb(var(--surface-muted))' }}>
            No log entries for this job.
          </div>
        ) : (
          <div
            className="font-mono text-[10px] p-2 rounded overflow-auto"
            style={{
              background: 'rgb(var(--surface-base))',
              border: '1px solid rgb(var(--surface-border))',
              maxHeight: 240,
            }}
          >
            {logs.map((l) => (
              <div key={l.id} className="flex gap-2 py-0.5">
                <span style={{ color: 'rgb(var(--surface-muted))', minWidth: 140 }}>{l.timestamp}</span>
                <span style={levelColor(l.level)} className="font-semibold" >{l.level}</span>
                <span className="flex-1 truncate" title={l.message}>{l.message}</span>
              </div>
            ))}
            {row.lastError && (
              <pre
                className="whitespace-pre-wrap mt-2 pt-2"
                style={{ color: '#c4252e', borderTop: '1px solid rgb(var(--surface-border))' }}
              >
                {row.lastError}
              </pre>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

function levelColor(level: 'info' | 'warn' | 'error'): React.CSSProperties {
  switch (level) {
    case 'info':  return { color: 'rgb(var(--surface-accent))', minWidth: 40 };
    case 'warn':  return { color: '#7a5b00', minWidth: 40 };
    case 'error': return { color: '#7a0000', minWidth: 40 };
  }
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
