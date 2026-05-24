// Subscribe to the running list of jobs for a single bundle. Used by
// BundleWorkspace's sticky header (always-on status pill) and EditTab's
// per-step inline queue widgets. Refetches on every `job-updated`
// Tauri event so the UI tracks the worker in real time without
// requiring the user to switch to the Jobs tab.
//
// The fetch is cheap (one IPC + one SQLite SELECT) and the queue per
// bundle is small (rarely >50 rows during a single bundle's life
// cycle), so we client-side-filter from listJobs() instead of adding
// a dedicated `list_bundle_jobs(uid)` command. If queue sizes grow we
// can swap the implementation here without touching consumers.

import { useEffect, useState } from 'react';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import { listJobs, type JobRow } from '../data/bundles';

export interface BundleJobsSnapshot {
  /** All jobs scoped to the bundle, newest first. */
  all: JobRow[];
  /** Jobs in `pending` status — waiting on the worker. */
  pending: JobRow[];
  /** The single job currently `running`, or `null`. The worker is
   *  strictly sequential so there's at most one. */
  running: JobRow | null;
  /** Jobs in `done` status, newest first. */
  done: JobRow[];
  /** Jobs in `failed` status, newest first. */
  failed: JobRow[];
  /** Convenience: are there any pending or running jobs? Drives the
   *  "⚡ N running" vs "✓ idle" status pill. */
  busy: boolean;
}

const EMPTY: BundleJobsSnapshot = {
  all: [], pending: [], running: null, done: [], failed: [], busy: false,
};

export function useBundleJobs(uid: string): BundleJobsSnapshot {
  const [snap, setSnap] = useState<BundleJobsSnapshot>(EMPTY);

  useEffect(() => {
    let alive = true;
    let unlisten: UnlistenFn | undefined;
    let pollTimer: ReturnType<typeof setInterval> | undefined;

    const refresh = async () => {
      try {
        const all = await listJobs();
        if (!alive) return;
        const mine = all
          .filter((j) => j.bundleUid === uid)
          .sort((a, b) => b.id - a.id);
        setSnap({
          all: mine,
          pending: mine.filter((j) => j.status === 'pending'),
          running: mine.find((j) => j.status === 'running') ?? null,
          done: mine.filter((j) => j.status === 'done'),
          failed: mine.filter((j) => j.status === 'failed'),
          busy: mine.some((j) => j.status === 'pending' || j.status === 'running'),
        });
      } catch (e) {
        console.warn('useBundleJobs refresh failed', e);
      }
    };

    refresh();
    // Tauri emits `job-updated` on every status transition. Plus a
    // 3s safety poll in case an event is missed during a rapid burst
    // (the worker batches status writes inside dispatch hot loops).
    (async () => {
      unlisten = await listen<unknown>('job-updated', () => { refresh(); });
    })();
    pollTimer = setInterval(refresh, 3000);

    return () => {
      alive = false;
      unlisten?.();
      if (pollTimer) clearInterval(pollTimer);
    };
  }, [uid]);

  return snap;
}
