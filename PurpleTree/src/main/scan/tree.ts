/**
 * @file tree.ts — the Structure-of-Arrays scan tree: builder + reader.
 *
 * `TreeBuilder` accumulates nodes during a crawl into growable typed arrays,
 * then `finalize()` rolls up subtree aggregates and emits a `SerializedTree`
 * of transferable buffers. `Tree` wraps a `SerializedTree` (in the main
 * process) and answers windowed slice queries for the renderer.
 *
 * Invariant: a parent is always created before its children, so node ids are
 * monotonic down the tree (parentId < childId). That lets the post-order
 * aggregation run as a single reverse-index loop.
 */
import type { SerializedTree } from '../../shared/protocol';
import {
  FLAG_DIR,
  FLAG_SYMLINK,
  FLAG_PERM_DENIED,
  FLAG_CROSSED_MOUNT,
  FLAG_HARDLINK_DUP,
  type NodeRow,
  type SortSpec,
  type FileFilter,
  type SizeMetric
} from '../../shared/types';

const INITIAL_CAPACITY = 1024;

export class TreeBuilder {
  private cap = INITIAL_CAPACITY;
  private n = 0;

  private parentIdx: Int32Array<ArrayBuffer> = new Int32Array(this.cap);
  private firstChild: Int32Array<ArrayBuffer> = new Int32Array(this.cap).fill(-1);
  private nextSibling: Int32Array<ArrayBuffer> = new Int32Array(this.cap).fill(-1);
  private selfSize: Float64Array<ArrayBuffer> = new Float64Array(this.cap);
  private aggSize: Float64Array<ArrayBuffer> = new Float64Array(this.cap);
  private selfAlloc: Float64Array<ArrayBuffer> = new Float64Array(this.cap);
  private aggAlloc: Float64Array<ArrayBuffer> = new Float64Array(this.cap);
  private fileCount: Uint32Array<ArrayBuffer> = new Uint32Array(this.cap);
  private childCount: Uint32Array<ArrayBuffer> = new Uint32Array(this.cap);
  private mtimeMs: Float64Array<ArrayBuffer> = new Float64Array(this.cap);
  private atimeMs: Float64Array<ArrayBuffer> = new Float64Array(this.cap);
  private flags: Uint8Array<ArrayBuffer> = new Uint8Array(this.cap);
  // Names are encoded into one growing UTF-8 buffer *as nodes are added* — not
  // held as a 2.4M-entry string[] and re-encoded into 2.4M Uint8Arrays at
  // finalize (that spike OOM'd the worker on large trees).
  private nameBuf: Uint8Array<ArrayBuffer> = new Uint8Array(1 << 16);
  private nameLen = 0;
  private nameOffsets: Uint32Array<ArrayBuffer> = new Uint32Array(this.cap + 1);
  private enc = new TextEncoder();

  constructor(
    public readonly rootPath: string,
    public readonly sep: string
  ) {}

  get count(): number {
    return this.n;
  }

  private grow(): void {
    const next = this.cap * 2;
    const gi = (a: Int32Array<ArrayBuffer>): Int32Array<ArrayBuffer> => {
      const b = new Int32Array(next).fill(-1);
      b.set(a);
      return b;
    };
    const gf = (a: Float64Array<ArrayBuffer>): Float64Array<ArrayBuffer> => {
      const b = new Float64Array(next);
      b.set(a);
      return b;
    };
    const gu = (a: Uint32Array<ArrayBuffer>): Uint32Array<ArrayBuffer> => {
      const b = new Uint32Array(next);
      b.set(a);
      return b;
    };
    const g8 = (a: Uint8Array<ArrayBuffer>): Uint8Array<ArrayBuffer> => {
      const b = new Uint8Array(next);
      b.set(a);
      return b;
    };
    // Int32 arrays default-fill -1 only for the *new* slots; copy preserves old.
    this.parentIdx = gi(this.parentIdx);
    this.firstChild = gi(this.firstChild);
    this.nextSibling = gi(this.nextSibling);
    this.selfSize = gf(this.selfSize);
    this.aggSize = gf(this.aggSize);
    this.selfAlloc = gf(this.selfAlloc);
    this.aggAlloc = gf(this.aggAlloc);
    this.fileCount = gu(this.fileCount);
    this.childCount = gu(this.childCount);
    this.mtimeMs = gf(this.mtimeMs);
    this.atimeMs = gf(this.atimeMs);
    this.flags = g8(this.flags);
    const no = new Uint32Array(next + 1);
    no.set(this.nameOffsets);
    this.nameOffsets = no;
    this.cap = next;
  }

