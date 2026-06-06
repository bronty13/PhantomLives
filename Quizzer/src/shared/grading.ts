// Grading — pure functions, the single source of truth used by BOTH the creator's
// live preview and the deployed player. Operates on full Question objects (with
// answers); the player reconstructs those by merging the answer key in at boot.

import type { ID, Question } from './model';
import { MULTI_ALL_OR_NOTHING } from './model';

export type QuestionResponse =
  | { type: 'truefalse'; value: boolean | null }
  | { type: 'mc'; choiceId: ID | null }
  | { type: 'multi'; choiceIds: ID[] }
  | { type: 'fill'; answers: Record<ID, string> }
  | { type: 'short'; text: string };

export interface GradeResult {
  awarded: number;
  max: number;
  correct: boolean;
  /** True for short-answer manual questions auto-credited with no human grader. */
  selfGraded: boolean;
}

/** Trim, collapse internal whitespace, and (unless case-sensitive) lower-case. */
export function normalize(s: string, caseSensitive = false): string {
  const collapsed = s.replace(/\s+/g, ' ').trim();
  return caseSensitive ? collapsed : collapsed.toLowerCase();
}

function setEqual(a: ID[], b: ID[]): boolean {
  if (a.length !== b.length) return false;
  const sa = new Set(a);
  if (sa.size !== b.length) return false; // guard against dup selections
  return b.every((x) => sa.has(x));
}

export function gradeQuestion(q: Question, r: QuestionResponse | undefined): GradeResult {
  const max = q.weight;
  const miss: GradeResult = { awarded: 0, max, correct: false, selfGraded: false };
  if (!r || r.type !== q.type) {
    // An empty/short-answer "manual" with no response is still self-graded credit.
    if (q.type === 'short' && q.grading.kind === 'manual') {
      return { awarded: max, max, correct: true, selfGraded: true };
    }
    return miss;
  }

  switch (q.type) {
    case 'truefalse': {
      const value = (r as { value: boolean | null }).value;
      const correct = value !== null && value === q.correct;
      return { awarded: correct ? max : 0, max, correct, selfGraded: false };
    }
    case 'mc': {
      const choiceId = (r as { choiceId: ID | null }).choiceId;
      const correct = choiceId !== null && choiceId === q.correctChoiceId;
      return { awarded: correct ? max : 0, max, correct, selfGraded: false };
    }
    case 'multi': {
      const choiceIds = (r as { choiceIds: ID[] }).choiceIds ?? [];
      const correct = setEqual(choiceIds, q.correctChoiceIds);
      // MULTI_ALL_OR_NOTHING: no partial credit.
      const awarded = correct ? max : 0;
      void MULTI_ALL_OR_NOTHING;
      return { awarded, max, correct, selfGraded: false };
    }
    case 'fill': {
      const answers = (r as { answers: Record<ID, string> }).answers ?? {};
      const total = q.blanks.length;
      let hits = 0;
      for (const blank of q.blanks) {
        const given = normalize(answers[blank.id] ?? '', q.caseSensitive);
        if (given === '') continue;
        const ok = blank.accepted.some(
          (acc) => normalize(acc, q.caseSensitive) === given,
        );
        if (ok) hits += 1;
      }
      const correct = hits === total && total > 0;
      // FILL_PROPORTIONAL: award weight * (correct blanks / total blanks).
      const awarded = total === 0 ? 0 : (max * hits) / total;
      return { awarded, max, correct, selfGraded: false };
    }
    case 'short': {
      if (q.grading.kind === 'manual') {
        // SHORT_MANUAL_AUTO_CREDIT — no grader in the deployed file.
        return { awarded: max, max, correct: true, selfGraded: true };
      }
      const text = normalize((r as { text: string }).text ?? '');
      const { keywords, minMatches } = q.grading;
      const matches = keywords.filter(
        (kw) => kw.trim() !== '' && text.includes(normalize(kw)),
      ).length;
      const correct = matches >= minMatches && minMatches > 0;
      return { awarded: correct ? max : 0, max, correct, selfGraded: false };
    }
  }
}

export interface QuizScore {
  awarded: number;
  max: number;
  pct: number; // 0..100
  passed: boolean;
  perQuestion: Record<ID, GradeResult>;
  selfGradedCount: number;
}

/** Grade an entire quiz given a response map keyed by question id. */
export function gradeQuiz(
  questions: Question[],
  responses: Record<ID, QuestionResponse | undefined>,
  passingPct: number,
): QuizScore {
  const perQuestion: Record<ID, GradeResult> = {};
  let awarded = 0;
  let max = 0;
  let selfGradedCount = 0;
  for (const q of questions) {
    const res = gradeQuestion(q, responses[q.id]);
    perQuestion[q.id] = res;
    awarded += res.awarded;
    max += res.max;
    if (res.selfGraded) selfGradedCount += 1;
  }
  const pct = max === 0 ? 0 : (awarded / max) * 100;
  return {
    awarded,
    max,
    pct,
    passed: pct >= passingPct,
    perQuestion,
    selfGradedCount,
  };
}
