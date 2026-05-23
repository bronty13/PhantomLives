import { invoke } from '@tauri-apps/api/core';

// Phase 14 PR2 — Global content tags + per-bundle tag links.
// Mirrors the Notes tag pattern. Tag defs are global; the join table is
// scoped to a bundle UID.

export interface ContentTag {
  id: number;
  name: string;
  color: string;       // '#RRGGBB'
  sortOrder: number;
  isBuiltin: boolean;
}

export async function listContentTags(): Promise<ContentTag[]> {
  return invoke<ContentTag[]>('list_content_tags');
}

export async function createContentTag(name: string, color: string): Promise<number> {
  return invoke<number>('create_content_tag', { name, color });
}

export async function updateContentTag(tagId: number, name: string, color: string): Promise<void> {
  await invoke<void>('update_content_tag', { tagId, name, color });
}

export async function deleteContentTag(tagId: number): Promise<void> {
  await invoke<void>('delete_content_tag', { tagId });
}

export async function listBundleTags(bundleUid: string): Promise<number[]> {
  return invoke<number[]>('list_bundle_tags', { bundleUid });
}

export async function setBundleTags(bundleUid: string, tagIds: number[]): Promise<void> {
  await invoke<void>('set_bundle_tags', { bundleUid, tagIds });
}

export async function listFanDayTags(fanDayId: number): Promise<number[]> {
  return invoke<number[]>('list_fan_day_tags', { fanDayId });
}

export async function setFanDayTags(fanDayId: number, tagIds: number[]): Promise<void> {
  await invoke<void>('set_fan_day_tags', { fanDayId, tagIds });
}

export interface FanSiteDayTag {
  date: string;          // YYYY-MM-DD
  bundleUid: string;
  personaCode: string | null;
  fanDayId: number;
  tagId: number;
  tagName: string;
  tagColor: string;
}

export async function listFanSiteDayTagsInRange(
  from: string,
  to: string,
  personaCode?: string | null,
): Promise<FanSiteDayTag[]> {
  return invoke<FanSiteDayTag[]>('list_fansite_day_tags_in_range', {
    from,
    to,
    personaCode: personaCode ?? null,
  });
}

export async function listClipTags(clipId: string): Promise<number[]> {
  return invoke<number[]>('list_clip_tags', { clipId });
}

export async function setClipTags(clipId: string, tagIds: number[]): Promise<void> {
  await invoke<void>('set_clip_tags', { clipId, tagIds });
}

export interface ClipTagInDate {
  date: string;             // YYYY-MM-DD
  clipId: string;
  personaCode: string | null;
  tagId: number;
  tagName: string;
  tagColor: string;
}

export async function listClipTagsInRange(
  from: string,
  to: string,
  personaCode?: string | null,
): Promise<ClipTagInDate[]> {
  return invoke<ClipTagInDate[]>('list_clip_tags_in_range', {
    from,
    to,
    personaCode: personaCode ?? null,
  });
}
