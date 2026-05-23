import { invoke } from '@tauri-apps/api/core';

// Phase 9 — Content Bundler typed wrappers.
//
// Every method here is a thin wrapper around a Tauri command in
// src-tauri/src/bundles.rs. The Rust side owns ALL SQL (transactions,
// validation, hashing, file copies); we just shuttle JSON across the
// IPC boundary. The struct shapes mirror Rust's #[serde(rename_all =
// "camelCase")] response types (asserted by lib.rs::camel_case_contract).

export type BundleType = 'content' | 'custom' | 'fansite';
export type BundleState = 'draft' | 'published' | 'purged';
export type FileKind = 'video' | 'image' | 'audio';
export type AgingFlag = 'fresh' | 'aging' | 'overdue';
export type Severity = 'error' | 'warn';

export interface BundleSummary {
  uid: string;
  bundleType: BundleType;
  personaCode: string | null;
  state: BundleState;
  title: string;
  contentDate: string;
  goLiveDate: string | null;
  publishedAt: string | null;
  bundlePath: string | null;
  bundleSizeBytes: number | null;
  createdAt: string;
  updatedAt: string;
  agingFlag: AgingFlag;
  fileCount: number;
  tagIds: number[];
}

export interface BundleFileInfo {
  id: number;
  bundleUid: string;
  fansiteDayId: number | null;
  position: number;
  relpath: string;
  /** Absolute on-disk path, resolved by Rust against app_data_dir.
   *  Pass to `convertFileSrc` for inline <img>/<video> previews. */
  absolutePath: string;
  originalName: string;
  kind: FileKind;
  sizeBytes: number;
  sha256: string;
}

export interface BundleCategory {
  name: string;
  position: number;
}

export interface BundleFanDay {
  id: number;
  dayOfMonth: number;
  message: string;
  fileCount: number;
  /** Per-day tag IDs (FanSite only). Empty for non-FanSite bundles. */
  tagIds: number[];
}

export interface Bundle {
  summary: BundleSummary;
  specialInstructions: string;
  descriptionMode: 'audio' | 'text' | null;
  descriptionText: string;
  descriptionAudioRelpath: string | null;
  descriptionAudioAbsolutePath: string | null;
  descriptionAudioOriginalName: string | null;
  deliveryKind: 'site' | 'url' | null;
  deliverySiteId: number | null;
  deliveryUrl: string | null;
  deliveryRecipient: string;
  priceCents: number | null;
  handledInPlatform: boolean;
  fansiteYear: number | null;
  fansiteMonth: number | null;
  outerSha256: string | null;
  innerSha256: string | null;
  files: BundleFileInfo[];
  categories: BundleCategory[];
  fanDays: BundleFanDay[];
}

export interface BundleFieldPatch {
  // Use `undefined` to leave a field untouched. Use `null` (where the
  // type permits) to explicitly clear it. Rust's `Option<Option<T>>`
  // decoding handles this distinction.
  title?: string;
  goLiveDate?: string | null;
  specialInstructions?: string;
  descriptionMode?: 'audio' | 'text' | null;
  descriptionText?: string;
  deliveryKind?: 'site' | 'url' | null;
  deliverySiteId?: number | null;
  deliveryUrl?: string | null;
  deliveryRecipient?: string;
  priceCents?: number | null;
  handledInPlatform?: boolean;
  fansiteYear?: number | null;
  fansiteMonth?: number | null;
}

export interface BundlePublishResult {
  uid: string;
  path: string;
  sizeBytes: number;
  innerSha256: string;
  outerSha256: string;
  fileCount: number;
  clipCreated: boolean;
}

export interface PurgeResult {
  considered: number;
  purged: number;
  skippedMissing: number;
  lastRunAt: string;
}

export interface BundleArchiveRow {
  uid: string | null;
  path: string;
  filename: string;
  modifiedAt: string;
  sizeBytes: number;
}

export interface BundlerSettings {
  bundlePath: string | null;
  warnThresholdDays: number;
  purgeThresholdDays: number;
  autoPurgeEnabled: boolean;
  lastPurgeAt: string | null;
}

export interface ValidationIssueDto {
  fieldPath: string;
  message: string;
  severity: Severity;
  jumpToFieldId: string;
}

/** Discriminated error shape returned by publish_bundle when validation fails. */
export interface BundleErrorPayload {
  kind: 'error' | 'validationFailed';
  message?: string;
  count?: number;
  issues?: ValidationIssueDto[];
}

