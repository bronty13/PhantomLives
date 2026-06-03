/**
 * @file protocol.ts — the worker <-> main message contract.
 *
 * The scan worker receives `ScanCommand`s and posts `ScanEvent`s. The final
 * tree is shipped as `SerializedTree`, a bundle of transferable ArrayBuffers
 * (Structure-of-Arrays) so it crosses the worker boundary zero-copy.
 */
import type { ScanOptions, ScanStats, ScanProgress, DuplicateScanResult, DuplicateProgress } from './types';

/** The Structure-of-Arrays tree, as transferable buffers. */
export interface SerializedTree {
  nodeCount: number;
  rootPath: string;
  /** Filesystem path separator used to reconstruct absolute paths. */
  sep: string;
  parentIdx: ArrayBuffer; // Int32Array
  firstChild: ArrayBuffer; // Int32Array (-1 = none)
  nextSibling: ArrayBuffer; // Int32Array (-1 = none)
  selfSize: ArrayBuffer; // Float64Array — logical (content) size
  aggSize: ArrayBuffer; // Float64Array — recursive logical size
  selfAlloc: ArrayBuffer; // Float64Array — on-disk allocated size
  aggAlloc: ArrayBuffer; // Float64Array — recursive on-disk size
  fileCount: ArrayBuffer; // Uint32Array (recursive file count)
  childCount: ArrayBuffer; // Uint32Array (direct children)
  mtimeMs: ArrayBuffer; // Float64Array
  atimeMs: ArrayBuffer; // Float64Array
  flags: ArrayBuffer; // Uint8Array
  nameBytes: ArrayBuffer; // Uint8Array (UTF-8, concatenated names)
  nameOffsets: ArrayBuffer; // Uint32Array (length nodeCount + 1)
}

/** Every transferable buffer in a SerializedTree, for postMessage transfer list. */
export function treeTransferList(t: SerializedTree): ArrayBuffer[] {
  return [
    t.parentIdx,
    t.firstChild,
    t.nextSibling,
    t.selfSize,
    t.aggSize,
    t.selfAlloc,
    t.aggAlloc,
    t.fileCount,
    t.childCount,
    t.mtimeMs,
    t.atimeMs,
    t.flags,
    t.nameBytes,
    t.nameOffsets
  ];
}

/** Commands sent from main -> worker. */
export type ScanCommand =
  | {
      type: 'start';
      scanId: string;
      rootPath: string;
      opts: ScanOptions;
      /** SharedArrayBuffer-backed Int32Array[0]; set to 1 to request cancel. */
      cancelFlag: SharedArrayBuffer;
    }
  | {
      type: 'find-duplicates';
      scanId: string;
      /** Absolute file paths + sizes to consider (from a completed scan). */
      files: Array<{ path: string; size: number }>;
      cancelFlag: SharedArrayBuffer;
    };

/** Events posted from worker -> main. */
export type ScanEvent =
  | { type: 'progress'; progress: ScanProgress }
  | { type: 'done'; stats: ScanStats; tree: SerializedTree }
  | { type: 'error'; scanId: string; message: string }
  | { type: 'dup-progress'; scanId: string; progress: DuplicateProgress }
  | { type: 'dup-done'; scanId: string; result: DuplicateScanResult };
