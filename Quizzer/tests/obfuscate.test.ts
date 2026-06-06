import { describe, expect, it } from 'vitest';
import { deobfuscate, obfuscate } from '../src/shared/obfuscate';

describe('obfuscate / deobfuscate', () => {
  it('round-trips primitives, objects, and arrays', () => {
    const value = { a: 1, b: 'two', c: [true, null, { d: 'nested' }] };
    expect(deobfuscate(obfuscate(value))).toEqual(value);
  });

  it('round-trips unicode', () => {
    const value = { emoji: '🎓✅', accents: 'café résumé naïve', cjk: '日本語' };
    expect(deobfuscate(obfuscate(value))).toEqual(value);
  });

  it('round-trips a large payload without overflowing', () => {
    const big = Array.from({ length: 50_000 }, (_, i) => ({ id: `q${i}`, answer: i % 4 }));
    expect(deobfuscate(obfuscate(big))).toEqual(big);
  });

  it('does not emit the answer as plain JSON', () => {
    const blob = obfuscate({ correctChoiceId: 'super-secret' });
    expect(blob).not.toContain('super-secret');
    expect(blob).not.toContain('correctChoiceId');
  });
});
