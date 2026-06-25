// Value-coding maps for scoring.
//
// The scoring engine works in numbers, but answers are stored in their native
// form (a 0–4 code for ordinal scales, a chosen label string for SINGLE items,
// an array for MULTI). This module resolves any scoring-relevant answer to a
// numeric value on the 0–4 working scale — or `null` for "missing".
//
// MISSING is the single most important correctness rule in the instrument:
// codes 97 ("unfamiliar"), 98 ("not applicable"), and 99 ("prefer not to
// answer") are MISSING, never zero. They are excluded from every numerator and
// from the "valid" count, but they still count as a *displayed* cell for the
// eligibility denominators (handled in the engine, not here).

import { itemsByVar, CODED_SCALES } from './instrument'

/** A stored answer value, as written into the data file. */
export type AnswerValue = number | string | string[] | null

/** Codes that mean "missing" on every 0–4 ordinal scale. */
export const MISSING_CODES = new Set([97, 98, 99])

export function isMissingCode(code: number): boolean {
  return MISSING_CODES.has(code)
}

// SINGLE-item coding maps. The coding lives in each item's option text; the
// published score_rules give the exact numeric mapping. Labels are matched
// case-insensitively and trimmed.

const POS_NEG_MAP: Record<string, number | null> = {
  no: 0,
  'yes, minor difficulty': 1,
  'yes, moderate difficulty': 2,
  'yes, substantial difficulty': 3,
  unsure: null,
  'prefer not to answer': null,
}

const STIGMA_MAP: Record<string, number | null> = {
  'not at all': 0,
  'a little': 1,
  moderately: 2,
  'a great deal': 3,
  extremely: 4,
  'prefer not to answer': null,
}

/** Role-axis categories (TOP##_ROLE) → classification tag. Not a numeric input. */
export const ROLE_MAP: Record<string, string | null> = {
  'mostly leading/giving': 'Leading/giving',
  'mostly receiving/following': 'Receiving/following',
  'both or versatile': 'Versatile',
  'varies by situation': 'Varies',
  'no role preference': 'No role preference/not applicable',
  'not applicable': 'No role preference/not applicable',
  'prefer not to answer': null,
}

function norm(s: string): string {
  return s.trim().toLowerCase()
}

/**
 * Resolve a scoring-relevant answer to a number on the 0–4 working scale, or
 * `null` if missing / not-applicable / prefer-not-to-answer / unanswered.
 */
export function resolveNumeric(variable: string, raw: AnswerValue): number | null {
  if (raw === null || raw === undefined) return null
  const item = itemsByVar.get(variable)
  if (!item) return null

  // WB_LIFE_SAT: a 0–10 numeric satisfaction scale, normalized to 0–4.
  if (variable === 'WB_LIFE_SAT') {
    if (typeof raw !== 'number') return null
    if (isMissingCode(raw)) return null
    if (raw < 0 || raw > 10) return null
    return (raw / 10) * 4
  }

  // TOP##_POS_NEG and TOP##_STIGMA are SINGLE items with text-coded options.
  if (variable.endsWith('_POS_NEG')) {
    return typeof raw === 'string' ? (POS_NEG_MAP[norm(raw)] ?? null) : null
  }
  if (variable.endsWith('_STIGMA')) {
    return typeof raw === 'string' ? (STIGMA_MAP[norm(raw)] ?? null) : null
  }

  // 0–4 ordinal coded scales (incl. YES_NO_SKIP, where 1/0 are valid, 99 missing).
  if (CODED_SCALES.has(item.response_type)) {
    if (typeof raw !== 'number') return null
    if (isMissingCode(raw)) return null
    return raw
  }

  return null
}

/** Reverse a 0–4 value (4 − x). Used only where the score_rules call for it. */
export function reverse(value: number | null): number | null {
  return value === null ? null : 4 - value
}

/** Mean of the non-null values, or null when there are none. */
export function meanValid(values: (number | null)[]): number | null {
  const valid = values.filter((v): v is number => v !== null)
  if (valid.length === 0) return null
  return valid.reduce((a, b) => a + b, 0) / valid.length
}
