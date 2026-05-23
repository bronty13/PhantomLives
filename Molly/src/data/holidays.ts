import { invoke } from '@tauri-apps/api/core';

// Phase 14 PR1 — Holidays typed wrappers.
// Rust owns CRUD + the US-default reset path; we just shuttle JSON.
// The resolver (lib/holidayResolver.ts) takes this list and converts
// it to concrete ISO dates per visible calendar month.

export type HolidayKind = 'fixed' | 'nth_weekday';
export type HolidaySource = 'us_default' | 'custom';

export interface Holiday {
  id: number;
  name: string;
  kind: HolidayKind;
  month: number;            // 1..12
  day: number | null;       // for 'fixed'
  weekday: number | null;   // for 'nth_weekday': 0=Sun..6=Sat
  nth: number | null;       // 1..4 or -1=last
  colorPrimary: string;
  colorSecondary: string | null;
  colorText: string;
  emoji: string | null;
  enabled: boolean;
  source: HolidaySource;
  createdAt: string;
  updatedAt: string;
}

export interface HolidayInput {
  name: string;
  kind: HolidayKind;
  month: number;
  day: number | null;
  weekday: number | null;
  nth: number | null;
  colorPrimary: string;
  colorSecondary: string | null;
  colorText: string;
  emoji: string | null;
  enabled: boolean;
}

export async function listHolidays(): Promise<Holiday[]> {
  return invoke<Holiday[]>('list_holidays');
}

export async function createHoliday(input: HolidayInput): Promise<number> {
  return invoke<number>('create_holiday', { input });
}

export async function updateHoliday(id: number, input: HolidayInput): Promise<void> {
  await invoke<void>('update_holiday', { id, input });
}

export async function setHolidayEnabled(id: number, enabled: boolean): Promise<void> {
  await invoke<void>('set_holiday_enabled', { id, enabled });
}

export async function deleteHoliday(id: number): Promise<void> {
  await invoke<void>('delete_holiday', { id });
}

export async function resetHolidaysToUSDefaults(): Promise<number> {
  return invoke<number>('reset_holidays_to_us_defaults');
}
