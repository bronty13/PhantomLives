/**
 * @file scanController.ts — owns the scan workers and the in-memory trees.
 *
 * The authoritative scanned tree lives here in the main process (never shipped
 * whole to the renderer — see the slice queries below). Spawns a fresh worker
 * per operation, forwards throttled progress to the renderer, stores the
 * finalized Tree keyed by scanId, and cancels cooperatively via an Atomics
 * flag on a SharedArrayBuffer.
 */
import { Worker } from 'node:worker_threads';
import { join } from 'node:path';
import type { ScanEvent, SerializedTree } from '../../shared/protocol';
import type {
  ScanOptions,
  ScanStats,
  SortSpec,
  FileFilter,
  NodeRow,
  RectNode
} from '../../shared/types';
import { Tree } from './tree';
import { computeTreemap } from './treemap';
import { writeSnapshot, readSnapshot } from './snapshot';

type Sender = (channel: string, payload: unknown) => void;

let sender: Sender = () => {};
export function initController(s: Sender): void {
  sender = s;
}

const EXPORT_CAP = 50_000;

const trees = new Map<string, Tree>();
// The Tree's typed arrays are *views* over these buffers (no copy), so keeping
// the SerializedTree around for snapshot-saving costs nothing extra.
const serialized = new Map<string, SerializedTree>();
const stats = new Map<string, ScanStats>();
interface ActiveOp {
  worker: Worker;
  cancel: Int32Array;
  cancelTimer?: ReturnType<typeof setTimeout>;
}
const active = new Map<string, ActiveOp>();

/** Grace period before a cooperative cancel escalates to a hard terminate. */
const CANCEL_GRACE_MS = 800;

/**
 * Cancel an operation: set the cooperative flag (clean partial result if the
 * worker is between syscalls), then hard-terminate after a grace period if it
 * hasn't stopped — the worker uses *synchronous* fs, so a slow/hung syscall
 * (e.g. a network/cloud mount) would otherwise ignore the flag indefinitely.
 */
function cancelOp(key: string, cancelledChannel: string, scanId: string): void {
  const op = active.get(key);
  if (!op || op.cancelTimer) return;
  Atomics.store(op.cancel, 0, 1);
  op.cancelTimer = setTimeout(() => {
    if (active.get(key) === op) {
      void op.worker.terminate();
      active.delete(key);
      sender(cancelledChannel, { scanId });
    }
  }, CANCEL_GRACE_MS);
}

function clearOp(key: string): void {
  const op = active.get(key);
  if (op?.cancelTimer) clearTimeout(op.cancelTimer);
  active.delete(key);
}
let counter = 0;

function newScanId(): string {
  return `scan-${Date.now()}-${++counter}`;
}

function workerPath(): string {
  // Both main/index.js and main/scanWorker.js are emitted under out/main.
  return join(__dirname, 'scanWorker.js');
}

function spawn(): { worker: Worker; cancel: Int32Array; sab: SharedArrayBuffer } {
  const sab = new SharedArrayBuffer(4);
  const cancel = new Int32Array(sab);
  const worker = new Worker(workerPath());
  return { worker, cancel, sab };
}

/** Begin a scan; returns the scanId immediately (progress arrives via events). */
export function startScan(rootPath: string, opts: ScanOptions): string {
  const scanId = newScanId();
  const { worker, cancel, sab } = spawn();
  const startMs = Date.now();
  active.set(scanId, { worker, cancel });

  worker.on('message', (evt: ScanEvent) => {
    switch (evt.type) {
      case 'progress':
        sender('purpletree:scan-progress', evt.progress);
        break;
      case 'done': {
        const tree = new Tree(evt.tree);
        trees.set(scanId, tree);
        serialized.set(scanId, evt.tree);
        const s: ScanStats = { ...evt.stats, durationMs: Date.now() - startMs };
        stats.set(scanId, s);
        sender('purpletree:scan-complete', s);
        clearOp(scanId);
        void worker.terminate();
        break;
      }
      case 'error':
        sender('purpletree:scan-error', { scanId, message: evt.message });
        clearOp(scanId);
        void worker.terminate();
        break;
    }
  });
  worker.on('error', (err) => {
    sender('purpletree:scan-error', { scanId, message: err.message });
    clearOp(scanId);
  });

  worker.postMessage({ type: 'start', scanId, rootPath, opts, cancelFlag: sab });
  return scanId;
}

