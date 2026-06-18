// Sanitization + strip-diff against NiteFlirt's real allowlist (vendored verbatim
// in nfAllowlist.json). Two jobs:
//   1. sanitizeNf()        — produce output NiteFlirt won't silently mutilate.
//   2. buildSanitizeReport — tell the user *what* would be stripped, and why,
//      so a pasted `<div class=...>` doesn't vanish without explanation.

import DOMPurify from 'dompurify';
import allowlist from './nfAllowlist.json';

export const ALLOWED_TAGS: string[] = [...allowlist.html4Tags, ...allowlist.html5Tags].map((t) =>
  t.toLowerCase(),
);
export const ALLOWED_ATTR: string[] = [
  ...allowlist.html4Attributes,
  ...allowlist.html5Attributes,
].map((a) => a.toLowerCase());

const ALLOWED_TAG_SET = new Set(ALLOWED_TAGS);
const ALLOWED_ATTR_SET = new Set(ALLOWED_ATTR);

/** Run HTML through DOMPurify with NiteFlirt's exact allowlist. This mirrors what
 *  the platform's own sanitizer keeps, so what the user sees is what survives. */
export function sanitizeNf(html: string): string {
  return DOMPurify.sanitize(html, {
    ALLOWED_TAGS,
    ALLOWED_ATTR,
    ALLOW_DATA_ATTR: false,
    // Keep <font>, <center>, table layout etc. — they're in NiteFlirt's allowlist.
    // No KEEP_CONTENT changes: stripped-tag *content* is preserved by default.
  });
}

export interface StripHit {
  /** The tag or attribute name that NiteFlirt would strip. */
  name: string;
  /** How many times it appears in the pasted HTML. */
  count: number;
  /** For attributes: the element tags it appeared on (for a friendlier message). */
  onTags?: string[];
}

export interface SanitizeReport {
  strippedTags: StripHit[];
  strippedAttrs: StripHit[];
  /** Human-readable one-liners ready to show in the validator panel. */
  messages: string[];
  /** True when nothing would be stripped. */
  clean: boolean;
}

/** Diff raw pasted HTML against the allowlist and describe what won't survive a
 *  NiteFlirt save. Pure DOM walk — does not depend on DOMPurify internals. */
export function buildSanitizeReport(rawHtml: string): SanitizeReport {
  const tags = new Map<string, number>();
  const attrs = new Map<string, { count: number; onTags: Set<string> }>();

  const doc = new DOMParser().parseFromString(rawHtml, 'text/html');
  const all = doc.body ? doc.body.querySelectorAll('*') : [];
  all.forEach((el) => {
    const tag = el.tagName.toLowerCase();
    if (!ALLOWED_TAG_SET.has(tag)) {
      tags.set(tag, (tags.get(tag) ?? 0) + 1);
    }
    for (const attr of Array.from(el.attributes)) {
      const an = attr.name.toLowerCase();
      // data-* and event handlers are never in the allowlist.
      const stripped = an.startsWith('data-') || an.startsWith('on') || !ALLOWED_ATTR_SET.has(an);
      if (stripped) {
        const entry = attrs.get(an) ?? { count: 0, onTags: new Set<string>() };
        entry.count += 1;
        entry.onTags.add(tag);
        attrs.set(an, entry);
      }
    }
  });

  const strippedTags: StripHit[] = [...tags.entries()]
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count);
  const strippedAttrs: StripHit[] = [...attrs.entries()]
    .map(([name, v]) => ({ name, count: v.count, onTags: [...v.onTags].sort() }))
    .sort((a, b) => b.count - a.count);

  const messages: string[] = [];
  for (const t of strippedTags) {
    messages.push(
      `<${t.name}> is not supported — the tag (and its formatting) will be stripped on save${
        t.count > 1 ? ` (×${t.count})` : ''
      }.`,
    );
  }
  for (const a of strippedAttrs) {
    const on = a.onTags && a.onTags.length ? ` on <${a.onTags.join('>, <')}>` : '';
    messages.push(
      `The \`${a.name}\` attribute${on} is not supported and will be stripped on save${
        a.count > 1 ? ` (×${a.count})` : ''
      }.`,
    );
  }

  return {
    strippedTags,
    strippedAttrs,
    messages,
    clean: strippedTags.length === 0 && strippedAttrs.length === 0,
  };
}