// ---------------------------------------------------------------------------
// CRUD wrappers (thin pass-through to Tauri commands)
// ---------------------------------------------------------------------------

export async function createBundle(
  bundleType: BundleType,
  personaCode: string | null,
): Promise<string> {
  return invoke<string>('create_bundle', { bundleType, personaCode });
}

export async function updateBundleFields(
  uid: string,
  patch: BundleFieldPatch,
): Promise<void> {
  await invoke('update_bundle_fields', { uid, patch });
}

export async function saveBundleFile(
  bundleUid: string,
  srcPath: string,
  kind: FileKind,
  fansiteDayId: number | null = null,
): Promise<BundleFileInfo> {
  return invoke<BundleFileInfo>('save_bundle_file', {
    bundleUid,
    srcPath,
    kind,
    fansiteDayId,
  });
}

export async function deleteBundleFile(fileId: number): Promise<void> {
  await invoke('delete_bundle_file', { fileId });
}

export async function reorderBundleFiles(
  bundleUid: string,
  orderedIds: number[],
): Promise<void> {
  await invoke('reorder_bundle_files', { bundleUid, orderedIds });
}

export async function setBundleCategories(
  bundleUid: string,
  namesInOrder: string[],
): Promise<void> {
  await invoke('set_bundle_categories', { bundleUid, namesInOrder });
}

export async function listBundles(
  state: BundleState | null = null,
): Promise<BundleSummary[]> {
  return invoke<BundleSummary[]>('list_bundles', { state });
}

export async function getBundle(uid: string): Promise<Bundle> {
  return invoke<Bundle>('get_bundle', { uid });
}

export async function deleteBundleDraft(uid: string): Promise<void> {
  await invoke('delete_bundle_draft', { uid });
}

export async function publishBundle(uid: string): Promise<BundlePublishResult> {
  return invoke<BundlePublishResult>('publish_bundle', { uid });
}

export async function deletePublishedBundle(uid: string): Promise<void> {
  await invoke('delete_published_bundle', { uid });
}

export async function listBundleArchives(): Promise<BundleArchiveRow[]> {
  return invoke<BundleArchiveRow[]>('list_bundle_archives');
}

export async function revealBundlesDir(): Promise<void> {
  await invoke('reveal_bundles_dir');
}

export async function openBundleArchive(path: string): Promise<void> {
  await invoke('open_bundle_archive', { path });
}

export async function autoPurgeOldBundles(): Promise<PurgeResult> {
  return invoke<PurgeResult>('auto_purge_old_bundles');
}

export async function getBundlerSettings(): Promise<BundlerSettings> {
  return invoke<BundlerSettings>('get_bundler_settings');
}

export async function setBundlerSettings(settings: BundlerSettings): Promise<void> {
  await invoke('set_bundler_settings', { settings });
}

export async function listProhibitedWords(): Promise<string[]> {
  return invoke<string[]>('list_prohibited_words');
}

export async function addProhibitedWord(word: string): Promise<void> {
  await invoke('add_prohibited_word', { word });
}

export async function removeProhibitedWord(word: string): Promise<void> {
  await invoke('remove_prohibited_word', { word });
}

/** FanSite: idempotent create-or-return for a given (bundle, day). */
export async function createFanDay(
  bundleUid: string,
  dayOfMonth: number,
): Promise<BundleFanDay> {
  return invoke<BundleFanDay>('create_fan_day', { bundleUid, dayOfMonth });
}

export async function updateFanDayMessage(fanDayId: number, message: string): Promise<void> {
  await invoke('update_fan_day_message', { fanDayId, message });
}

export async function deleteFanDay(fanDayId: number): Promise<void> {
  await invoke('delete_fan_day', { fanDayId });
}

/**
 * Read MasterClipper's category list (best-effort, read-only). Returns
 * empty array if MasterClipper isn't installed / its DB is unreachable.
 * Used by the bundle category picker to pre-populate suggestions with
 * Sallie's existing category vocabulary from the parent app.
 */
export async function readMasterClipperCategories(): Promise<string[]> {
  try {
    return await invoke<string[]>('read_masterclipper_categories');
  } catch {
    // Tauri-side already swallows non-fatal errors and returns an empty
    // vec; a thrown error here means the command itself is unavailable
    // (e.g. dev build without the wiring), which we also tolerate.
    return [];
  }
}
