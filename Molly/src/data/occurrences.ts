import { db } from './db';
import { listSchedules, type Schedule } from './schedules';
import { nextOccurrencesAfter, parseIso, isoDate } from '../lib/cadence';

export interface Occurrence {
  id: number;
  scheduleId: number;
  scheduleName: string;
  personaCode: string | null;
  dueAt: string;             // ISO date YYYY-MM-DD
  completedAt: string | null;
  completionNote: string;
  attachmentPath: string | null;
  cadenceDescription?: string;
}

interface OccurrenceRow {
  id: number;
  schedule_id: number;
  due_at: string;
  completed_at: string | null;
  completion_note: string;
  attachment_path: string | null;
  schedule_name: string;
  persona_code: string | null;
}

function rowToOccurrence(r: OccurrenceRow): Occurrence {
  return {
    id: r.id,
    scheduleId: r.schedule_id,
    scheduleName: r.schedule_name,
    personaCode: r.persona_code,
    dueAt: r.due_at,
    completedAt: r.completed_at,
    completionNote: r.completion_note,
    attachmentPath: r.attachment_path,
  };
}

/**
 * Materialize occurrences for every active schedule out to `daysAhead`
 * days from today. Idempotent — UNIQUE(schedule_id, due_at) means
 * re-runs no-op for already-stamped occurrences.
 */
export async function materializeOccurrences(daysAhead = 60): Promise<{ scheduledRows: number; inserted: number }> {
  const conn = await db();
  const schedules = await listSchedules({ activeOnly: true });
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const horizon = new Date(today);
  horizon.setDate(horizon.getDate() + daysAhead);
  const horizonIso = isoDate(horizon);

  let scheduledRows = 0;
  let inserted = 0;
  for (const s of schedules) {
    // Get enough occurrences to fill the window; cap at 100 for safety.
    const candidates = nextOccurrencesAfter(s.cadence, today, 100, true);
    for (const due of candidates) {
      if (due > horizonIso) break;
      scheduledRows++;
      const res = await conn.execute(
        'INSERT OR IGNORE INTO occurrences (schedule_id, due_at) VALUES ($1, $2)',
        [s.id, due],
      );
      if (res.rowsAffected && res.rowsAffected > 0) inserted++;
    }
  }
  return { scheduledRows, inserted };
}

const OCC_SELECT = `
  SELECT o.id, o.schedule_id, o.due_at, o.completed_at, o.completion_note, o.attachment_path,
         s.name AS schedule_name, s.persona_code
  FROM occurrences o
  JOIN schedules s ON s.id = o.schedule_id
  WHERE s.active = 1`;

interface ListOpts {
  personaCode?: string;
}

function personaWhereAndParams(opts: ListOpts | undefined, startIdx: number): { whereSql: string; params: unknown[] } {
  if (!opts?.personaCode || opts.personaCode === 'ALL') return { whereSql: '', params: [] };
  return { whereSql: ` AND s.persona_code = $${startIdx}`, params: [opts.personaCode] };
}

export async function listToday(opts?: ListOpts): Promise<Occurrence[]> {
  const conn = await db();
  const today = isoDate(new Date());
  const pw = personaWhereAndParams(opts, 2);
  const rows = await conn.select<OccurrenceRow[]>(
    `${OCC_SELECT} AND o.due_at = $1 AND o.completed_at IS NULL${pw.whereSql} ORDER BY s.name`,
    [today, ...pw.params],
  );
  return rows.map(rowToOccurrence);
}

export async function listOverdue(opts?: ListOpts): Promise<Occurrence[]> {
  const conn = await db();
  const today = isoDate(new Date());
  const pw = personaWhereAndParams(opts, 2);
  const rows = await conn.select<OccurrenceRow[]>(
    `${OCC_SELECT} AND o.due_at < $1 AND o.completed_at IS NULL${pw.whereSql} ORDER BY o.due_at ASC, s.name`,
    [today, ...pw.params],
  );
  return rows.map(rowToOccurrence);
}

/**
 * Pending occurrences whose due date falls within an inclusive [from, to]
 * range. Used by the calendar to dot reminder pills onto the month grid.
 * Completed occurrences are excluded by design — the calendar shows what's
 * upcoming, not what's already done.
 */
export async function listOccurrencesInRange(from: string, to: string, opts?: ListOpts): Promise<Occurrence[]> {
  const conn = await db();
  const pw = personaWhereAndParams(opts, 3);
  const rows = await conn.select<OccurrenceRow[]>(
    `${OCC_SELECT} AND o.due_at >= $1 AND o.due_at <= $2 AND o.completed_at IS NULL${pw.whereSql} ORDER BY o.due_at ASC, s.name`,
    [from, to, ...pw.params],
  );
  return rows.map(rowToOccurrence);
}

