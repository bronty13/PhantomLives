import { invoke } from '@tauri-apps/api/core';

// Phase 15 PR2-frontend — Hours tracker + reward milestones.

export interface ClockSession {
  id: number;
  personaCode: string | null;
  startMs: number;
  durationMs: number | null;   // null = still running
  notes: string;
  createdAt: string;
}

export interface HoursTotals {
  todayMs: number;
  weekMs: number;
  monthMs: number;
  allTimeMs: number;
  openSessionStartMs: number | null;
  openSessionId: number | null;
}

export interface RewardMilestone {
  id: number;
  hoursGoal: number;
  label: string;
  sortOrder: number;
  createdAt: string;
  updatedAt: string;
}

export interface RewardMilestoneInput {
  hoursGoal: number;
  label: string;
}

const personaArg = (code: string | null) => (code === 'ALL' || code == null ? null : code);

export async function startSession(personaCode: string | null): Promise<number> {
  return invoke<number>('hours_start_session', { personaCode: personaArg(personaCode) });
}
export async function stopSession(): Promise<number> {
  return invoke<number>('hours_stop_session');
}
export async function listSessions(limit?: number): Promise<ClockSession[]> {
  return invoke<ClockSession[]>('hours_list_sessions', { limit: limit ?? null });
}
export async function deleteSession(id: number): Promise<void> {
  await invoke<void>('hours_delete_session', { id });
}
export async function getHoursTotals(): Promise<HoursTotals> {
  // tz_offset_min — JS `getTimezoneOffset()` returns minutes WEST of UTC,
  // so negate to get the conventional "offset east of UTC" the Rust side
  // expects.
  const tzOffsetMin = -new Date().getTimezoneOffset();
  return invoke<HoursTotals>('hours_totals', { tzOffsetMin });
}

export async function listRewardMilestones(): Promise<RewardMilestone[]> {
  return invoke<RewardMilestone[]>('list_reward_milestones');
}
export async function createRewardMilestone(input: RewardMilestoneInput): Promise<number> {
  return invoke<number>('create_reward_milestone', { input });
}
export async function updateRewardMilestone(id: number, input: RewardMilestoneInput): Promise<void> {
  await invoke<void>('update_reward_milestone', { id, input });
}
export async function deleteRewardMilestone(id: number): Promise<void> {
  await invoke<void>('delete_reward_milestone', { id });
}
