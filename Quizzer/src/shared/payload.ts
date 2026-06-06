// The window.__QUIZ__ contract: what the creator injects and the player reads.
// Correct answers are stripped out of the quiz and live only in an obfuscated
// answer key, so no plaintext answers appear anywhere in the deployed file.

import type {
  Branding,
  ID,
  Question,
  Quiz,
  ShortAnswerGrading,
} from './model';
import { SCHEMA_VERSION } from './model';
import { deobfuscate, obfuscate } from './obfuscate';

export type DeployFormat = 'single' | 'zip';

export type AnswerKeyEntry =
  | { type: 'truefalse'; correct: boolean }
  | { type: 'mc'; correctChoiceId: ID }
  | { type: 'multi'; correctChoiceIds: ID[] }
  | { type: 'fill'; accepted: Record<ID, string[]> }
  | { type: 'short'; grading: ShortAnswerGrading };

export type AnswerKey = Record<ID, AnswerKeyEntry>;

export interface DeployPayload {
  schemaVersion: number;
  format: DeployFormat;
  generatedAt: string;
  quiz: Quiz; // answer fields blanked
  branding: Branding;
  answerKey: string; // obfuscated AnswerKey
}

/** Pull the secret answer data out of a question into an answer-key entry. */
function extractEntry(q: Question): AnswerKeyEntry {
  switch (q.type) {
    case 'truefalse':
      return { type: 'truefalse', correct: q.correct };
    case 'mc':
      return { type: 'mc', correctChoiceId: q.correctChoiceId };
    case 'multi':
      return { type: 'multi', correctChoiceIds: q.correctChoiceIds };
    case 'fill': {
      const accepted: Record<ID, string[]> = {};
      for (const b of q.blanks) accepted[b.id] = b.accepted;
      return { type: 'fill', accepted };
    }
    case 'short':
      return { type: 'short', grading: q.grading };
  }
}

/** Return a structurally-valid copy of the question with answer fields blanked. */
function blankQuestion(q: Question): Question {
  switch (q.type) {
    case 'truefalse':
      return { ...q, correct: false };
    case 'mc':
      return { ...q, correctChoiceId: '' };
    case 'multi':
      return { ...q, correctChoiceIds: [] };
    case 'fill':
      return { ...q, blanks: q.blanks.map((b) => ({ ...b, accepted: [] })) };
    case 'short':
      return {
        ...q,
        grading:
          q.grading.kind === 'keyword'
            ? { kind: 'keyword', keywords: [], minMatches: q.grading.minMatches }
            : { kind: 'manual' },
      };
  }
}

/** Overlay an answer-key entry back onto a blanked question (player side). */
function applyEntry(q: Question, entry: AnswerKeyEntry): Question {
  if (q.type !== entry.type) return q;
  switch (entry.type) {
    case 'truefalse':
      return { ...(q as Extract<Question, { type: 'truefalse' }>), correct: entry.correct };
    case 'mc':
      return { ...(q as Extract<Question, { type: 'mc' }>), correctChoiceId: entry.correctChoiceId };
    case 'multi':
      return {
        ...(q as Extract<Question, { type: 'multi' }>),
        correctChoiceIds: entry.correctChoiceIds,
      };
    case 'fill': {
      const fq = q as Extract<Question, { type: 'fill' }>;
      return {
        ...fq,
        blanks: fq.blanks.map((b) => ({ ...b, accepted: entry.accepted[b.id] ?? [] })),
      };
    }
    case 'short':
      return { ...(q as Extract<Question, { type: 'short' }>), grading: entry.grading };
  }
}

/** Build the deploy payload (answers stripped + obfuscated) for a quiz + branding. */
export function buildPayload(
  quiz: Quiz,
  branding: Branding,
  format: DeployFormat,
  generatedAt: string,
): DeployPayload {
  const answerKey: AnswerKey = {};
  for (const q of quiz.questions) answerKey[q.id] = extractEntry(q);
  const blanked: Quiz = {
    ...quiz,
    questions: quiz.questions.map(blankQuestion),
  };
  return {
    schemaVersion: SCHEMA_VERSION,
    format,
    generatedAt,
    quiz: blanked,
    branding,
    answerKey: obfuscate(answerKey),
  };
}

/** Player side: reconstruct full questions (with answers) from a payload. */
export function resolveQuestions(payload: DeployPayload): Question[] {
  const key = deobfuscate<AnswerKey>(payload.answerKey);
  return payload.quiz.questions.map((q) => {
    const entry = key[q.id];
    return entry ? applyEntry(q, entry) : q;
  });
}
