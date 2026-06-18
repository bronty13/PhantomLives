// Round-trip import preparation (pure). The actual HTML -> doc-node conversion
// happens when the cleaned HTML is fed to the Tiptap editor (its node/mark
// parseHTML rules run). This module does the framework-free pre-flight:
//   1. sanitize the pasted HTML against NiteFlirt's allowlist,
//   2. report what was/will-be stripped,
//   3. scan for emoji (which NiteFlirt would use to truncate the live page).

import { sanitizeNf, buildSanitizeReport, type SanitizeReport } from '../sanitize';
import { findEmoji, type EmojiHit } from '../validate/emoji';

export interface ImportResult {
  /** Allowlist-clean HTML, ready for editor.commands.setContent(). */
  cleaned: string;
  /** What the original paste contained that NiteFlirt would strip. */
  report: SanitizeReport;
  /** Emoji found in the paste (must be resolved before save/copy). */
  emoji: EmojiHit[];
}

export function importHtml(raw: string): ImportResult {
  const report = buildSanitizeReport(raw);
  const cleaned = sanitizeNf(raw);
  const emoji = findEmoji(raw);
  return { cleaned, report, emoji };
}
