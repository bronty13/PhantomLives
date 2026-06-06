// Quiz bundle import/export — a portable JSON file (quiz + its branding) used by the
// Save/Export and Import actions on the quiz-management screen.

import type { Branding, Quiz, QuizBundle } from '../../shared/model';
import { SCHEMA_VERSION } from '../../shared/model';

export function exportBundleJson(quiz: Quiz, branding: Branding): string {
  const bundle: QuizBundle = { schemaVersion: SCHEMA_VERSION, quiz, branding };
  return JSON.stringify(bundle, null, 2);
}

export function parseBundle(json: string): QuizBundle {
  let data: unknown;
  try {
    data = JSON.parse(json);
  } catch {
    throw new Error('Not valid JSON.');
  }
  const b = data as Partial<QuizBundle>;
  if (!b || typeof b !== 'object' || !b.quiz || !b.branding) {
    throw new Error('File is not a Quizzer bundle (missing quiz or branding).');
  }
  if (!Array.isArray(b.quiz.questions)) {
    throw new Error('Bundle quiz has no questions array.');
  }
  if ((b.schemaVersion ?? 1) > SCHEMA_VERSION) {
    throw new Error('Bundle was made with a newer version of Quizzer.');
  }
  return { schemaVersion: b.schemaVersion ?? SCHEMA_VERSION, quiz: b.quiz, branding: b.branding };
}
