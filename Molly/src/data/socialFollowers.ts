// v1.25.0 — daily follower-count tracking (frontend wrappers around the
// Rust commands in src-tauri/src/social_followers.rs).
//
// SNAPSHOT semantics: one absolute number per (persona, platform, day),
// UPSERT-latest-wins. A missing day is a gap, not zero. Persona-scoped
// like the piggy bank; the ALL view uses the combined endpoint.

import { invoke } from '@tauri-apps/api/core';

export { todayIsoLocal } from './socialDrops';

export interface PlatformFollowerToday {
  platformId: number;
  name: string;
  shortCode: string;
  icon: string;
  color: string;
  sortOrder: number;
  followerGoal: number;
  latestCount: number | null;
  latestDate: string | null;
  todayCount: number | null;
  prevCount: number | null;
  delta: number | null;
  goalHit: boolean;
}

export interface FollowerHistoryEntry {
  date: string;
  count: number | null;
  isLogged: boolean;
}

export interface LoggedPoint {
  date: string;
  count: number;
}

export interface FollowerUpsertResult {
  personaCode: string;
  platformId: number;
  countDate: string;
  followerCount: number;
  prevCount: number | null;
  delta: number | null;
  followerGoal: number;
  goalHit: boolean;
  justHitGoal: boolean;
}

export interface PersonaFollowerSlice {
  personaCode: string;
  personaName: string;
  latestCount: number | null;
  latestDate: string | null;
}

export interface CombinedFollowerToday {
  platformId: number;
  name: string;
  shortCode: string;
  icon: string;
  color: string;
  sortOrder: number;
  followerGoal: number;
  combinedLatest: number | null;
  contributingPersonas: number;
  breakdown: PersonaFollowerSlice[];
}

export interface FollowerInput {
  personaCode: string | null;
  platformId: number;
  countDate: string;
  followerCount: number;
}

export function upsertFollowerCount(input: FollowerInput): Promise<FollowerUpsertResult> {
  return invoke('upsert_follower_count', { input });
}

export function listFollowersToday(
  personaCode: string | null,
  date: string,
): Promise<PlatformFollowerToday[]> {
  return invoke('list_followers_today', { personaCode, date });
}

export function listFollowerHistory(
  personaCode: string | null,
  platformId: number,
  endDate: string,
  days: number,
): Promise<FollowerHistoryEntry[]> {
  return invoke('list_follower_history', { personaCode, platformId, endDate, days });
}

export function listLoggedFollowerHistory(
  personaCode: string | null,
  platformId: number,
  endDate: string,
): Promise<LoggedPoint[]> {
  return invoke('list_logged_follower_history', { personaCode, platformId, endDate });
}

export function listCombinedFollowersToday(date: string): Promise<CombinedFollowerToday[]> {
  return invoke('list_combined_followers_today', { date });
}

export function setSocialPlatformFollowerGoal(platformId: number, followerGoal: number): Promise<void> {
  return invoke('set_social_platform_follower_goal', { platformId, followerGoal });
}

export function deleteFollowerCount(
  personaCode: string | null,
  platformId: number,
  countDate: string,
): Promise<boolean> {
  return invoke('delete_follower_count', { personaCode, platformId, countDate });
}
