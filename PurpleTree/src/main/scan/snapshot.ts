/**
 * @file snapshot.ts — persist/restore a scanned tree as a compact .ptscan blob.
 *
 * Snapshots are a deterministic function of the filesystem (re-running a scan
 * regenerates them) so they are *regenerable* — they don't compel the backup
 * machinery, but they live under Application Support and are swept up by the
 * launch-time backup anyway. Format: an 8-byte magic, a JSON header (field
 * byte-lengths + metadata), then the raw SoA buffers concatenated.
 */
import { app } from 'electron';
import { mkdir, readdir, readFile, writeFile, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import type { SerializedTree } from '../../shared/protocol';
import type { SnapshotInfo } from '../../shared/types';

const MAGIC = 'PTSNAP02';
const FIELDS: Array<keyof SerializedTree> = [
  'parentIdx',
  'firstChild',
  'nextSibling',
  'selfSize',
  'aggSize',
  'selfAlloc',
  'aggAlloc',
  'fileCount',
  'childCount',
  'mtimeMs',
  'atimeMs',
  'flags',
  'nameBytes',
  'nameOffsets'
];

function snapshotsDir(): string {
  return join(app.getPath('userData'), 'snapshots');
}
function snapshotPath(scanId: string): string {
  return join(snapshotsDir(), `${scanId}.ptscan`);
}

interface Header {
  nodeCount: number;
  rootPath: string;
  sep: string;
  createdMs: number;
  totalBytes: number;
  totalFiles: number;
  fields: Array<{ name: keyof SerializedTree; byteLength: number }>;
}

export async function writeSnapshot(
  scanId: string,
  tree: SerializedTree,
  stats: { totalBytes: number; totalFiles: number }
): Promise<SnapshotInfo> {
  await mkdir(snapshotsDir(), { recursive: true });
  const header: Header = {
    nodeCount: tree.nodeCount,
    rootPath: tree.rootPath,
    sep: tree.sep,
    createdMs: Date.now(),
    totalBytes: stats.totalBytes,
    totalFiles: stats.totalFiles,
    fields: FIELDS.map((name) => ({ name, byteLength: (tree[name] as ArrayBuffer).byteLength }))
  };
  const headerBuf = Buffer.from(JSON.stringify(header), 'utf8');
  const lenBuf = Buffer.alloc(4);
  lenBuf.writeUInt32LE(headerBuf.length, 0);
  const parts: Buffer[] = [Buffer.from(MAGIC, 'ascii'), lenBuf, headerBuf];
  for (const f of FIELDS) parts.push(Buffer.from(tree[f] as ArrayBuffer));
  const blob = Buffer.concat(parts);
  const path = snapshotPath(scanId);
  await writeFile(path, blob);
  return {
    scanId,
    rootPath: tree.rootPath,
    createdMs: header.createdMs,
    totalBytes: stats.totalBytes,
    totalFiles: stats.totalFiles,
    sizeBytes: blob.length
  };
}

export async function readSnapshot(scanId: string): Promise<SerializedTree | null> {
  const path = snapshotPath(scanId);
  if (!existsSync(path)) return null;
  const blob = await readFile(path);
  if (blob.subarray(0, 8).toString('ascii') !== MAGIC) return null;
  const headerLen = blob.readUInt32LE(8);
  const header: Header = JSON.parse(blob.subarray(12, 12 + headerLen).toString('utf8'));
  let off = 12 + headerLen;
  const out: Partial<SerializedTree> = {
    nodeCount: header.nodeCount,
    rootPath: header.rootPath,
    sep: header.sep
  };
  for (const { name, byteLength } of header.fields) {
    // Copy into a fresh ArrayBuffer so views are independent of `blob`.
    const ab = blob.buffer.slice(blob.byteOffset + off, blob.byteOffset + off + byteLength);
    (out as Record<string, ArrayBuffer>)[name] = ab;
    off += byteLength;
  }
  return out as SerializedTree;
}

export async function listSnapshots(): Promise<SnapshotInfo[]> {
  const dir = snapshotsDir();
  if (!existsSync(dir)) return [];
  const names = (await readdir(dir)).filter((n) => n.endsWith('.ptscan'));
  const infos: SnapshotInfo[] = [];
  for (const n of names) {
    try {
      const blob = await readFile(join(dir, n));
      if (blob.subarray(0, 8).toString('ascii') !== MAGIC) continue;
      const headerLen = blob.readUInt32LE(8);
      const h: Header = JSON.parse(blob.subarray(12, 12 + headerLen).toString('utf8'));
      infos.push({
        scanId: n.replace(/\.ptscan$/, ''),
        rootPath: h.rootPath,
        createdMs: h.createdMs,
        totalBytes: h.totalBytes,
        totalFiles: h.totalFiles,
        sizeBytes: blob.length
      });
    } catch {
      // skip corrupt snapshot
    }
  }
  infos.sort((a, b) => b.createdMs - a.createdMs);
  return infos;
}

export async function deleteSnapshot(scanId: string): Promise<void> {
  const path = snapshotPath(scanId);
  if (existsSync(path)) await rm(path, { force: true });
}