  /** Append a name's UTF-8 bytes to the growing name buffer; returns nothing. */
  private appendName(name: string): void {
    // Worst case 3 bytes per UTF-16 unit covers BMP and surrogate pairs.
    const need = this.nameLen + name.length * 3;
    if (need > this.nameBuf.length) {
      let cap = this.nameBuf.length * 2;
      while (cap < need) cap *= 2;
      const b = new Uint8Array(cap);
      b.set(this.nameBuf.subarray(0, this.nameLen));
      this.nameBuf = b;
    }
    const { written } = this.enc.encodeInto(name, this.nameBuf.subarray(this.nameLen));
    this.nameLen += written;
  }

  /**
   * Add a node. `parent` is the parent node id, or -1 for the root (which
   * must be the first node added). Returns the new node id.
   */
  addNode(opts: {
    parent: number;
    name: string;
    selfSize: number;
    /** On-disk allocated size; defaults to the logical size when omitted. */
    allocSize?: number;
    mtimeMs: number;
    atimeMs: number;
    flags: number;
  }): number {
    if (this.n >= this.cap) this.grow();
    const id = this.n++;
    this.parentIdx[id] = opts.parent;
    this.selfSize[id] = opts.selfSize;
    this.selfAlloc[id] = opts.allocSize ?? opts.selfSize;
    this.mtimeMs[id] = opts.mtimeMs;
    this.atimeMs[id] = opts.atimeMs;
    this.flags[id] = opts.flags;
    this.nameOffsets[id] = this.nameLen;
    this.appendName(opts.name);
    if (opts.parent >= 0) {
      // Prepend to the parent's child list (O(1); order is irrelevant since
      // the renderer sorts at query time).
      this.nextSibling[id] = this.firstChild[opts.parent];
      this.firstChild[opts.parent] = id;
      this.childCount[opts.parent]++;
    }
    return id;
  }

  /** OR a flag bit onto an existing node (e.g. mark a dir permission-denied). */
  addFlag(id: number, bit: number): void {
    this.flags[id] |= bit;
  }

  /** Roll up aggregates and emit the transferable SerializedTree. */
  finalize(): SerializedTree {
    const n = this.n;
    // Seed: files contribute their own size + count of 1; hard-link repeats
    // contribute 0 to folder totals (du-correct) but keep their real
    // selfSize for per-file display.
    for (let i = 0; i < n; i++) {
      const isDir = (this.flags[i] & FLAG_DIR) !== 0;
      const isHardDup = (this.flags[i] & FLAG_HARDLINK_DUP) !== 0;
      this.aggSize[i] = isHardDup ? 0 : this.selfSize[i];
      this.aggAlloc[i] = isHardDup ? 0 : this.selfAlloc[i];
      this.fileCount[i] = isDir ? 0 : 1;
    }
    // Post-order roll-up via reverse-index loop (parentId < childId holds).
    for (let i = n - 1; i >= 1; i--) {
      const p = this.parentIdx[i];
      if (p < 0) continue;
      this.aggSize[p] += this.aggSize[i];
      this.aggAlloc[p] += this.aggAlloc[i];
      this.fileCount[p] += this.fileCount[i];
    }

    // Names were encoded incrementally during addNode — just cap the offsets
    // and slice the buffers to their used length. No per-name allocation here.
    this.nameOffsets[n] = this.nameLen;
    const nameBytes = this.nameBuf.slice(0, this.nameLen);
    const nameOffsets = this.nameOffsets.slice(0, n + 1);

    // Slice each typed array to exactly n elements and detach its buffer.
    const sliceI = (a: Int32Array<ArrayBuffer>): ArrayBuffer => a.slice(0, n).buffer;
    const sliceF = (a: Float64Array<ArrayBuffer>): ArrayBuffer => a.slice(0, n).buffer;
    const sliceU = (a: Uint32Array<ArrayBuffer>): ArrayBuffer => a.slice(0, n).buffer;
    const slice8 = (a: Uint8Array<ArrayBuffer>): ArrayBuffer => a.slice(0, n).buffer;

    return {
      nodeCount: n,
      rootPath: this.rootPath,
      sep: this.sep,
      parentIdx: sliceI(this.parentIdx),
      firstChild: sliceI(this.firstChild),
      nextSibling: sliceI(this.nextSibling),
      selfSize: sliceF(this.selfSize),
      aggSize: sliceF(this.aggSize),
      selfAlloc: sliceF(this.selfAlloc),
      aggAlloc: sliceF(this.aggAlloc),
      fileCount: sliceU(this.fileCount),
      childCount: sliceU(this.childCount),
      mtimeMs: sliceF(this.mtimeMs),
      atimeMs: sliceF(this.atimeMs),
      flags: slice8(this.flags),
      nameBytes: nameBytes.buffer,
      nameOffsets: nameOffsets.buffer
    };
  }
}

