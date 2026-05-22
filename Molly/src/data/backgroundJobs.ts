import { invoke } from '@tauri-apps/api/core';

// Generic background jobs runner. v1 only registered kind is 'atw_repost'.

export interface BackgroundJob {
  id: number;
  kind: string;
  name: string;
  enabled: boolean;
  cadenceSeconds: number;
  paramsJson: string;
  lastRunAt: string | null;
  nextRunAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface BackgroundJobRun {
  id: number;
  jobId: number;
  startedAt: string;
  finishedAt: string | null;
  status: 'running' | 'success' | 'failed' | 'cancelled';
  summary: string;
  logExcerpt: string;
}

export async function listBackgroundJobs(): Promise<BackgroundJob[]> {
  return invoke<BackgroundJob[]>('list_background_jobs');
}

export async function listJobRuns(jobId: number, limit = 50): Promise<BackgroundJobRun[]> {
  return invoke<BackgroundJobRun[]>('list_job_runs', { jobId, limit });
}

export async function upsertAtwJob(cadenceSeconds: number): Promise<number> {
  return invoke<number>('upsert_atw_job', { cadenceSeconds });
}

export async function setJobEnabled(jobId: number, enabled: boolean): Promise<void> {
  await invoke('set_job_enabled', { jobId, enabled });
}

export async function setJobCadence(jobId: number, cadenceSeconds: number): Promise<void> {
  await invoke('set_job_cadence', { jobId, cadenceSeconds });
}

export async function runJobNow(jobId: number): Promise<number> {
  return invoke<number>('run_job_now', { jobId });
}
