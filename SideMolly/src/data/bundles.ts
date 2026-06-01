import { invoke } from '@tauri-apps/api/core';

// Mirrors src-tauri/src/bundles.rs boundary structs — camelCase contract
// enforced at cargo-test time so this file stays in lockstep.

export interface IngestResult {
  uid: string;
  bundleType: string;
  personaCode: string | null;
  title: string;
  verifyStatus: string;
  fileCount: number;
  manifestSource: 'manifest_json' | 'molly_log';
  workspacePath: string;
  extractedCount: number;
  thumbnailCount: number;
  exportThumbCount: number;
}

export interface ExportThumb {
  position: number;
  sourceInZipPath: string;
  thumbnailPath: string;
}

export interface WatchSettings {
  configuredPath: string;
  resolvedPath: string;
  usingDefault: boolean;
}

export interface ScanResult {
  scannedPath: string;
  considered: number;
  ingested: number;
  skipped: number;
  failed: number;
  errors: string[];
}

export interface BundleSummary {
  uid: string;
  bundleType: 'content' | 'custom' | 'fansite' | 'youtube';
  personaCode: string | null;
  title: string;
  ingestedAt: string;
  verifyStatus: 'pending' | 'verified' | 'failed';
  bundleState: 'new' | 'in_progress' | 'shipped' | 'archived';
  fileCount: number;
  sourceZipPath: string;
}

export interface FanDay {
  dayOfMonth: number;
  message: string;
  fileCount: number;
}

export interface BundleManifest {
  uid: string;
  bundleType: string;
  personaCode: string | null;
  title: string;
  contentDate: string | null;
  goLiveDate: string | null;
  specialInstructions: string;
  descriptionMode: string | null;
  descriptionText: string;
  descriptionAudioPath: string | null;
  categories: string[];
  deliveryKind: string | null;
  deliverySiteName: string | null;
  deliveryUrl: string | null;
  deliveryRecipient: string;
  priceCents: number | null;
  handledInPlatform: boolean;
  fansiteYear: number | null;
  fansiteMonth: number | null;
  fanDays: FanDay[];
  publishedAt: string | null;
}

export interface BundleFileRow {
  inZipPath: string;
  originalName: string;
  kind: 'video' | 'image' | 'audio' | 'info' | 'log' | 'manifest' | 'other';
  position: number;
  fansiteDayOfMonth: number | null;
  sha256: string;
  sizeBytes: number;
  workingPath: string | null;
  thumbnailPath: string | null;
  rotationDegrees: 0 | 90 | 180 | 270;
}

export interface BundleDetail {
  summary: BundleSummary;
  manifest: BundleManifest;
  files: BundleFileRow[];
}

export function ingestBundle(path: string): Promise<IngestResult> {
  return invoke<IngestResult>('ingest_bundle', { path });
}

export function listBundles(): Promise<BundleSummary[]> {
  return invoke<BundleSummary[]>('list_bundles');
}

export function getBundle(uid: string): Promise<BundleDetail> {
  return invoke<BundleDetail>('get_bundle', { uid });
}

export function revealWorkingDir(uid: string): Promise<void> {
  return invoke('reveal_working_dir', { uid });
}

export function revealWorkingFile(uid: string, inZipPath: string): Promise<void> {
  return invoke('reveal_working_file', { uid, inZipPath });
}

export function readDocText(uid: string, inZipPath: string): Promise<string> {
  return invoke<string>('read_doc_text', { uid, inZipPath });
}

export function getExportThumbnails(uid: string): Promise<ExportThumb[]> {
  return invoke<ExportThumb[]>('get_export_thumbnails', { uid });
}

/** Map<inZipPath, "data:image/jpeg;base64,…"> for every file that has a
 *  thumbnail. One IPC call instead of N asset:// URL dances. */
export function getBundleThumbnails(uid: string): Promise<Record<string, string>> {
  return invoke<Record<string, string>>('get_bundle_thumbnails', { uid });
}

// ----- Phase 3 image ops -----

export type WatermarkPosition =
  | 'top-left' | 'top-center' | 'top-right'
  | 'middle-left' | 'middle-center' | 'middle-right'
  | 'bottom-left' | 'bottom-center' | 'bottom-right';