/** Read-only view over a finalized SerializedTree (lives in main). */
export class Tree {
  readonly nodeCount: number;
  readonly rootPath: string;
  readonly sep: string;
  private readonly parentIdx: Int32Array;
  private readonly firstChild: Int32Array;
  private readonly nextSibling: Int32Array;
  private readonly selfSize: Float64Array;
  private readonly aggSize: Float64Array;
  private readonly selfAlloc: Float64Array;
  private readonly aggAlloc: Float64Array;
  private readonly fileCount: Uint32Array;
  /** Which size to report. Defaults to logical for test/back-compat. */
  private metric: SizeMetric = 'logical';
  private readonly childCount: Uint32Array;
  private readonly mtimeMs: Float64Array;
  private readonly atimeMs: Float64Array;
  private readonly flags: Uint8Array;
  private readonly nameBytes: Uint8Array;
  private readonly nameOffsets: Uint32Array;
  private readonly dec = new TextDecoder();

  constructor(t: SerializedTree) {
    this.nodeCount = t.nodeCount;
    this.rootPath = t.rootPath;
    this.sep = t.sep;
    this.parentIdx = new Int32Array(t.parentIdx);
    this.firstChild = new Int32Array(t.firstChild);
    this.nextSibling = new Int32Array(t.nextSibling);
    this.selfSize = new Float64Array(t.selfSize);
    this.aggSize = new Float64Array(t.aggSize);
    this.selfAlloc = new Float64Array(t.selfAlloc);
    this.aggAlloc = new Float64Array(t.aggAlloc);
    this.fileCount = new Uint32Array(t.fileCount);
    this.childCount = new Uint32Array(t.childCount);
    this.mtimeMs = new Float64Array(t.mtimeMs);
    this.atimeMs = new Float64Array(t.atimeMs);
    this.flags = new Uint8Array(t.flags);
    this.nameBytes = new Uint8Array(t.nameBytes);
    this.nameOffsets = new Uint32Array(t.nameOffsets);
  }

  /** Switch the reported size metric (alloc = on-disk, logical = content). */
  setMetric(m: SizeMetric): void {
    this.metric = m;
  }

  /** Recursive subtree size in the active metric. */
  private aggOf(id: number): number {
    return this.metric === 'alloc' ? this.aggAlloc[id] : this.aggSize[id];
  }

  /** A node's own size in the active metric. */
  private selfOf(id: number): number {
    return this.metric === 'alloc' ? this.selfAlloc[id] : this.selfSize[id];
  }

  name(id: number): string {
    return this.dec.decode(this.nameBytes.subarray(this.nameOffsets[id], this.nameOffsets[id + 1]));
  }

  isDir(id: number): boolean {
    return (this.flags[id] & FLAG_DIR) !== 0;
  }

