import { invoke } from '@tauri-apps/api/core';
import { db } from './db';
import type { PersonaCode } from '../lib/c4sClassify';

export interface C4SClip {
  clipId: string;
  personaCode: PersonaCode;
  clipStatus: string;
  clipTrackingTag: string;
  clipTitle: string;
  clipDescription: string;
  categories: string;          // comma-joined; UI splits on ", "
  keywords: string;
  clipFilename: string;
  clipThumbnail: string;
  clipPreview: string;
  performers: string;
  priceCents: number | null;
  salesCount: number | null;
  income6moCents: number | null;
  importedAt: string;
}

interface C4SClipRow {
  clip_id: string;
  persona_code: PersonaCode;
  clip_status: string;
  clip_tracking_tag: string;
  clip_title: string;
  clip_description: string;
  categories: string;
  keywords: string;
  clip_filename: string;
  clip_thumbnail: string;
  clip_preview: string;
  performers: string;
  price_cents: number | null;
  sales_count: number | null;
  income_6mo_cents: number | null;
  imported_at: string;
}

function rowToClip(r: C4SClipRow): C4SClip {
  return {
    clipId: r.clip_id,
    personaCode: r.persona_code,
    clipStatus: r.clip_status,
    clipTrackingTag: r.clip_tracking_tag,
    clipTitle: r.clip_title,
    clipDescription: r.clip_description,
    categories: r.categories,
    keywords: r.keywords,
    clipFilename: r.clip_filename,
    clipThumbnail: r.clip_thumbnail,
    clipPreview: r.clip_preview,
    performers: r.performers,
    priceCents: r.price_cents,
    salesCount: r.sales_count,
    income6moCents: r.income_6mo_cents,
    importedAt: r.imported_at,
  };
}

const SELECT_COLS =
  'clip_id, persona_code, clip_status, clip_tracking_tag, clip_title, clip_description, categories, keywords, clip_filename, clip_thumbnail, clip_preview, performers, price_cents, sales_count, income_6mo_cents, imported_at';

export interface ListC4SClipsOpts {
  personaCode?: PersonaCode;        // undefined / 'ALL' → both stores
}

export async function listC4SClips(opts: ListC4SClipsOpts = {}): Promise<C4SClip[]> {
  const conn = await db();
  const params: unknown[] = [];
  let sql = `SELECT ${SELECT_COLS} FROM c4s_clips WHERE 1=1`;
  if (opts.personaCode === 'CoC' || opts.personaCode === 'PoA') {
    params.push(opts.personaCode);
    sql += ` AND persona_code = $${params.length}`;
  }
  sql += ' ORDER BY clip_id DESC';
  const rows = await conn.select<C4SClipRow[]>(sql, params);
  return rows.map(rowToClip);
}

export async function getC4SClip(personaCode: PersonaCode, clipId: string): Promise<C4SClip | null> {
  const conn = await db();
  const rows = await conn.select<C4SClipRow[]>(
    `SELECT ${SELECT_COLS} FROM c4s_clips WHERE persona_code = $1 AND clip_id = $2`,
    [personaCode, clipId],
  );
  return rows.length === 0 ? null : rowToClip(rows[0]);
}

// ---------- Aggregates for the dashboard ----------

export interface C4SCounts {
  total: number;
  byStatus: { status: string; count: number }[];
  byPersona: { personaCode: PersonaCode; count: number }[];
  topCategories: { name: string; count: number }[];
  topKeywords: { name: string; count: number }[];
  priceMinCents: number | null;
  priceMaxCents: number | null;
  priceMeanCents: number | null;
  salesTotal: number;
  income6moTotalCents: number;
  clipsWithSales: number;
}

