import { describe, expect, it } from 'vitest';
import { certificateBlob, generateCertificate } from '../src/shared/certificate';

describe('certificate', () => {
  const opts = {
    respondentName: 'Ada Lovelace',
    quizName: 'Intro to Logic',
    dateText: '2026-06-05 10:00',
    scorePct: 92,
    colors: { primary: '#5b2a86', accent: '#d98324', text: '#1a1a1a' },
  };

  it('builds a non-empty PDF blob', () => {
    const blob = certificateBlob(opts);
    expect(blob.size).toBeGreaterThan(500);
  });

  it('tolerates bad colors and an empty name without throwing', () => {
    expect(() =>
      generateCertificate({ ...opts, respondentName: '', colors: { primary: 'nope', accent: '', text: '#000' } }),
    ).not.toThrow();
  });
});
