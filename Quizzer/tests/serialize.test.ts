import { describe, expect, it } from 'vitest';
import { exportBundleJson, parseBundle } from '../src/creator/storage/bundle';
import type { Branding, Quiz } from '../src/shared/model';

const branding: Branding = {
  id: 'b1', name: 'Brand', updatedAt: 5,
  colors: { primary: '#111', secondary: '#222', accent: '#333', bg: '#fff', text: '#000' },
  font: { kind: 'builtin', family: 'Lora' },
};
const quiz: Quiz = {
  id: 'q1', name: 'Round Trip', introHtml: '<p>x</p>', attempts: 2, randomizeQuestions: true,
  passingPct: 70, certificateEnabled: false, brandingId: 'b1', createdAt: 1, updatedAt: 2,
  questions: [
    { id: 'qa', type: 'truefalse', promptHtml: '<p>t</p>', weight: 1, correctText: 'y', incorrectText: 'n', showCorrectAnswer: true, correct: false },
  ],
};

describe('bundle import/export', () => {
  it('round-trips quiz + branding', () => {
    const parsed = parseBundle(exportBundleJson(quiz, branding));
    expect(parsed.quiz).toEqual(quiz);
    expect(parsed.branding).toEqual(branding);
  });
  it('rejects non-JSON', () => {
    expect(() => parseBundle('not json')).toThrow();
  });
  it('rejects JSON that is not a bundle', () => {
    expect(() => parseBundle('{"foo":1}')).toThrow(/bundle/i);
  });
  it('rejects a newer schema version', () => {
    const bad = JSON.stringify({ schemaVersion: 999, quiz, branding });
    expect(() => parseBundle(bad)).toThrow(/newer/i);
  });
});