  /** Reconstruct the absolute path of a node by walking to the root. */
  path(id: number): string {
    if (id <= 0) return this.rootPath;
    const parts: string[] = [];
    let cur = id;
    while (cur > 0) {
      parts.push(this.name(cur));
      cur = this.parentIdx[cur];
    }
    parts.reverse();
    const base = this.rootPath.endsWith(this.sep) ? this.rootPath.slice(0, -1) : this.rootPath;
    return [base, ...parts].join(this.sep);
  }

  row(id: number): NodeRow {
    const f = this.flags[id];
    return {
      id,
      name: id === 0 ? this.rootPath : this.name(id),
      aggSize: this.aggOf(id),
      fileCount: this.fileCount[id],
      isDir: (f & FLAG_DIR) !== 0,
      isSymlink: (f & FLAG_SYMLINK) !== 0,
      permDenied: (f & FLAG_PERM_DENIED) !== 0,
      mtimeMs: this.mtimeMs[id],
      atimeMs: this.atimeMs[id],
      childCount: this.childCount[id],
      path: this.path(id)
    };
  }

  private childIds(id: number): number[] {
    const out: number[] = [];
    let c = this.firstChild[id];
    while (c !== -1) {
      out.push(c);
      c = this.nextSibling[c];
    }
    return out;
  }

  private compare(a: number, b: number, spec: SortSpec): number {
    let v = 0;
    switch (spec.key) {
      case 'size':
        v = this.aggOf(a) - this.aggOf(b);
        break;
      case 'count':
        v = this.fileCount[a] - this.fileCount[b];
        break;
      case 'mtime':
        v = this.mtimeMs[a] - this.mtimeMs[b];
        break;
      case 'name':
        v = this.name(a).localeCompare(this.name(b));
        break;
      case 'type': {
        const da = this.isDir(a) ? 0 : 1;
        const db = this.isDir(b) ? 0 : 1;
        v = da - db || this.name(a).localeCompare(this.name(b));
        break;
      }
    }
    return spec.dir === 'asc' ? v : -v;
  }

  /** Sorted, windowed direct children of a node. */
  getChildren(id: number, spec: SortSpec, limit: number, offset: number): NodeRow[] {
    if (id < 0 || id >= this.nodeCount) return [];
    const kids = this.childIds(id);
    kids.sort((a, b) => this.compare(a, b, spec));
    return kids.slice(offset, offset + limit).map((c) => this.row(c));
  }

  /** Path from the root down to `id`, inclusive (for a breadcrumb bar). */
  getBreadcrumb(id: number): NodeRow[] {
    const chain: number[] = [];
    let cur = id;
    while (cur > 0) {
      chain.push(cur);
      cur = this.parentIdx[cur];
    }
    chain.push(0);
    chain.reverse();
    return chain.map((c) => this.row(c));
  }

  /**
   * Resolve an absolute path to its node id, or -1 if it's not in this tree.
   * Walks down from the root segment by segment (O(depth × branching)) rather
   * than reconstructing every node's path — used to re-anchor the renderer's
   * focus after a refresh renumbers node ids.
   */
  findByPath(absPath: string): number {
    const trim = (p: string): string =>
      p.length > 1 && p.endsWith(this.sep) ? p.slice(0, -1) : p;
    const target = trim(absPath);
    const base = trim(this.rootPath);
    if (target === base) return 0;
    if (!target.startsWith(base + this.sep)) return -1;
    const segs = target
      .slice(base.length + this.sep.length)
      .split(this.sep)
      .filter((s) => s.length > 0);
    let cur = 0;
    for (const seg of segs) {
      let found = -1;
      let c = this.firstChild[cur];
      while (c !== -1) {
        if (this.name(c) === seg) {
          found = c;
          break;
        }
        c = this.nextSibling[c];
      }
      if (found === -1) return -1;
      cur = found;
    }
    return cur;
  }

