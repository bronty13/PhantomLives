import { describe, expect, it } from 'vitest';
import { buildPayload, resolveQuestions } from '../src/shared/payload';
import { gradeQuestion } from '../src/shared/grading';
import type { Branding, Quiz } from '../src/shared/model';

const branding: Branding = {
  id: 'b1', name: 'Brand', updatedAt: 0,
  colors: { primary: '#111', secondary: '#222', accent: '#333', bg: '#fff', text: '#000' },
  font: { kind: 'builtin', family: 'Inter' },
};

const quiz: Quiz = {
  id: 'quiz1', name: 'Geo', introHtml: '<p>hi</p>', attempts: 3,
  randomizeQuestions: false, passingPct: 80, certificateEnabled: true, brandingId: 'b1',
  createdAt: 0, updatedAt: 0,
  questions: [
    { id: 'q1', type: 'truefalse', promptHtml: '<p>tf</p>', weight: 1, correctText: 'y', incorrectText: 'n', showCorrectAnswer: true, correct: true },
    { id: 'q2', type: 'mc', promptHtml: '<p>mc</p>', weight: 1, correctText: 'y', incorrectText: 'n', showCorrectAnswer: true, randomizeChoices: false, choices: [{ id: 'a', text: 'A' }, { id: 'b', text: 'B' }], correctChoiceId: 'b' },
    { id: 'q3', type: 'fill', promptHtml: '<p>fill</p>', weight: 1, correctText: 'y', incorrectText: 'n', showCorrectAnswer: true, caseSensitive: false, blanks: [{ id: 'bl', accepted: ['paris'] }] },
    { id: 'q4', type: 'short', promptHtml: '<p>s</p>', weight: 1, correctText: 'y', incorrectText: 'n', showCorrectAnswer: false, mode: 'text', grading: { kind: 'keyword', keywords: ['secret'], minMatches: 1 } },
  ],
};

describe('buildPayload', () => {
  const payload = buildPayload(quiz, branding, 'single', '2026-06-05T00:00:00Z');

  it('blanks all answer fields in the serialized quiz', () => {
    const serialized = JSON.stringify(payload.quiz);
    const q1 = payload.quiz.questions[0];
    const q2 = payload.quiz.questions[1];
    const q3 = payload.quiz.questions[2];
    const q4 = payload.quiz.questions[3];
    expect(q1.type === 'truefalse' && q1.correct).toBe(false);
    expect(q2.type === 'mc' && q2.correctChoiceId).toBe('');
    expect(q3.type === 'fill' && q3.blanks[0].accepted).toEqual([]);
    expect(q4.type === 'short' && q4.grading.kind === 'keyword' && q4.grading.keywords).toEqual([]);
    // No plaintext answer leaks in the serialized (blanked) quiz.
    expect(serialized).not.toContain('paris');
    expect(serialized).not.toContain('secret');
  });

  it('keeps the obfuscated answer key out of plaintext', () => {
    expect(payload.answerKey).not.toContain('paris');
    expect(payload.answerKey).not.toContain('secret');
  });

  it('round-trips to fully gradeable questions via resolveQuestions', () => {
    const resolved = resolveQuestions(payload);
    const q1 = resolved.find((q) => q.id === 'q1')!;
    const q3 = resolved.find((q) => q.id === 'q3')!;
    expect(gradeQuestion(q1, { type: 'truefalse', value: true }).correct).toBe(true);
    expect(gradeQuestion(q3, { type: 'fill', answers: { bl: 'Paris' } }).correct).toBe(true);
  });
});