/** Cancel a running scan (cooperative flag, then hard terminate if needed). */
export function cancelScan(scanId: string): void {
  cancelOp(scanId, 'purpletree:scan-cancelled', scanId);
}

/** Kick off duplicate detection over a completed scan's files. */
export function findDuplicates(scanId: string): boolean {
  const tree = trees.get(scanId);
  if (!tree) return false;
  const files = tree.collectFiles();
  const dupKey = `dup:${scanId}`;
  const { worker, cancel, sab } = spawn();
  active.set(dupKey, { worker, cancel });
  worker.on('message', (evt: ScanEvent) => {
    if (evt.type === 'dup-progress') sender('purpletree:dup-progress', evt);
    else if (evt.type === 'dup-done') {
      sender('purpletree:dup-done', evt);
      clearOp(dupKey);
      void worker.terminate();
    }
  });
  worker.on('error', (err) => {
    sender('purpletree:dup-error', { scanId, message: err.message });
    clearOp(dupKey);
  });
  worker.postMessage({ type: 'find-duplicates', scanId, files, cancelFlag: sab });
  return true;
}

export function cancelDuplicates(scanId: string): void {
  cancelOp(`dup:${scanId}`, 'purpletree:dup-cancelled', scanId);
}

// ----- Slice queries (the renderer pulls these; never the whole tree) -----

export function getChildren(
  scanId: string,
  nodeId: number,
  sort: SortSpec,
  limit: number,
  offset: number
): NodeRow[] {
  return trees.get(scanId)?.getChildren(nodeId, sort, limit, offset) ?? [];
}

export function getTopFiles(scanId: string, n: number, filter?: FileFilter): NodeRow[] {
  return trees.get(scanId)?.getTopFiles(n, filter) ?? [];
}

export function getBreadcrumb(scanId: string, nodeId: number): NodeRow[] {
  return trees.get(scanId)?.getBreadcrumb(nodeId) ?? [];
}

export function getTreemap(
  scanId: string,
  focusId: number,
  width: number,
  height: number,
  maxDepth?: number
): RectNode[] {
  const tree = trees.get(scanId);
  return tree ? computeTreemap(tree, focusId, width, height, maxDepth) : [];
}

export function getSummary(scanId: string): { stats: ScanStats; rootRow: NodeRow } | null {
  const tree = trees.get(scanId);
  const s = stats.get(scanId);
  if (!tree || !s) return null;
  return { stats: s, rootRow: tree.row(0) };
}

export function getExportRows(scanId: string): NodeRow[] {
  return trees.get(scanId)?.flatten(EXPORT_CAP) ?? [];
}

export function getRoot(scanId: string): NodeRow | null {
  return trees.get(scanId)?.row(0) ?? null;
}

// ----- Snapshots -----

export async function saveSnapshot(scanId: string): Promise<boolean> {
  const tree = trees.get(scanId);
  const ser = serialized.get(scanId);
  if (!tree || !ser) return false;
  await writeSnapshot(scanId, ser, tree.stats());
  return true;
}

/** Load a previously-saved snapshot into memory under a fresh scanId. */
export async function loadSnapshot(scanId: string): Promise<{ scanId: string } | null> {
  const ser = await readSnapshot(scanId);
  if (!ser) return null;
  const tree = new Tree(ser);
  const liveId = newScanId();
  trees.set(liveId, tree);
  const st = tree.stats();
  stats.set(liveId, {
    scanId: liveId,
    rootPath: tree.rootPath,
    totalBytes: st.totalBytes,
    totalFiles: st.totalFiles,
    totalDirs: 0,
    permDeniedCount: 0,
    mountSkippedCount: 0,
    symlinkCount: 0,
    durationMs: 0,
    partial: false
  });
  return { scanId: liveId };
}