  /**
   * Recompute the summary counters from the live node set. The crawl-time stats
   * don't survive a subtree splice (a refresh re-scans only one folder), so a
   * refreshed tree re-derives totals from its flags + root rollups instead.
   */
  recountStats(): {
    totalBytes: number;
    totalFiles: number;
    totalDirs: number;
    permDeniedCount: number;
    mountSkippedCount: number;
    symlinkCount: number;
  } {
    let totalDirs = 0;
    let permDeniedCount = 0;
    let mountSkippedCount = 0;
    let symlinkCount = 0;
    for (let i = 0; i < this.nodeCount; i++) {
      const f = this.flags[i];
      if (f & FLAG_DIR) totalDirs++;
      if (f & FLAG_PERM_DENIED) permDeniedCount++;
      if (f & FLAG_CROSSED_MOUNT) mountSkippedCount++;
      if (f & FLAG_SYMLINK) symlinkCount++;
    }
    return {
      // Logical bytes, to match the worker's byte counter (the topbar's size
      // comes from the metric-aware root row, not this field).
      totalBytes: this.aggSize[0] ?? 0,
      totalFiles: this.fileCount[0] ?? 0,
      totalDirs,
      permDeniedCount,
      mountSkippedCount,
      symlinkCount
    };
  }

  /** Top-N files (not dirs) matching a filter, largest first. */
  getTopFiles(n: number, filter?: FileFilter): NodeRow[] {
    const minBytes = filter?.minBytes ?? 0;
    const cutoffMs =
      filter && filter.notAccessedDays > 0
        ? Date.now() - filter.notAccessedDays * 86_400_000
        : 0;
    const exts = filter?.extensions ?? [];
    const matches: number[] = [];
    for (let i = 1; i < this.nodeCount; i++) {
      if (this.isDir(i)) continue;
      if (this.selfOf(i) < minBytes) continue;
      if (cutoffMs > 0 && this.atimeMs[i] > cutoffMs) continue;
      if (exts.length > 0) {
        const nm = this.name(i).toLowerCase();
        const dot = nm.lastIndexOf('.');
        const ext = dot >= 0 ? nm.slice(dot + 1) : '';
        if (!exts.includes(ext)) continue;
      }
      matches.push(i);
    }
    matches.sort((a, b) => this.selfOf(b) - this.selfOf(a));
    return matches.slice(0, n).map((i) => {
      const r = this.row(i);
      // For the file list, surface the file's own size, not subtree agg.
      r.aggSize = this.selfOf(i);
      return r;
    });
  }

  /** All files in the tree as {path, size} — feeds the duplicate finder. */
  collectFiles(): Array<{ path: string; size: number }> {
    const out: Array<{ path: string; size: number }> = [];
    for (let i = 1; i < this.nodeCount; i++) {
      if (this.isDir(i)) continue;
      if ((this.flags[i] & FLAG_SYMLINK) !== 0) continue;
      out.push({ path: this.path(i), size: this.selfSize[i] });
    }
    return out;
  }

  stats(): { totalBytes: number; totalFiles: number } {
    return { totalBytes: this.aggOf(0) ?? 0, totalFiles: this.fileCount[0] ?? 0 };
  }

  /**
   * Map every node's absolute path → {size, isDir} (active metric). Folders use
   * their aggregate size, files their own size. Feeds the snapshot diff so it
   * can reveal file-level changes, not just folder rollups.
   */
  allSizes(): Map<string, { size: number; isDir: boolean }> {
    const m = new Map<string, { size: number; isDir: boolean }>();
    for (let i = 0; i < this.nodeCount; i++) {
      const dir = this.isDir(i);
      m.set(this.path(i), { size: dir ? this.aggOf(i) : this.selfOf(i), isDir: dir });
    }
    return m;
  }

  /** All non-root nodes sorted by aggregate size desc, capped — for export. */
  flatten(limit: number): NodeRow[] {
    const ids: number[] = [];
    for (let i = 1; i < this.nodeCount; i++) ids.push(i);
    ids.sort((a, b) => this.aggOf(b) - this.aggOf(a));
    return ids.slice(0, limit).map((i) => this.row(i));
  }
}

