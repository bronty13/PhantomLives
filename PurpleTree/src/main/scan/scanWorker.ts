/**
 * @file scanWorker.ts — the filesystem crawl engine (runs in a worker thread).
 *
 * Receives `ScanCommand`s on parentPort, posts `ScanEvent`s back. The crawl is
 * an iterative DFS using synchronous fs calls (the worker has nothing else to
 * do, and sync avoids per-entry promise overhead across millions of stats).
 * The final SoA tree is transferred zero-copy.
 *
 * Safety rules enforced here (never in the renderer):
 *   - lstat, never stat: count links, never follow them (cycle-safe).
 *   - skip other volumes unless crossMountPoints is set.
 *   - de-dup hard links by (dev,ino) on mac/linux (Windows ino is unreliable).
 *   - any opendir/readdir/lstat error (incl. ETIMEDOUT on network/cloud mounts)
 *     → mark perm-denied, count, continue. One bad directory never aborts the
 *     whole scan.
 */
import { parentPort } from 'node:worker_threads';
import { opendirSync, lstatSync, type Dirent } from 'node:fs';
import { sep as pathSep } from 'node:path';
import {
  FLAG_DIR,
  FLAG_SYMLINK,
  FLAG_PERM_DENIED,
  FLAG_CROSSED_MOUNT,
  FLAG_HARDLINK_DUP,
  type ScanProgress,
  type ScanStats
} from '../../shared/types';
import type { ScanCommand, ScanEvent } from '../../shared/protocol';
import { treeTransferList } from '../../shared/protocol';
import { TreeBuilder } from './tree';
import { findDuplicates } from '../dup/dupePipeline';
import { hashFilePartial, hashFileFull } from '../dup/xxhash';

const port = parentPort;
if (!port) throw new Error('scanWorker must run as a worker thread');

const PROGRESS_INTERVAL_MS = 100;
const CANCEL_CHECK_STRIDE = 256;
const isWindows = process.platform === 'win32';

function post(evt: ScanEvent, transfer?: ArrayBuffer[]): void {
  port!.postMessage(evt, transfer ?? []);
}

/** Prefix \\?\ on Windows for paths approaching the 260-char MAX_PATH limit. */
function longPath(p: string): string {
  if (!isWindows) return p;
  if (p.length < 248 || p.startsWith('\\\\?\\')) return p;
  if (/^[a-zA-Z]:\\/.test(p)) return `\\\\?\\${p}`;
  return p;
}

interface CrawlFrame {
  id: number;
  path: string;
}