export async function listComingUp(opts?: ListOpts, days = 7): Promise<Occurrence[]> {
  const conn = await db();
  const today = isoDate(new Date());
  const horizon = new Date();
  horizon.setDate(horizon.getDate() + days);
  const horizonIso = isoDate(horizon);
  const pw = personaWhereAndParams(opts, 3);
  const rows = await conn.select<OccurrenceRow[]>(
    `${OCC_SELECT} AND o.due_at > $1 AND o.due_at <= $2 AND o.completed_at IS NULL${pw.whereSql} ORDER BY o.due_at ASC, s.name`,
    [today, horizonIso, ...pw.params],
  );
  return rows.map(rowToOccurrence);
}

export async function listRecentlyCompleted(opts?: ListOpts, limit = 10): Promise<Occurrence[]> {
  const conn = await db();
  const pw = personaWhereAndParams(opts, 2);
  const rows = await conn.select<OccurrenceRow[]>(
    `${OCC_SELECT} AND o.completed_at IS NOT NULL${pw.whereSql} ORDER BY o.completed_at DESC LIMIT $1`,
    [limit, ...pw.params],
  );
  return rows.map(rowToOccurrence);
}

export interface CheckOffPayload {
  note?: string;
  attachmentPath?: string | null;
}

export async function checkOff(occurrenceId: number, payload: CheckOffPayload = {}): Promise<void> {
  const conn = await db();
  await conn.execute(
    `UPDATE occurrences SET completed_at = datetime('now'), completion_note = $1, attachment_path = $2 WHERE id = $3`,
    [payload.note ?? '', payload.attachmentPath ?? null, occurrenceId],
  );
}

export async function undoCheckOff(occurrenceId: number): Promise<void> {
  const conn = await db();
  await conn.execute(
    `UPDATE occurrences SET completed_at = NULL, completion_note = '', attachment_path = NULL WHERE id = $1`,
    [occurrenceId],
  );
}

export interface PendingCounts {
  todayCount: number;
  overdueCount: number;
}

export async function pendingCounts(opts?: ListOpts): Promise<PendingCounts> {
  const conn = await db();
  const today = isoDate(new Date());
  const pw = personaWhereAndParams(opts, 2);
  const todayRows = await conn.select<{ n: number }[]>(
    `SELECT COUNT(*) AS n FROM occurrences o JOIN schedules s ON s.id = o.schedule_id WHERE s.active = 1 AND o.due_at = $1 AND o.completed_at IS NULL${pw.whereSql}`,
    [today, ...pw.params],
  );
  const overdueRows = await conn.select<{ n: number }[]>(
    `SELECT COUNT(*) AS n FROM occurrences o JOIN schedules s ON s.id = o.schedule_id WHERE s.active = 1 AND o.due_at < $1 AND o.completed_at IS NULL${pw.whereSql}`,
    [today, ...pw.params],
  );
  return {
    todayCount: todayRows[0]?.n ?? 0,
    overdueCount: overdueRows[0]?.n ?? 0,
  };
}

/** Convenience: hand back a schedule joined with its next pending due date. */
export interface ScheduleWithNextDue {
  schedule: Schedule;
  nextDue: string | null;
}

export async function listSchedulesWithNextDue(): Promise<ScheduleWithNextDue[]> {
  const conn = await db();
  const schedules = await listSchedules();
  if (schedules.length === 0) return [];
  const today = isoDate(new Date());
  const rows = await conn.select<{ schedule_id: number; due_at: string }[]>(
    `SELECT schedule_id, MIN(due_at) AS due_at FROM occurrences WHERE completed_at IS NULL AND due_at >= $1 GROUP BY schedule_id`,
    [today],
  );
  const map = new Map(rows.map((r) => [r.schedule_id, r.due_at]));
  return schedules.map((s) => ({ schedule: s, nextDue: map.get(s.id) ?? null }));
}

/** Look up the cadence object behind an occurrence, for the preview "Next: …" line. */
export async function nextDueAfter(scheduleId: number, after: string): Promise<string | null> {
  const conn = await db();
  const rows = await conn.select<{ due_at: string }[]>(
    `SELECT due_at FROM occurrences WHERE schedule_id = $1 AND due_at > $2 AND completed_at IS NULL ORDER BY due_at ASC LIMIT 1`,
    [scheduleId, after],
  );
  return rows[0]?.due_at ?? null;
}

// Convenience date formatter for UI ("Today", "Tomorrow", "Mon, May 25").
export function describeDueDate(due: string): string {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const d = parseIso(due);
  d.setHours(0, 0, 0, 0);
  const diff = Math.round((d.getTime() - today.getTime()) / 86_400_000);
  if (diff === 0) return 'Today';
  if (diff === 1) return 'Tomorrow';
  if (diff === -1) return 'Yesterday';
  if (diff > 1 && diff <= 7) {
    return d.toLocaleDateString(undefined, { weekday: 'long' });
  }
  if (diff < -1) return `${-diff} days overdue`;
  return d.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
}
