import { db } from './db';
import type { Cadence } from '../lib/cadence';

export interface Schedule {
  id: number;
  name: string;
  personaCode: string | null;
  cadence: Cadence;
  leadTimeDays: number;
  notes: string;
  active: boolean;
  createdAt: string;
  updatedAt: string;
}

interface ScheduleRow {
  id: number;
  name: string;
  persona_code: string | null;
  cadence_json: string;
  lead_time_days: number;
  notes: string;
  active: number;
  created_at: string;
  updated_at: string;
}

function rowToSchedule(r: ScheduleRow): Schedule {
  let cadence: Cadence;
  try {
    cadence = JSON.parse(r.cadence_json) as Cadence;
  } catch {
    cadence = { kind: 'weekly', days: [1] };
  }
  return {
    id: r.id,
    name: r.name,
    personaCode: r.persona_code,
    cadence,
    leadTimeDays: r.lead_time_days,
    notes: r.notes,
    active: r.active !== 0,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  };
}

export async function listSchedules(opts?: { activeOnly?: boolean }): Promise<Schedule[]> {
  const conn = await db();
  const sql = opts?.activeOnly
    ? 'SELECT id, name, persona_code, cadence_json, lead_time_days, notes, active, created_at, updated_at FROM schedules WHERE active = 1 ORDER BY name'
    : 'SELECT id, name, persona_code, cadence_json, lead_time_days, notes, active, created_at, updated_at FROM schedules ORDER BY active DESC, name';
  const rows = await conn.select<ScheduleRow[]>(sql);
  return rows.map(rowToSchedule);
}

export async function getSchedule(id: number): Promise<Schedule | null> {
  const conn = await db();
  const rows = await conn.select<ScheduleRow[]>(
    'SELECT id, name, persona_code, cadence_json, lead_time_days, notes, active, created_at, updated_at FROM schedules WHERE id = $1',
    [id],
  );
  return rows.length === 0 ? null : rowToSchedule(rows[0]);
}

export async function createSchedule(s: Omit<Schedule, 'id' | 'createdAt' | 'updatedAt'>): Promise<number> {
  const conn = await db();
  const result = await conn.execute(
    `INSERT INTO schedules (name, persona_code, cadence_json, lead_time_days, notes, active)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [s.name, s.personaCode, JSON.stringify(s.cadence), s.leadTimeDays, s.notes, s.active ? 1 : 0],
  );
  return Number(result.lastInsertId ?? 0);
}

export async function updateSchedule(s: Schedule): Promise<void> {
  const conn = await db();
  await conn.execute(
    `UPDATE schedules SET name = $1, persona_code = $2, cadence_json = $3, lead_time_days = $4, notes = $5, active = $6, updated_at = datetime('now') WHERE id = $7`,
    [s.name, s.personaCode, JSON.stringify(s.cadence), s.leadTimeDays, s.notes, s.active ? 1 : 0, s.id],
  );
}

export async function deleteSchedule(id: number): Promise<void> {
  const conn = await db();
  await conn.execute('DELETE FROM schedules WHERE id = $1', [id]);
}
