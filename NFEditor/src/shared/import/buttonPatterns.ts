// NiteFlirt payment-embed URL classification — the heart of round-trip import.
//
// A Goody/PTV / Tribute / Flirt-call button is `<a href><img></a>`. So is a plain
// image wrapped in an external link. The RELIABLE discriminator is the host: a
// NiteFlirt payment embed always points at niteflirt.com; an external linked image
// does not. We classify ONLY niteflirt.com anchors as buttons, so an Amazon/Throne
// linked image correctly falls through to a generic link+image.
//
// The SUB-type (goody vs tribute vs flirt) is a best-effort path heuristic. The
// exact NiteFlirt button URL shapes are not in the public help page; calibrate the
// PATH_RULES below against 2-3 real snippets from the "Payment Mail Buttons" screen.
// Misclassifying the sub-type is cosmetic (all three serialize to the same
// <a href><img></a> shape); misclassifying NF-vs-generic is not — that's the gate.

export type NfButtonType = 'goodyButton' | 'tributeButton' | 'flirtButton';

/** True when an href points at NiteFlirt (any subdomain). */
export function isNiteFlirtUrl(href: string): boolean {
  try {
    const u = new URL(href, 'https://www.niteflirt.com');
    return /(^|\.)niteflirt\.com$/i.test(u.hostname);
  } catch {
    return false;
  }
}

/** True for a NiteFlirt File Manager media URL (`/fm/f/{a}/{b}`). */
export function isNiteFlirtFileManagerUrl(src: string): boolean {
  try {
    const u = new URL(src, 'https://www.niteflirt.com');
    return /(^|\.)niteflirt\.com$/i.test(u.hostname) && /\/fm\/f\//i.test(u.pathname);
  } catch {
    return false;
  }
}

// Path keyword → button sub-type. First match wins; default is goody.
const PATH_RULES: Array<{ re: RegExp; type: NfButtonType }> = [
  { re: /tribut|pay(ment)?[-_]?request|\/pay\b|\/tparam/i, type: 'tributeButton' },
  { re: /listing|click[-_]?to[-_]?call|\/call\b|\/flirt|\/cmd\//i, type: 'flirtButton' },
  { re: /good(y|ies|ie)|pay[-_]?to[-_]?view|\/ptv\b|\/fm\/f\//i, type: 'goodyButton' },
];

/**
 * Classify a NiteFlirt anchor that wraps an image into a button sub-type, or
 * null if the href is NOT a NiteFlirt URL (caller should then treat it as a
 * generic link + image).
 */
export function classifyNfButton(href: string): NfButtonType | null {
  if (!isNiteFlirtUrl(href)) return null;
  let path = href;
  try {
    path = new URL(href, 'https://www.niteflirt.com').pathname + new URL(href, 'https://www.niteflirt.com').search;
  } catch {
    /* keep raw href */
  }
  for (const rule of PATH_RULES) {
    if (rule.re.test(path)) return rule.type;
  }
  return 'goodyButton';
}
