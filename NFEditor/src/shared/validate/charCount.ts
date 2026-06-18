// Live character counter. Critical detail: it counts the SERIALIZED output of the
// ACTIVE mode (legacy <table>/<font> eats far more characters than compact), not
// the doc JSON size or editor.getHTML(). Counting the wrong thing lets a user blow
// NiteFlirt's hard limit and silently lose content on save.

import type { DocNode, DocType, OutputMode } from '../model';
import { CHAR_LIMITS } from '../model';
import { serialize } from '../serialize';

export type CountLevel = 'ok' | 'warn' | 'over';

export interface CharCountStatus {
  count: number;
  limit: number;
  remaining: number;
  /** 0..1 fraction of the limit used (capped at 1 for the bar). */
  fraction: number;
  level: CountLevel;
}

/** Classify a raw count against a doc-type limit. `warn` at 90%. */
export function classifyCount(count: number, docType: DocType): CharCountStatus {
  const limit = CHAR_LIMITS[docType];
  const remaining = limit - count;
  const fraction = Math.min(1, count / limit);
  const level: CountLevel = count > limit ? 'over' : fraction >= 0.9 ? 'warn' : 'ok';
  return { count, limit, remaining, fraction, level };
}

/** Serialize the doc in the active mode and classify its length. */
export function charCountStatus(doc: DocNode, mode: OutputMode, docType: DocType): CharCountStatus {
  return classifyCount(serialize(doc, mode).length, docType);
}