export interface WatermarkProfile {
  personaCode: string;
  text: string;
  opacityPercent: number;
  position: WatermarkPosition;
  fontSizePct: number;
  marginPct: number;
  imageEnabled: boolean;
  videoEnabled: boolean;
}

export interface ImageOpsInput {
  watermark: boolean;
  stripExif: boolean;
  rename: boolean;
}

export interface ProcessedFileRow {
  bundleFileId: number;
  inZipPath: string;
  opKind: string;
  outputPath: string;
  createdAt: string;
}

export interface ProcessImagesResult {
  bundleUid: string;
  opKind: string;
  processed: ProcessedFileRow[];
  skipped: number;
  errors: string[];
}

export function getWatermarkProfiles(): Promise<WatermarkProfile[]> {
  return invoke<WatermarkProfile[]>('get_watermark_profiles');
}

export function setWatermarkProfile(profile: WatermarkProfile): Promise<void> {
  return invoke('set_watermark_profile', { profile });
}

export function processBundleImages(uid: string, ops: ImageOpsInput): Promise<ProcessImagesResult> {
  return invoke<ProcessImagesResult>('process_bundle_images', { uid, ops });
}

export function listProcessedFiles(uid: string): Promise<ProcessedFileRow[]> {
  return invoke<ProcessedFileRow[]>('list_processed_files', { uid });
}

export function getProcessedPreviews(uid: string): Promise<Record<string, string>> {
  return invoke<Record<string, string>>('get_processed_previews', { uid });
}

// ----- Phase 4 video ops + jobs queue -----

export interface VideoOpsInput {
  watermark: boolean;
  stripMetadata: boolean;
  rename: boolean;
}

export interface EnqueueVideoOpsResult {
  bundleUid: string;
  opKind: string;
  enqueuedCount: number;
  skipped: number;
  jobIds: number[];
  errors: string[];
}

export type JobStatus = 'pending' | 'running' | 'done' | 'failed';

