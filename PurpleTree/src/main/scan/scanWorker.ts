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
import { opendir, lstat } from 'node:fs/promises';
import { sep as pathSep, join as pathJoin } from 'node:path';
import { homedir } from 'node:os';
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

async function runScan(cmd: Extract<ScanCommand, { type: 'start' }>): Promise<void> {
  const { scanId, rootPath, opts, cancelFlag } = cmd;
  const cancelArr = new Int32Array(cancelFlag);
  const cancelled = (): boolean => Atomics.load(cancelArr, 0) !== 0;

  const builder = new TreeBuilder(rootPath, pathSep);
  const seenInodes = new Set<string>();

  // Cloud/network provider mounts (~/Library/CloudStorage/iCloud Drive,
  // GoogleDrive-…, OneDrive-…, MacDroid-…, etc.) report the same device id as
  // the home volume, so the st_dev mount check misses them. They're remote, not
  // local disk, and slow remote readdirs make scans crawl — so by default
  // (crossMountPoints off) we don't descend into the CloudStorage tree.
  const cloudStorageDir = pathJoin(homedir(), 'Library', 'CloudStorage');

  let filesScanned = 0;
  let dirsScanned = 0;
  let bytes = 0;
  let permDeniedCount = 0;
  let mountSkippedCount = 0;
  let symlinkCount = 0;
  let lastEmit = 0;
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
    const st = await lstat(longPath(rootPath));
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
      // Emit *before* opening so the UI shows the directory we're about to
      // read — if it hangs, that path is the culprit.
      emitProgress();
      try {
        await crawlFrame(frame);
      } catch {
        // No single directory may abort the scan — skip it and continue.
        builder.addFlag(frame.id, FLAG_PERM_DENIED);
        permDeniedCount++;
      }
      emitProgress();
    }
  }

  /**
   * Process one directory frame: open it, read entries, enqueue subdirs.
   * Uses async fs so the worker's event loop stays responsive — that is what
   * makes the cooperative cancel flag *and* worker.terminate() actually work
   * even when a single readdir/lstat is wedged on a hung network/cloud mount.
   */
  async function crawlFrame(frame: CrawlFrame): Promise<void> {
    let dir;
    try {
      dir = await opendir(longPath(frame.path));
    } catch {
      builder.addFlag(frame.id, FLAG_PERM_DENIED);
      permDeniedCount++;
      return;
    }

    try {
      // `for await` reads entries lazily and auto-closes the handle on break,
      // return, or throw. A readdir failure mid-iteration throws here and is
      // caught below — it never aborts the whole scan.
      for await (const entry of dir) {
        if (cancelled()) break;
        const childPath = frame.path.endsWith(pathSep)
          ? frame.path + entry.name
          : frame.path + pathSep + entry.name;

        let st;
        try {
          st = await lstat(longPath(childPath));
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
          const crossed =
            !opts.crossMountPoints &&
            (st.dev !== rootDev || childPath === cloudStorageDir);
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
    } catch {
      // readdir failed mid-iteration (ETIMEDOUT etc.) — mark + move on.
      builder.addFlag(frame.id, FLAG_PERM_DENIED);
      permDeniedCount++;
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
  const scanId = 'scanId' in cmd ? cmd.scanId : 'unknown';
  const fail = (err: unknown): void =>
    post({ type: 'error', scanId, message: err instanceof Error ? err.message : String(err) });
  try {
    if (cmd.type === 'start') {
      void runScan(cmd).catch(fail);
    } else if (cmd.type === 'find-duplicates') {
      void runDuplicates(cmd).catch(fail);
    }
  } catch (err) {
    fail(err);
  }
});
