/**
 * @file types.ts — DTOs shared across main, preload, worker, and renderer.
 *
 * Dependency-free on purpose: it is imported by the Node worker, the main
 * process, the preload bridge, and the React renderer, so it must not pull
 * in anything platform-specific.
 */

/** Node flag bits packed into the SoA `flags` Uint8Array. */
export const FLAG_DIR = 1 << 0;
export const FLAG_SYMLINK = 1 << 1;
export const FLAG_PERM_DENIED = 1 << 2;
export const FLAG_CROSSED_MOUNT = 1 << 3;
/** A repeat hard link: shown in listings but excluded from folder totals. */
export const FLAG_HARDLINK_DUP = 1 << 4;

/** Options that govern a single scan. */
export interface ScanOptions {
  /** Follow symbolic links into their targets. Hard default: false. */
  followSymlinks: boolean;
  /** Descend across filesystem mount points / volumes. Default: false. */
  crossMountPoints: boolean;
  /**
   * De-duplicate hard links so the same inode isn't counted twice in folder
   * totals (du-style). macOS/Linux only — Windows inode numbers are
   * unreliable, so this is ignored there.
   */
  dedupHardLinks: boolean;
}

export const DEFAULT_SCAN_OPTIONS: ScanOptions = {
  followSymlinks: false,
  crossMountPoints: false,
  dedupHardLinks: true
};

/** Lightweight row DTO handed to the renderer for one tree node. */
export interface NodeRow {
  id: number;
  name: string;
  /** Recursive subtree size in bytes (hard-link deduped when enabled). */
  aggSize: number;
  /** Recursive file count in the subtree. */
  fileCount: number;
  isDir: boolean;
  isSymlink: boolean;
  permDenied: boolean;
  /** Last-modified time, ms since epoch (0 if unknown). */
  mtimeMs: number;
  /** Last-accessed time, ms since epoch (0 if unknown). */
  atimeMs: number;
  /** Number of direct children (0 for files). */
  childCount: number;
  /** Absolute filesystem path. */
  path: string;
}

/** Summary statistics for a completed (or cancelled) scan. */
export interface ScanStats {
  scanId: string;
  rootPath: string;
  totalBytes: number;
  totalFiles: number;
  totalDirs: number;
  /** Directories skipped because of EACCES/EPERM. */
  permDeniedCount: number;
  /** Directories skipped because they live on another volume. */
  mountSkippedCount: number;
  /** Symbolic links encountered (counted as links, not followed). */
  symlinkCount: number;
  /** Wall-clock duration in ms (stamped in main, not the worker). */
  durationMs: number;
  /** True if the scan was cancelled before finishing. */
  partial: boolean;
}

/** Push payload sent to the renderer while a scan is in flight. */
export interface ScanProgress {
  scanId: string;
  filesScanned: number;
  dirsScanned: number;
  bytes: number;
  currentPath: string;
  permDeniedCount: number;
  mountSkippedCount: number;
}

/**
 * Which size to report. `alloc` = blocks actually used on disk (du/DaisyDisk
 * style; cloud placeholders & sparse files ≈ 0). `logical` = the file's content
 * length (Finder "Size" style).
 */
export type SizeMetric = 'alloc' | 'logical';

export type SortKey = 'size' | 'name' | 'count' | 'mtime' | 'type';
export type SortDir = 'asc' | 'desc';
export interface SortSpec {
  key: SortKey;
  dir: SortDir;
}

/** One rectangle in a computed treemap layout. */
export interface RectNode {
  id: number;
  name: string;
  path: string;
  size: number;
  x: number;
  y: number;
  w: number;
  h: number;
  depth: number;
  isDir: boolean;
}

/** One arc segment in a computed sunburst layout. Angles in radians; radii
 *  normalized to [0,1] (the renderer scales them to the canvas). */
export interface ArcNode {
  id: number;
  name: string;
  path: string;
  size: number;
  depth: number;
  isDir: boolean;
  a0: number;
  a1: number;
  r0: number;
  r1: number;
}

/** Filter for the "large & old files" view. */
export interface FileFilter {
  /** Minimum file size in bytes (0 = no minimum). */
  minBytes: number;
  /** Only files not accessed within this many days (0 = no age filter). */
  notAccessedDays: number;
  /** Restrict to these lowercase extensions (without dot); empty = all. */
  extensions: string[];
}

/** A confirmed set of byte-identical duplicate files. */
export interface DuplicateSet {
  /** Full-file hash (hex). */
  hash: string;
  /** Shared file size in bytes. */
  size: number;
  /** Absolute paths of the duplicates. */
  paths: string[];
  /** Bytes reclaimable by keeping one copy: (count - 1) * size. */
  wastedBytes: number;
}

export interface DuplicateScanResult {
  sets: DuplicateSet[];
  filesHashed: number;
  bytesHashed: number;
  totalWasted: number;
}

export interface DuplicateProgress {
  phase: 'sizing' | 'partial-hash' | 'full-hash';
  filesHashed: number;
  bytesHashed: number;
  candidateSets: number;
}

/** Declarative cache-cleanup preset (shipped in resources/cache-presets.json). */
export interface CachePreset {
  id: string;
  label: string;
  description: string;
  platform: 'darwin' | 'win32' | 'all';
  riskLevel: 'low' | 'medium' | 'high';
  /** Path templates with ${HOME} / ${LOCALAPPDATA} / ${TMPDIR} tokens. */
  paths: string[];
}

/** A preset after token expansion + size measurement, ready to show. */
export interface ResolvedCachePreset {
  id: string;
  label: string;
  description: string;
  riskLevel: 'low' | 'medium' | 'high';
  /** Resolved absolute paths that actually exist on this machine. */
  paths: string[];
  /** Total bytes reclaimable across the resolved paths. */
  totalBytes: number;
  /** Total file count across the resolved paths. */
  fileCount: number;
}

/** Result of a delete (trash or permanent) operation. */
export interface DeleteResult {
  ok: boolean;
  /** Paths successfully removed. */
  removed: string[];
  /** Paths that failed, with reasons. */
  failed: Array<{ path: string; reason: string }>;
}

/** A single backup archive on disk. */
export interface BackupInfo {
  name: string;
  path: string;
  sizeBytes: number;
  /** Created time, ms since epoch. */
  createdMs: number;
}

export interface BackupSettings {
  autoBackupEnabled: boolean;
  backupPath: string;
  backupRetentionDays: number;
  lastBackupMs: number;
}

/** A saved scan snapshot (regenerable; stored for compare-over-time). */
export interface SnapshotInfo {
  scanId: string;
  rootPath: string;
  createdMs: number;
  totalBytes: number;
  totalFiles: number;
  sizeBytes: number;
}

export type ExportFormat = 'csv' | 'html' | 'json';
