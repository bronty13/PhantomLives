// Emoji detection — the single most important safety check in NFEditor.
//
// NiteFlirt's sanitizer has a DESTRUCTIVE failure mode: when an emoji is present,
// the emoji *and everything after it* is silently stripped on save. So we must
// detect emoji robustly and block them at input, on import, and before copy.
//
// We use Unicode property escapes, NOT a hand-rolled codepoint range list (which
// misses ZWJ family sequences, regional-indicator flags, and keycaps). We key off
// `\p{Emoji_Presentation}` (characters that render as a colorful emoji BY DEFAULT)
// rather than `\p{Extended_Pictographic}` (which also covers ©, ®, (tm), and other
// chars that are plain text unless forced to emoji with VS16). That keeps ordinary
// punctuation usable while still catching every real emoji, including a base char
// the author explicitly turns into an emoji with the VS16 (️) selector.

// Building blocks (named for clarity; all are invisible/combining code points):
const VS16 = '\\uFE0F'; // emoji-presentation selector
const ZWJ = '\\u200D'; // zero-width joiner (family/profession sequences)
const KEYCAP = '\\u20E3'; // combining enclosing keycap

// One match = one full grapheme emoji (base + optional VS16/keycap + ZWJ joins).
const EMOJI_SRC =
  `(?:\\p{Emoji_Presentation}|\\p{Extended_Pictographic}${VS16}|\\p{Regional_Indicator}{2}|[0-9#*]${VS16}?${KEYCAP})` +
  `(?:${ZWJ}(?:\\p{Emoji_Presentation}|\\p{Extended_Pictographic}${VS16}?))*`;
const EMOJI_FLAGS = 'gu';

export interface EmojiHit {
  /** UTF-16 index into the source string where the emoji starts. */
  index: number;
  /** The matched emoji grapheme(s). */
  emoji: string;
}

/** All emoji in `text`, with positions, in order. */
export function findEmoji(text: string): EmojiHit[] {
  const hits: EmojiHit[] = [];
  const re = new RegExp(EMOJI_SRC, EMOJI_FLAGS);
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    hits.push({ index: m.index, emoji: m[0] });
    if (m.index === re.lastIndex) re.lastIndex++; // guard against zero-width loops
  }
  return hits;
}

/** True if `text` contains any emoji. */
export function hasEmoji(text: string): boolean {
  return new RegExp(EMOJI_SRC, EMOJI_FLAGS).test(text);
}

/** Remove every emoji from `text` (used when stripping pasted content). */
export function stripEmoji(text: string): string {
  return text.replace(new RegExp(EMOJI_SRC, EMOJI_FLAGS), '');
}