function splitList(raw: string): string[] {
  return raw
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

export async function c4sCounts(personaCode?: PersonaCode | 'ALL'): Promise<C4SCounts> {
  const conn = await db();
  const params: unknown[] = [];
  let where = 'WHERE 1=1';
  if (personaCode === 'CoC' || personaCode === 'PoA') {
    params.push(personaCode);
    where += ` AND persona_code = $${params.length}`;
  }

  const totalRow = await conn.select<{ n: number }[]>(
    `SELECT COUNT(*) AS n FROM c4s_clips ${where}`,
    params,
  );
  const total = totalRow[0]?.n ?? 0;

  const byStatusRows = await conn.select<{ s: string; n: number }[]>(
    `SELECT clip_status AS s, COUNT(*) AS n FROM c4s_clips ${where} GROUP BY clip_status ORDER BY n DESC`,
    params,
  );
  const byStatus = byStatusRows.map((r) => ({ status: r.s, count: r.n }));

  const byPersonaRows = await conn.select<{ p: PersonaCode; n: number }[]>(
    `SELECT persona_code AS p, COUNT(*) AS n FROM c4s_clips ${where} GROUP BY persona_code ORDER BY n DESC`,
    params,
  );
  const byPersona = byPersonaRows.map((r) => ({ personaCode: r.p, count: r.n }));

  // Categories / keywords are comma-joined strings — split client-side. For
  // the row counts Sallie has today (≤1000), this is far cheaper than a
  // recursive CTE.
  const catRows = await conn.select<{ categories: string }[]>(
    `SELECT categories FROM c4s_clips ${where}`,
    params,
  );
  const catCounts = new Map<string, number>();
  for (const r of catRows) for (const c of splitList(r.categories)) catCounts.set(c, (catCounts.get(c) ?? 0) + 1);
  const topCategories = [...catCounts.entries()]
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 10);

  const kwRows = await conn.select<{ keywords: string }[]>(
    `SELECT keywords FROM c4s_clips ${where}`,
    params,
  );
  const kwCounts = new Map<string, number>();
  for (const r of kwRows) for (const k of splitList(r.keywords)) kwCounts.set(k, (kwCounts.get(k) ?? 0) + 1);
  const topKeywords = [...kwCounts.entries()]
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 10);

  const priceRow = await conn.select<{ mn: number | null; mx: number | null; av: number | null }[]>(
    `SELECT MIN(price_cents) AS mn, MAX(price_cents) AS mx, AVG(price_cents) AS av FROM c4s_clips ${where} AND price_cents IS NOT NULL`,
    params,
  );

  const salesRow = await conn.select<{ s: number | null; i: number | null; n: number }[]>(
    `SELECT COALESCE(SUM(sales_count), 0) AS s,
            COALESCE(SUM(income_6mo_cents), 0) AS i,
            COALESCE(SUM(CASE WHEN sales_count IS NOT NULL THEN 1 ELSE 0 END), 0) AS n
     FROM c4s_clips ${where}`,
    params,
  );

  return {
    total,
    byStatus,
    byPersona,
    topCategories,
    topKeywords,
    priceMinCents: priceRow[0]?.mn ?? null,
    priceMaxCents: priceRow[0]?.mx ?? null,
    priceMeanCents: priceRow[0]?.av != null ? Math.round(priceRow[0]!.av!) : null,
    salesTotal: salesRow[0]?.s ?? 0,
    income6moTotalCents: salesRow[0]?.i ?? 0,
    clipsWithSales: salesRow[0]?.n ?? 0,
  };
}

export interface C4SImportRow {
  personaCode: PersonaCode;
  sourceFile: string;
  rowCount: number;
  importedAt: string;
}

export async function c4sLastImports(): Promise<C4SImportRow[]> {
  const conn = await db();
  const rows = await conn.select<{
    persona_code: PersonaCode;
    source_file: string;
    row_count: number;
    imported_at: string;
  }[]>(
    `SELECT persona_code, source_file, row_count, imported_at
     FROM c4s_imports c
     WHERE imported_at = (SELECT MAX(imported_at) FROM c4s_imports WHERE persona_code = c.persona_code)
     ORDER BY persona_code`,
  );
  return rows.map((r) => ({
    personaCode: r.persona_code,
    sourceFile: r.source_file,
    rowCount: r.row_count,
    importedAt: r.imported_at,
  }));
}

export async function c4sLastImportFor(personaCode: PersonaCode): Promise<C4SImportRow | null> {
  const conn = await db();
  const rows = await conn.select<{
    persona_code: PersonaCode;
    source_file: string;
    row_count: number;
    imported_at: string;
  }[]>(
    `SELECT persona_code, source_file, row_count, imported_at
     FROM c4s_imports
     WHERE persona_code = $1
     ORDER BY imported_at DESC
     LIMIT 1`,
    [personaCode],
  );
  if (rows.length === 0) return null;
  return {
    personaCode: rows[0].persona_code,
    sourceFile: rows[0].source_file,
    rowCount: rows[0].row_count,
    importedAt: rows[0].imported_at,
  };
}

// ---------- Mutations go through Tauri commands (atomic transactions) ----

export interface ReplaceResult {
  personaCode: PersonaCode;
  deletedCount: number;
  insertedCount: number;
  expectedCount: number;
  matches: boolean;
  importedAt: string;
}

export interface C4SClipDto {
  clipId: string;
  clipStatus: string;
  clipTrackingTag: string;
  clipTitle: string;
  clipDescription: string;
  categories: string;
  keywords: string;
  clipFilename: string;
  clipThumbnail: string;
  clipPreview: string;
  performers: string;
  priceCents: number | null;
  salesCount: number | null;
  income6moCents: number | null;
}

export async function replaceC4SClips(
  personaCode: PersonaCode,
  sourceFile: string,
  rows: C4SClipDto[],
): Promise<ReplaceResult> {
  return invoke<ReplaceResult>('replace_c4s_clips', {
    personaCode,
    sourceFile,
    rows,
  });
}

export interface DeleteAllResult {
  deletedClips: number;
  deletedImports: number;
}

export async function deleteAllC4SData(): Promise<DeleteAllResult> {
  return invoke<DeleteAllResult>('delete_all_c4s_data');
}