export interface JobRow {
  id: number;
  kind: string;
  paramsJson: string;
  bundleUid: string | null;
  sourceInZipPath: string | null;
  status: JobStatus;
  attempts: number;
  lastError: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface JobRunRow {
  id: number;
  jobId: number;
  startedAt: string;
  finishedAt: string | null;
  exitCode: number | null;
  logPath: string | null;
}

export function enqueueBundleVideoOps(uid: string, ops: VideoOpsInput): Promise<EnqueueVideoOpsResult> {
  return invoke<EnqueueVideoOpsResult>('enqueue_bundle_video_ops', { uid, ops });
}

export function listJobs(statusFilter?: JobStatus | 'all'): Promise<JobRow[]> {
  return invoke<JobRow[]>('list_jobs', { statusFilter: statusFilter ?? null });
}

export function listJobRuns(jobId: number): Promise<JobRunRow[]> {
  return invoke<JobRunRow[]>('list_job_runs', { jobId });
}

export function revealJobOutput(jobId: number): Promise<void> {
  return invoke('reveal_job_output', { jobId });
}

export function revealProcessedFile(uid: string, inZipPath: string, opKind: string): Promise<void> {
  return invoke('reveal_processed_file', { uid, inZipPath, opKind });
}

export function setBundleFileRotation(
  uid: string,
  inZipPath: string,
  degrees: 0 | 90 | 180 | 270,
): Promise<void> {
  return invoke('set_bundle_file_rotation', { uid, inZipPath, degrees });
}

// ----- Phase 4.5 auto-assembly -----

export interface AutoAssemblySettings {
  targetWidth: number;
  targetHeight: number;
  targetFps: number;
  xfadeDurationSecs: number;
  titleDurationSecs: number;
  audioEnhanceEnabled: boolean;
  /** Phase 4.5b — runtime support lands later. */
  deepfilternetEnabled: boolean;
}

export interface EnqueueAutoAssembleResult {
  bundleUid: string;
  masterPath: string;
  jobIds: number[];
  videoCount: number;
  errors: string[];
}

export function getAutoAssemblySettings(): Promise<AutoAssemblySettings> {
  return invoke<AutoAssemblySettings>('get_auto_assembly_settings');
}

export function setAutoAssemblySettings(settings: AutoAssemblySettings): Promise<void> {
  return invoke('set_auto_assembly_settings', { settings });
}

export interface DeepFilterNetStatus {
  installed: boolean;
  binPath: string | null;
  version: string | null;
}

export function getDeepFilterNetStatus(): Promise<DeepFilterNetStatus> {
  return invoke<DeepFilterNetStatus>('get_deepfilternet_status');
}

// ----- Phase 5 transcription -----

export interface TranscribeStatus {
  installed: boolean;
  command: string | null;
  description: string | null;
  version: string | null;
}

export interface EnqueueTranscriptsResult {
  bundleUid: string;
  jobIds: number[];
  videoCount: number;
  skipped: number;
  errors: string[];
}

export interface TranscriptRow {
  bundleUid: string;
  inZipPath: string;
  stem: string;
  jsonPath: string | null;
  txtPath: string | null;
  srtPath: string | null;
  txtPreview: string | null;
}

export function getTranscribeStatus(): Promise<TranscribeStatus> {
  return invoke<TranscribeStatus>('get_transcribe_status');
}

/**
 * Enqueue transcript jobs for a bundle's videos.
 *
 * - `forceAll=false` (default): only queue videos that don't have a
 *   .txt sidecar — i.e. retry the previously-failed ones and skip the
 *   already-transcribed ones. The most common case after a partial
 *   first run.
 * - `forceAll=true`: queue every video regardless. Use when settings
 *   changed (different model, language, etc.) and you want to redo
 *   the whole batch.
 */
export function enqueueBundleTranscripts(
  uid: string,
  forceAll = false,
): Promise<EnqueueTranscriptsResult> {
  return invoke<EnqueueTranscriptsResult>('enqueue_bundle_transcripts', { uid, forceAll });
}

export function listTranscripts(uid: string): Promise<TranscriptRow[]> {
  return invoke<TranscriptRow[]>('list_transcripts', { uid });
}

export function revealTranscript(uid: string, inZipPath: string): Promise<void> {
  return invoke('reveal_transcript', { uid, inZipPath });
}

// ----- Processing log -----

export interface LogRow {
  id: number;
  timestamp: string;
  bundleUid: string | null;
  jobId: number | null;
  kind: string | null;
  level: 'info' | 'warn' | 'error';
  message: string;
  subject: string | null;
  details: string | null;
}

export interface ExportLogResult {
  bundleUid: string;
  outputPath: string;
  rowCount: number;
}

export function listLogEntries(bundleUid: string | null, limit = 500): Promise<LogRow[]> {
  return invoke<LogRow[]>('list_log_entries', { bundleUid, limit });
}

export function exportBundleLog(uid: string): Promise<ExportLogResult> {
  return invoke<ExportLogResult>('export_bundle_log', { uid });
}

export function clearBundleLog(uid: string): Promise<number> {
  return invoke<number>('clear_bundle_log', { uid });
}

export function revealBundleLog(uid: string): Promise<void> {
  return invoke('reveal_bundle_log', { uid });
}

// ----- Phase 6: Dropbox local-folder copy -----

export interface DropboxSettings {
  rootPath: string;
  template: string;
}

export interface DryRunRow {
  sourcePath: string;
  sourceSha256: string;
  sourceSizeBytes: number;
  dropboxPath: string;
  destinationName: string;
  kind: string;
  /** new | skip | changed | missing */
  status: string;
}

export interface DryRunSummary {
  bundleUid: string;
  rootConfigured: boolean;
  dropboxRoot: string;
  destinationDir: string;
  items: DryRunRow[];
}

export interface CopyResultRow {
  sourcePath: string;
  dropboxPath: string;
  /** copied | skipped | failed */
  status: string;
  verified: boolean;
  error: string | null;
}

export interface CopyResultSummary {
  bundleUid: string;
  destinationDir: string;
  copied: number;
  skipped: number;
  failed: number;
  items: CopyResultRow[];
}

export function getDropboxSettings(): Promise<DropboxSettings> {
  return invoke<DropboxSettings>('get_dropbox_settings');
}

export function setDropboxSettings(settings: DropboxSettings): Promise<void> {
  return invoke('set_dropbox_settings', { settings });
}

export function dryRunDropbox(uid: string): Promise<DryRunSummary> {
  return invoke<DryRunSummary>('dry_run_dropbox', { uid });
}

export function copyToDropbox(uid: string): Promise<CopyResultSummary> {
  return invoke<CopyResultSummary>('copy_to_dropbox', { uid });
}

export function revealDropboxDest(uid: string): Promise<void> {
  return invoke('reveal_dropbox_dest', { uid });
}

// ----- Phase 7: Posting primitives -----

export type PostingKind = 'content' | 'custom' | 'fansite' | 'youtube' | 'any';
export type PostingState = 'pending' | 'scheduled' | 'posted' | 'skipped';

export interface PostingTarget {
  id: number;
  name: string;
  urlTemplate: string;
  personaCode: string | null;
  color: string;
  icon: string;
  position: number;
  kind: PostingKind;
  enabled: boolean;
}

export interface PostingTargetInput {
  name: string;
  urlTemplate?: string;
  personaCode?: string | null;
  color?: string;
  icon?: string;
  position?: number;
  kind?: PostingKind;
  enabled?: boolean;
}

export interface BundlePosting {
  id: number;
  bundleUid: string;
  targetId: number;
  state: PostingState;
  postedAt: string | null;
  postedUrl: string | null;
  bodyOverride: string | null;
  notes: string | null;
  selectedAssetsJson: string;
  fansiteDay: number | null;
  updatedAt: string;
}

export interface PostingCard {
  target: PostingTarget;
  posting: BundlePosting | null;
  resolvedUrl: string;
}

export interface UpsertBundlePostingInput {
  bundleUid: string;
  targetId: number;
  state: PostingState;
  postedAt?: string | null;
  postedUrl?: string | null;
  bodyOverride?: string | null;
  notes?: string | null;
  selectedAssetsJson?: string | null;
  fansiteDay?: number | null;
}

export interface BundleAsset {
  kind: 'processed_image' | 'processed_video' | 'master' | 'transcript_txt' | 'transcript_srt' | string;
  path: string;
  label: string;
  sizeBytes: number;
  inZipPath: string | null;
}

// ----- Phase 13: multi-site FanSite runner -----

/** One fan-site target's posting state for a single calendar day. */
export interface FanSiteTargetDay {
  targetId: number;
  state: PostingState;
  postedAt: string | null;
  postedUrl: string | null;
  notes: string | null;
}

export interface FanSiteDay {
  dayOfMonth: number;
  message: string;
  fileCount: number;
  /** One entry per FanSitePlan.targets (same order); index by targetId. */
  targets: FanSiteTargetDay[];
}

export interface FanSitePlan {
  bundleUid: string;
  personaCode: string | null;
  title: string;
  year: number | null;
  month: number | null;
  /** Every enabled fan-site target for this persona (the roster). */
  targets: PostingTarget[];
  days: FanSiteDay[];
}

export interface PreparedDayFile {
  name: string;
  path: string;
  kind: 'image' | 'video' | 'audio' | 'other' | string;
  inZipPath: string;
}

export interface PreparedDay {
  bundleUid: string;
  dayOfMonth: number;
  folderPath: string;
  files: PreparedDayFile[];
  processedCount: number;
  skippedCount: number;
  errors: string[];
}

export interface PostingLogRow {
  id: number;
  bundleUid: string;
  targetId: number | null;
  targetName: string;
  personaCode: string | null;
  fansiteDay: number | null;
  title: string | null;
  action: 'posted' | 'unposted' | 'reset';
  postedUrl: string | null;
  details: string | null;
  loggedAt: string;
}

export interface SetFanSiteDayInput {
  bundleUid: string;
  targetId: number;
  fansiteDay: number;
  state: PostingState;
  postedUrl?: string | null;
  notes?: string | null;
}

export function listPostingTargets(): Promise<PostingTarget[]> {
  return invoke<PostingTarget[]>('list_posting_targets');
}

export function createPostingTarget(target: PostingTargetInput): Promise<number> {
  return invoke<number>('create_posting_target', { target });
}

export function updatePostingTarget(id: number, target: PostingTargetInput): Promise<void> {
  return invoke('update_posting_target', { id, target });
}

export function deletePostingTarget(id: number): Promise<void> {
  return invoke('delete_posting_target', { id });
}

export function listBundlePostings(uid: string): Promise<PostingCard[]> {
  return invoke<PostingCard[]>('list_bundle_postings', { uid });
}

export function upsertBundlePosting(input: UpsertBundlePostingInput): Promise<void> {
  return invoke('upsert_bundle_posting', { input });
}

export function markPosted(
  bundleUid: string,
  targetId: number,
  postedUrl: string | null,
  fansiteDay: number | null = null,
): Promise<void> {
  return invoke('mark_posted', { bundleUid, targetId, postedUrl, fansiteDay });
}

export function listBundleAssets(uid: string): Promise<BundleAsset[]> {
  return invoke<BundleAsset[]>('list_bundle_assets', { uid });
}

// ----- Phase 13: multi-site FanSite runner -----

export function getFanSitePlan(uid: string): Promise<FanSitePlan> {
  return invoke<FanSitePlan>('get_fansite_plan', { uid });
}

/** Create the canonical per-persona fan-site roster (idempotent).
 *  Returns the full target list afterward. */
export function seedFanSiteTargets(): Promise<PostingTarget[]> {
  return invoke<PostingTarget[]>('seed_fansite_targets');
}

/** Stage one day's media into a dedicated folder (rotate + strip EXIF,
 *  no watermark) and return the folder path + file list. */
export function prepareFanSiteDay(uid: string, day: number): Promise<PreparedDay> {
  return invoke<PreparedDay>('prepare_fansite_day', { uid, day });
}

export function revealFanSiteDay(uid: string, day: number): Promise<void> {
  return invoke('reveal_fansite_day', { uid, day });
}

/** Upsert one (bundle, target, day) posting cell. Writes a posting_log
 *  row when the cell flips to/from posted. */
export function setFanSiteDay(input: SetFanSiteDayInput): Promise<void> {
  return invoke('set_fansite_day', { input });
}

/** Unwind one site (targetId set) or the whole bundle (targetId null). */
export function resetFanSitePostings(uid: string, targetId: number | null = null): Promise<void> {
  return invoke('reset_fansite_postings', { uid, targetId });
}

export function listPostingLog(uid: string): Promise<PostingLogRow[]> {
  return invoke<PostingLogRow[]>('list_posting_log', { uid });
}

// ----- Phase 11: post-bundle return trip -----

export interface ComposeResult {
  bundleUid: string;
  outputPath: string;
  innerZipSha256: string;
  outerZipSha256: string;
  targetCount: number;
  artifactCount: number;
  bytesWritten: number;
}

export interface PostBundleStatus {
  bundleUid: string;
  outputPath: string;
  exists: boolean;
  sizeBytes: number;
  modifiedAt: string | null;
}

export function composePostBundle(uid: string): Promise<ComposeResult> {
  return invoke<ComposeResult>('compose_post_bundle', { uid });
}

export function getPostBundleStatus(uid: string): Promise<PostBundleStatus> {
  return invoke<PostBundleStatus>('get_post_bundle_status', { uid });
}

export function revealPostBundle(uid: string): Promise<void> {
  return invoke('reveal_post_bundle', { uid });
}

// ----- Phase 12: Jobs panel ops -----

export function retryJob(id: number): Promise<void> {
  return invoke('retry_job', { id });
}

export function cancelPendingJob(id: number): Promise<void> {
  return invoke('cancel_pending_job', { id });
}

export function clearJobsByStatus(statuses: JobStatus[]): Promise<number> {
  return invoke<number>('clear_jobs_by_status', { statuses });
}

export function getWorkerPaused(): Promise<boolean> {
  return invoke<boolean>('get_worker_paused');
}

export function setWorkerPaused(paused: boolean): Promise<void> {
  return invoke('set_worker_paused', { paused });
}

/** Output orientation for the auto-assembled master cut. The bundle's
 *  clips can't be assumed to all be landscape or all portrait, so the
 *  user picks per-bundle on the Edit tab. `'auto'` lets the backend
 *  probe the clips and pick the majority orientation. */
export type AssemblyFormat = 'auto' | 'horizontal' | 'vertical';
/** What `'auto'` resolves to — never `'auto'` itself. */
export type DetectedFormat = 'horizontal' | 'vertical';

export function enqueueAutoAssemble(
  uid: string,
  format: AssemblyFormat = 'auto',
): Promise<EnqueueAutoAssembleResult> {
  return invoke<EnqueueAutoAssembleResult>('enqueue_auto_assemble', { uid, format });
}

/** Probe the bundle's clips and report the auto-detected orientation. */
export function detectBundleFormat(uid: string): Promise<DetectedFormat> {
  return invoke<DetectedFormat>('detect_bundle_format', { uid });
}

export interface ClearProcessingResult {
  processedRows: number;
  jobRows: number;
  logRows: number;
  dirsRemoved: string[];
}

/** Testing aid — wipe a bundle's regenerable processing outputs
 *  (auto/processed/transcripts dirs + DB rows) without re-ingesting. */
export function clearBundleProcessing(uid: string): Promise<ClearProcessingResult> {
  return invoke<ClearProcessingResult>('clear_bundle_processing', { uid });
}

export interface MasterCutStatus {
  bundleUid: string;
  masterPath: string;
  exists: boolean;
  sizeBytes: number;
  modifiedAt: string | null;
}

export function getMasterCutStatus(uid: string): Promise<MasterCutStatus> {
  return invoke<MasterCutStatus>('get_master_cut_status', { uid });
}

export function revealMasterCut(uid: string): Promise<void> {
  return invoke('reveal_master_cut', { uid });
}

export function openMasterCut(uid: string): Promise<void> {
  return invoke('open_master_cut', { uid });
}

export function getWatchSettings(): Promise<WatchSettings> {
  return invoke<WatchSettings>('get_watch_settings');
}

export function setWatchDir(path: string | null): Promise<WatchSettings> {
  return invoke<WatchSettings>('set_watch_dir', { path });
}

export function scanWatchDirNow(): Promise<ScanResult> {
  return invoke<ScanResult>('scan_watch_dir_now');
}

export function revealWatchDir(): Promise<void> {
  return invoke('reveal_watch_dir');
}

// ----- presentation helpers used in multiple views -----

export function personaChipColor(code: string | null): { bg: string; fg: string; label: string } {
  switch (code) {
    case 'CoC': return { bg: 'rgb(var(--persona-coc) / 0.30)', fg: '#5B2540', label: 'CoC' };
    case 'PoA': return { bg: 'rgb(var(--persona-poa) / 0.30)', fg: '#7A0000', label: 'PoA' };
    case 'Sa':  return { bg: 'rgb(var(--persona-sa) / 0.30)',  fg: '#3A2F22', label: 'Sa'  };
    default:    return { bg: 'rgb(var(--surface-border))', fg: 'rgb(var(--surface-muted))', label: '—' };
  }
}

export function bundleTypeEmoji(t: string): string {
  switch (t) {
    case 'content': return '🎬';
    case 'custom':  return '🎁';
    case 'fansite': return '📅';
    case 'youtube': return '▶️';
    // Forward-compat: any future Molly type still gets a usable glyph
    // instead of rendering `undefined`.
    default:        return '📦';
  }
}

export function verifyStatusBadge(s: BundleSummary['verifyStatus']): { glyph: string; tone: string } {
  switch (s) {
    case 'verified': return { glyph: '✓', tone: '#1f9d55' };
    case 'failed':   return { glyph: '⚠', tone: '#c4252e' };
    case 'pending':  return { glyph: '…', tone: 'rgb(var(--surface-muted))' };
  }
}

export function fmtPrice(cents: number | null, handledInPlatform: boolean): string {
  if (handledInPlatform) return 'handled in-platform';
  if (cents == null) return '—';
  return `$${(cents / 100).toFixed(2)}`;
}

export function fmtSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}
