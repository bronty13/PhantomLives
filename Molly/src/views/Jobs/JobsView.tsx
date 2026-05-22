import { useCallback, useEffect, useState } from 'react';
import {
  type BackgroundJob,
  type BackgroundJobRun,
  listBackgroundJobs,
  listJobRuns,
  openRunLog,
  revealRunLog,
  runJobNow,
  setJobEnabled,
} from '../../data/backgroundJobs';

/** 🌀 Jobs sidebar entry. Lists registered background jobs + their
 * recent run history. v1 only has 'atw_repost'; future job kinds slot
 * in here too. */
export function JobsView() {
  const [jobs, setJobs] = useState<BackgroundJob[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      setJobs(await listBackgroundJobs());
    } catch (e) {
      setError(String((e as { message?: string })?.message ?? e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
    // Re-poll every 30s while the view is open so status pills update
    // as scheduled runs finish in the background.
    const id = window.setInterval(refresh, 30_000);
    return () => window.clearInterval(id);
  }, [refresh]);

  return (
    <div className="p-8 space-y-4 max-w-4xl">
      <header className="space-y-1">
        <h2 className="display-font text-2xl font-bold persona-accent">🌀 Jobs</h2>
        <p className="opacity-70 text-sm">
          Background tasks Molly runs on a schedule. Currently only the ATW Repost bot.
          Configure cadence + credentials in <strong>Settings → 🌀 ATW Repost</strong>.
        </p>
      </header>
      {error && (
        <div className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2">{error}</div>
      )}
      {loading && <div className="opacity-60 italic">Loading jobs…</div>}
      {!loading && jobs.length === 0 && (
        <div className="pretty-card text-sm opacity-70">
          No jobs registered yet. Configure the ATW bot in Settings → 🌀 ATW Repost to register it.
        </div>
      )}
      {jobs.map((job) => (
        <JobCard key={job.id} job={job} onChanged={refresh} />
      ))}
    </div>
  );
}

function JobCard({ job, onChanged }: { job: BackgroundJob; onChanged: () => Promise<void> }) {
  const [runs, setRuns] = useState<BackgroundJobRun[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refreshRuns = useCallback(async () => {
    try { setRuns(await listJobRuns(job.id, 20)); }
    catch (e) { setError(String((e as { message?: string })?.message ?? e)); }
  }, [job.id]);

  useEffect(() => { refreshRuns(); }, [refreshRuns]);

  async function toggleEnabled() {
    setBusy(true); setError(null);
    try { await setJobEnabled(job.id, !job.enabled); await onChanged(); }
    catch (e) { setError(String((e as { message?: string })?.message ?? e)); }
    finally { setBusy(false); }
  }
  async function runNow() {
    setBusy(true); setError(null);
    try { await runJobNow(job.id); await refreshRuns(); await onChanged(); }
    catch (e) { setError(String((e as { message?: string })?.message ?? e)); }
    finally { setBusy(false); }
  }

  return (
    <div className="pretty-card space-y-3">
      <div className="flex items-baseline justify-between gap-3">
        <div>
          <div className="font-semibold text-lg">{job.name}</div>
          <div className="text-xs opacity-60 font-mono">
            kind: {job.kind} · cadence: {fmtSeconds(job.cadenceSeconds)}
            {job.nextRunAt && ` · next: ${job.nextRunAt}`}
          </div>
        </div>
        <div className="flex gap-2">
          <button type="button" onClick={runNow} disabled={busy} className="pretty-button">
            ▶️ Run now
          </button>
          <button type="button" onClick={toggleEnabled} disabled={busy} className={`pretty-button ${job.enabled ? 'danger' : ''}`}>
            {job.enabled ? '⏸ Disable' : '▶️ Enable'}
          </button>
        </div>
      </div>
      {error && <div className="text-xs text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2">{error}</div>}
      <div className="space-y-1">
        <h4 className="text-xs font-semibold opacity-60 uppercase tracking-wider">Recent runs</h4>
        {runs.length === 0 ? (
          <div className="text-xs opacity-60 italic">No runs yet — click "Run now" above to fire one.</div>
        ) : (
          <ul className="space-y-1">
            {runs.map((r) => (
              <RunRow key={r.id} run={r} />
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

function RunRow({ run }: { run: BackgroundJobRun }) {
  const [open, setOpen] = useState(false);
  const [logError, setLogError] = useState<string | null>(null);
  const pillStyle = (() => {
    switch (run.status) {
      case 'success': return { bg: '#DCFCE7', color: '#166534', label: '✓ success' };
      case 'failed': return { bg: '#FEE2E2', color: '#991B1B', label: '✗ failed' };
      case 'running': return { bg: '#FEF3C7', color: '#92400E', label: '… running' };
      default: return { bg: '#E5E7EB', color: '#374151', label: run.status };
    }
  })();
  async function doOpenLog(e: React.MouseEvent) {
    e.stopPropagation();
    setLogError(null);
    try { await openRunLog(run.id); }
    catch (err) { setLogError(String((err as { message?: string })?.message ?? err)); }
  }
  async function doRevealLog(e: React.MouseEvent) {
    e.stopPropagation();
    setLogError(null);
    try { await revealRunLog(run.id); }
    catch (err) { setLogError(String((err as { message?: string })?.message ?? err)); }
  }
  return (
    <li className="text-sm">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="w-full flex items-baseline gap-2 px-2 py-1 rounded-xl hover:bg-black/5 text-left"
      >
        <span
          className="text-[10px] font-mono px-1.5 py-0.5 rounded-full"
          style={{ background: pillStyle.bg, color: pillStyle.color, minWidth: 70, textAlign: 'center' }}
        >
          {pillStyle.label}
        </span>
        <span className="font-mono text-xs opacity-60 w-44">{run.startedAt}</span>
        <span className="flex-1 truncate">{run.summary || '(no summary)'}</span>
        {(run.logExcerpt || run.logPath) && (
          <span className="opacity-50 text-xs">{open ? '▾' : '▸'}</span>
        )}
      </button>
      {open && (
        <div className="space-y-2 mt-1">
          {run.logPath && (
            <div className="flex items-center gap-2 px-2">
              <button
                type="button"
                onClick={doOpenLog}
                className="pretty-button secondary text-xs"
              >
                📄 Open full log
              </button>
              <button
                type="button"
                onClick={doRevealLog}
                className="pretty-button secondary text-xs"
              >
                📂 Reveal in Finder
              </button>
              <span className="text-[10px] font-mono opacity-50 truncate flex-1">{run.logPath}</span>
            </div>
          )}
          {logError && (
            <div className="text-xs text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-1 mx-2">
              {logError}
            </div>
          )}
          {run.logExcerpt && (
            <pre className="text-[10px] font-mono bg-black/5 rounded-xl p-2 max-h-72 overflow-auto whitespace-pre-wrap">
              {run.logExcerpt}
            </pre>
          )}
          {!run.logExcerpt && !run.logPath && (
            <div className="text-xs italic opacity-60 px-2">No log captured for this run.</div>
          )}
        </div>
      )}
    </li>
  );
}

function fmtSeconds(s: number): string {
  if (s % 3600 === 0) return `${s / 3600}h`;
  if (s % 60 === 0) return `${s / 60}m`;
  return `${s}s`;
}
