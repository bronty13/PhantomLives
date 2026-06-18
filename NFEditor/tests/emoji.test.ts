import { describe, it, expect } from 'vitest';
import { findEmoji, hasEmoji, stripEmoji } from '../src/shared/validate/emoji';

describe('emoji detection (the destructive-truncation guard)', () => {
  it('detects a simple emoji', () => {
    expect(hasEmoji('hello 😀')).toBe(true);
  });

  it('detects a ZWJ family sequence as emoji', () => {
    expect(hasEmoji('family 👨‍👩‍👧 here')).toBe(true);
  });

  it('detects a regional-indicator flag', () => {
    expect(hasEmoji('flag 🇺🇸 here')).toBe(true);
  });

  it('detects a keycap sequence', () => {
    expect(hasEmoji('press 1️⃣ now')).toBe(true);
  });

  it('does NOT flag plain text, digits, or default-text symbols', () => {
    expect(hasEmoji('Plain text, 100% fine — call (c) 2026 me!')).toBe(false);
    expect(hasEmoji('1 2 3 # *')).toBe(false);
    expect(hasEmoji('copyright © and trademark ™ stay')).toBe(false);
  });

  it('reports positions in order', () => {
    const hits = findEmoji('a😀b🎉');
    expect(hits.map((h) => h.index)).toEqual([1, 4]);
  });

  it('strips emoji while keeping surrounding text', () => {
    expect(stripEmoji('hi 😀 there 🎉!')).toBe('hi  there !');
  });

  it('strips a whole ZWJ sequence (not just its first codepoint)', () => {
    expect(stripEmoji('x👨‍👩‍👧y')).toBe('xy');
  });
});
