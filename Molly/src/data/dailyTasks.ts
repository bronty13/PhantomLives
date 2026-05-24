import { invoke } from '@tauri-apps/api/core';

// Phase 15 PR3-frontend — Daily to-do list.

export type DailyCategory = 'reddit' | 'youtube' | 'content' | 'admin' | 'other';

export interface DailyTask {
  id: number;
  personaCode: string | null;
  forDate: string;        // YYYY-MM-DD
  text: string;
  category: DailyCategory;
  doneAt: string | null;
  sortOrder: number;
  createdAt: string;
}

export interface DailyTaskInput {
  personaCode: string | null;
  forDate: string;
  text: string;
  category: DailyCategory;
}

const personaArg = (code: string | null) => (code === 'ALL' || code == null ? null : code);

export async function listDailyTasks(forDate: string, personaCode: string | null): Promise<DailyTask[]> {
  return invoke<DailyTask[]>('list_daily_tasks', {
    forDate,
    personaCode: personaArg(personaCode),
  });
}
export async function createDailyTask(input: DailyTaskInput): Promise<number> {
  return invoke<number>('create_daily_task', { input });
}
export async function completeDailyTask(id: number): Promise<void> {
  await invoke<void>('complete_daily_task', { id });
}
export async function undoDailyTask(id: number): Promise<void> {
  await invoke<void>('undo_daily_task', { id });
}
export async function deleteDailyTask(id: number): Promise<void> {
  await invoke<void>('delete_daily_task', { id });
}

export async function reorderDailyTasks(orderedIds: number[]): Promise<void> {
  await invoke<void>('reorder_daily_tasks', { orderedIds });
}

/** Current local-date YYYY-MM-DD — matches what the Rust validator expects. */
export function todayIso(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