function runScan(cmd: Extract<ScanCommand, { type: 'start' }>): void {
  const { scanId, rootPath, opts, cancelFlag } = cmd;
  const cancelArr = new Int32Array(cancelFlag);
  const cancelled = (): boolean => Atomics.load(cancelArr, 0) !== 0;

  const builder = new TreeBuilder(rootPath, pathSep);
  const seenInodes = new Set<string>();

  let filesScanned = 0;
  let dirsScanned = 0;
  let bytes = 0;
  let permDeniedCount = 0;
  let mountSkippedCount = 0;
  let symlinkCount = 0;
  let lastEmit = 0;
  let opCounter = 0;
  let currentPath = rootPath;

  const emitProgress = (force = false): void => {
    const now = Date.now();
    if (!force && now - lastEmit < PROGRESS_INTERVAL_MS) return;
    lastEmit = now;
    const progress: ScanProgress = {
      scanId,
      filesScanned,
      dirsScanned,
      bytes,
      currentPath,
      permDeniedCount,
      mountSkippedCount
    };
    post({ type: 'progress', progress });
  };

  // Root node.
  let rootDev = 0;
  let rootIsDir = true;
  try {
    const st = lstatSync(longPath(rootPath));
    rootDev = st.dev;
    rootIsDir = st.isDirectory();
    builder.addNode({
      parent: -1,
      name: rootPath,
      selfSize: rootIsDir ? 0 : st.size,
      mtimeMs: st.mtimeMs,
      atimeMs: st.atimeMs,
      flags: rootIsDir ? FLAG_DIR : 0
    });
  } catch (err) {
    post({ type: 'error', scanId, message: `Cannot read ${rootPath}: ${String(err)}` });
    return;
  }

  const stack: CrawlFrame[] = [{ id: 0, path: rootPath }];

  if (rootIsDir) {
    while (stack.length > 0) {
      if (cancelled()) break;
      const frame = stack.pop()!;
      currentPath = frame.path;
      dirsScanned++;
      try {
        crawlFrame(frame);
      } catch {
        // No single directory may abort the scan — skip it and continue.
        builder.addFlag(frame.id, FLAG_PERM_DENIED);
        permDeniedCount++;
      }
      emitProgress();
    }
  }

  /** Process one directory frame: open it, read entries, enqueue subdirs. */
  function crawlFrame(frame: CrawlFrame): void {
    let dir;
    try {
      dir = opendirSync(longPath(frame.path));
    } catch {
      builder.addFlag(frame.id, FLAG_PERM_DENIED);
      permDeniedCount++;
      return;
    }

    try {
      for (;;) {
        let entry: Dirent | null;
        try {
          entry = dir.readSync();
        } catch {
          // readdir failed mid-iteration — e.g. ETIMEDOUT on a network /
          // cloud-backed mount (CloudStorage, SMB, MacDroid). Mark this dir
          // and stop reading it, but NEVER abort the whole scan.
          builder.addFlag(frame.id, FLAG_PERM_DENIED);
          permDeniedCount++;
          break;
        }
        if (entry === null) break;
        if (++opCounter % CANCEL_CHECK_STRIDE === 0 && cancelled()) break;
        const childPath = frame.path.endsWith(pathSep)
          ? frame.path + entry.name
          : frame.path + pathSep + entry.name;

        let st;
        try {
          st = lstatSync(longPath(childPath));
        } catch {
          // Unreadable entry (race / permission) — skip silently.
          continue;
        }

        if (st.isSymbolicLink() && !opts.followSymlinks) {
          symlinkCount++;
          builder.addNode({
            parent: frame.id,
            name: entry.name,
            selfSize: st.size,
            mtimeMs: st.mtimeMs,
            atimeMs: st.atimeMs,
            flags: FLAG_SYMLINK
          });
          continue;
        }

        if (st.isDirectory()) {
          const crossed = !opts.crossMountPoints && st.dev !== rootDev;
          const childId = builder.addNode({
            parent: frame.id,
            name: entry.name,
            selfSize: 0,
            mtimeMs: st.mtimeMs,
            atimeMs: st.atimeMs,
            flags: FLAG_DIR | (crossed ? FLAG_CROSSED_MOUNT : 0)
          });
          if (crossed) {
            mountSkippedCount++;
          } else {
            stack.push({ id: childId, path: childPath });
          }
          continue;
        }

        // Regular file (or device/fifo — treated as a file leaf).
        let flags = 0;
        if (opts.dedupHardLinks && !isWindows && st.nlink > 1) {
          const key = `${st.dev}:${st.ino}`;
          if (seenInodes.has(key)) flags |= FLAG_HARDLINK_DUP;
          else seenInodes.add(key);
        }
        builder.addNode({
          parent: frame.id,
          name: entry.name,
          selfSize: st.size,
          mtimeMs: st.mtimeMs,
          atimeMs: st.atimeMs,
          flags
        });
        filesScanned++;
        if ((flags & FLAG_HARDLINK_DUP) === 0) bytes += st.size;
        emitProgress();
      }
    } finally {
      try {
        dir.closeSync();
      } catch {
        // closing a timed-out handle can itself throw — ignore.
      }
    }
  }

  emitProgress(true);
  const tree = builder.finalize();
  const stats: ScanStats = {
    scanId,
    rootPath,
    totalBytes: bytes,
    totalFiles: filesScanned,
    totalDirs: dirsScanned,
    permDeniedCount,
    mountSkippedCount,
    symlinkCount,
    durationMs: 0, // stamped in main
    partial: cancelled()
  };
  post({ type: 'done', stats, tree }, treeTransferList(tree));
}

async function runDuplicates(
  cmd: Extract<ScanCommand, { type: 'find-duplicates' }>
): Promise<void> {
  const { scanId, files, cancelFlag } = cmd;
  const cancelArr = new Int32Array(cancelFlag);
  const result = await findDuplicates(files, {
    hashPartial: (p, max) => hashFilePartial(p, max),
    hashFull: (p) => hashFileFull(p),
    onProgress: (progress) => post({ type: 'dup-progress', scanId, progress }),
    shouldCancel: () => Atomics.load(cancelArr, 0) !== 0
  });
  post({ type: 'dup-done', scanId, result });
}

port.on('message', (cmd: ScanCommand) => {
  try {
    if (cmd.type === 'start') {
      runScan(cmd);
    } else if (cmd.type === 'find-duplicates') {
      void runDuplicates(cmd);
    }
  } catch (err) {
    const scanId = 'scanId' in cmd ? cmd.scanId : 'unknown';
    post({ type: 'error', scanId, message: err instanceof Error ? err.message : String(err) });
  }
});
