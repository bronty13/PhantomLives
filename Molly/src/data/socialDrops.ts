// v1.21.0 — Social-hub piggy-bank tracker (frontend wrappers around
// the Rust commands in src-tauri/src/social_drops.rs).
//
// All counts are persona-scoped to match Reddit's existing behaviour.
// `personaCode === null` means ALL — no rows match because every drop
// is tied to a specific persona (see Rust pure_list_today).

import { invoke } from '@tauri-apps/api/core';

export interface PlatformToday {
  platformId: number;
  name: string;
  shortCode: string;
  icon: string;
  color: string;
  sortOrder: number;
  dailyGoal: number;
  count: number;
  hit: boolean;
}

export interface DayHistoryEntry {
  date: string;
  count: number;
  goal: number;
}

export interface DropResult {
  id: number;
  newCount: number;
  goal: number;
  hit: boolean;
  justHit: boolean;
}

export interface DropInput {
  personaCode: string | null;
  platformId: number;
  postedDate: string;
}

export function todayIsoLocal(): string {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${dd}`;
}

export function listSocialToday(
  personaCode: string | null,
  postedDate: string,
): Promise<PlatformToday[]> {
  return invoke('list_social_today', { personaCode, postedDate });
}

export function addSocialDrop(input: DropInput): Promise<DropResult> {
  return invoke('add_social_drop', { input });
}

export function undoLastSocialDrop(
  personaCode: string | null,
  platformId: number,
  postedDate: string,
): Promise<boolean> {
  return invoke('undo_last_social_drop', { personaCode, platformId, postedDate });
}

export function listSocialPlatformHistory(
  personaCode: string | null,
  platformId: number,
  endDate: string,
  days: number,
): Promise<DayHistoryEntry[]> {
  return invoke('list_social_platform_history', {
    personaCode,
    platformId,
    endDate,
    days,
  });
}

export function computeSocialOverallStreak(
  personaCode: string | null,
  endDate: string,
): Promise<number> {
  return invoke('compute_social_overall_streak', { personaCode, endDate });
}

export function computeSocialPlatformStreak(
  personaCode: string | null,
  platformId: number,
  endDate: string,
): Promise<number> {
  return invoke('compute_social_platform_streak', { personaCode, platformId, endDate });
}

export function setSocialPlatformGoal(platformId: number, dailyGoal: number): Promise<void> {
  return invoke('set_social_platform_goal', { platformId, dailyGoal });
}
