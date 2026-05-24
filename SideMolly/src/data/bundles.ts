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
  bundleType: 'content' | 'custom' | 'fansite';
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

export function enqueueBundleTranscripts(uid: string): Promise<EnqueueTranscriptsResult> {
  return invoke<EnqueueTranscriptsResult>('enqueue_bundle_transcripts', { uid });
}

export function listTranscripts(uid: string): Promise<TranscriptRow[]> {
  return invoke<TranscriptRow[]>('list_transcripts', { uid });
}

export function revealTranscript(uid: string, inZipPath: string): Promise<void> {
  return invoke('reveal_transcript', { uid, inZipPath });
}

export function enqueueAutoAssemble(uid: string): Promise<EnqueueAutoAssembleResult> {
  return invoke<EnqueueAutoAssembleResult>('enqueue_auto_assemble', { uid });
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

export function bundleTypeEmoji(t: BundleSummary['bundleType']): string {
  switch (t) {
    case 'content': return '🎬';
    case 'custom':  return '🎁';
    case 'fansite': return '📅';
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