/** Read-only typed-array views + a name decoder over a SerializedTree's buffers. */
function rawView(t: SerializedTree): {
  parentIdx: Int32Array;
  firstChild: Int32Array;
  nextSibling: Int32Array;
  selfSize: Float64Array;
  selfAlloc: Float64Array;
  mtimeMs: Float64Array;
  atimeMs: Float64Array;
  flags: Uint8Array;
  name: (id: number) => string;
  childrenOf: (id: number) => number[];
} {
  const firstChild = new Int32Array(t.firstChild);
  const nextSibling = new Int32Array(t.nextSibling);
  const nameBytes = new Uint8Array(t.nameBytes);
  const nameOffsets = new Uint32Array(t.nameOffsets);
  const dec = new TextDecoder();
  return {
    parentIdx: new Int32Array(t.parentIdx),
    firstChild,
    nextSibling,
    selfSize: new Float64Array(t.selfSize),
    selfAlloc: new Float64Array(t.selfAlloc),
    mtimeMs: new Float64Array(t.mtimeMs),
    atimeMs: new Float64Array(t.atimeMs),
    flags: new Uint8Array(t.flags),
    name: (id) => dec.decode(nameBytes.subarray(nameOffsets[id], nameOffsets[id + 1])),
    childrenOf: (id) => {
      const out: number[] = [];
      let c = firstChild[id];
      while (c !== -1) {
        out.push(c);
        c = nextSibling[c];
      }
      return out;
    }
  };
}

/**
 * Splice a freshly-scanned subtree into a serialized tree, replacing the stale
 * subtree rooted at `targetId`. Returns a brand-new SerializedTree (node ids are
 * renumbered) with aggregates re-rolled by `finalize()`.
 *
 * `sub` is a standalone scan rooted at the target folder's path (its node 0 is
 * the folder itself). When `targetId <= 0` the whole tree is being refreshed, so
 * `sub` already *is* the new tree and is returned unchanged.
 *
 * Both the old tree and the grafted subtree are walked with an explicit stack
 * DFS; because a node is emitted only after its parent (and children are pushed
 * only after the parent is emitted), the `parentId < childId` invariant the
 * aggregation loop relies on is preserved.
 */
export function spliceSubtree(
  old: SerializedTree,
  targetId: number,
  sub: SerializedTree
): SerializedTree {
  if (targetId <= 0) return sub;

  const o = rawView(old);
  const s = rawView(sub);
  const builder = new TreeBuilder(old.rootPath, old.sep);
  const targetParent = o.parentIdx[targetId];
  const targetName = o.name(targetId);
  const map = new Int32Array(old.nodeCount).fill(-1);

  // Graft the fresh subtree under `newParent`, renaming its root (which carries
  // the full path as its name) back to the folder's basename in the old tree.
  const graft = (newParent: number): void => {
    const smap = new Int32Array(sub.nodeCount).fill(-1);
    const stack = [0];
    while (stack.length) {
      const sid = stack.pop()!;
      smap[sid] = builder.addNode({
        parent: sid === 0 ? newParent : smap[s.parentIdx[sid]],
        name: sid === 0 ? targetName : s.name(sid),
        selfSize: s.selfSize[sid],
        allocSize: s.selfAlloc[sid],
        mtimeMs: s.mtimeMs[sid],
        atimeMs: s.atimeMs[sid],
        flags: s.flags[sid]
      });
      for (const c of s.childrenOf(sid)) stack.push(c);
    }
  };

  const stack = [0];
  while (stack.length) {
    const oid = stack.pop()!;
    if (oid === targetId) {
      graft(map[targetParent]); // skip the stale subtree's old children entirely
      continue;
    }
    map[oid] = builder.addNode({
      parent: oid === 0 ? -1 : map[o.parentIdx[oid]],
      name: oid === 0 ? old.rootPath : o.name(oid),
      selfSize: o.selfSize[oid],
      allocSize: o.selfAlloc[oid],
      mtimeMs: o.mtimeMs[oid],
      atimeMs: o.atimeMs[oid],
      flags: o.flags[oid]
    });
    for (const c of o.childrenOf(oid)) stack.push(c);
  }
  return builder.finalize();
}
