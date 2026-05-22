/**
 * Tiny block-level markdown parser tuned to USER_MANUAL.md.
 *
 * Ported in spirit from PurpleLife's hand-rolled `SecurityDocView.swift`
 * (which itself is a 200-line stand-in for a CommonMark library). The
 * goal is not full CommonMark — it's *"the manual is legible and the
 * links work"*. Skipping a real parser keeps Molly's bundle small and
 * the visual style 100% under our control (persona-tinted headings,
 * pastel cards, no foreign CSS).
 *
 * Supported block kinds:
 *  - H1 / H2 / H3 / H4 headings (`#`–`####`)
 *  - Unordered list items (`- ` or `* `)
 *  - Ordered list items (`N. `)
 *  - Blockquotes (`> `)
 *  - Fenced code blocks (```)
 *  - Horizontal rules (`---` or `***`)
 *  - Paragraphs (joined consecutive non-blank lines)
 *
 * Inline formatting handled by `renderInline`:
 *  - **bold** / *italic* / `inline code` / [text](url) / ~~strike~~
 *
 * Everything else falls through as plain text. HTML in the source is
 * passed through as text — we never inject raw HTML into the DOM.
 */

export type MdBlock =
  | { kind: 'h1' | 'h2' | 'h3' | 'h4'; text: string }
  | { kind: 'p'; text: string }
  | { kind: 'ul'; items: string[] }
  | { kind: 'ol'; items: string[] }
  | { kind: 'blockquote'; text: string }
  | { kind: 'code'; text: string; lang: string }
  | { kind: 'hr' };

export function parseMarkdown(text: string): MdBlock[] {
  const out: MdBlock[] = [];
  const lines = text.replace(/\r\n/g, '\n').split('\n');

  let paragraphBuffer: string[] = [];
  let ulBuffer: string[] = [];
  let olBuffer: string[] = [];
  let quoteBuffer: string[] = [];
  let inCode = false;
  let codeLang = '';
  let codeBuffer: string[] = [];

  const flushParagraph = () => {
    if (paragraphBuffer.length === 0) return;
    out.push({ kind: 'p', text: paragraphBuffer.join(' ') });
    paragraphBuffer = [];
  };
  const flushUl = () => {
    if (ulBuffer.length === 0) return;
    out.push({ kind: 'ul', items: ulBuffer });
    ulBuffer = [];
  };
  const flushOl = () => {
    if (olBuffer.length === 0) return;
    out.push({ kind: 'ol', items: olBuffer });
    olBuffer = [];
  };
  const flushQuote = () => {
    if (quoteBuffer.length === 0) return;
    out.push({ kind: 'blockquote', text: quoteBuffer.join(' ') });
    quoteBuffer = [];
  };
  const flushAllExceptParagraph = () => {
    flushUl();
    flushOl();
    flushQuote();
  };
  const flushAll = () => {
    flushParagraph();
    flushAllExceptParagraph();
  };

  for (const raw of lines) {
    // Fenced code blocks pass through verbatim (no inline parsing
    // inside). The fence line may carry an optional language hint.
    if (raw.startsWith('```')) {
      if (inCode) {
        out.push({ kind: 'code', text: codeBuffer.join('\n'), lang: codeLang });
        codeBuffer = [];
        inCode = false;
        codeLang = '';
      } else {
        flushAll();
        inCode = true;
        codeLang = raw.slice(3).trim();
      }
      continue;
    }
    if (inCode) {
      codeBuffer.push(raw);
      continue;
    }

    const trimmed = raw.trim();

    if (trimmed === '') {
      flushAll();
      continue;
    }

    if (trimmed === '---' || trimmed === '***') {
      flushAll();
      out.push({ kind: 'hr' });
      continue;
    }

    let m: RegExpExecArray | null;

    m = /^(#{1,4})\s+(.+)$/.exec(trimmed);
    if (m) {
      flushAll();
      const level = m[1].length as 1 | 2 | 3 | 4;
      const kind = (`h${level}`) as 'h1' | 'h2' | 'h3' | 'h4';
      out.push({ kind, text: m[2] });
      continue;
    }

    m = /^[-*]\s+(.+)$/.exec(trimmed);
    if (m) {
      flushParagraph();
      flushOl();
      flushQuote();
      ulBuffer.push(m[1]);
      continue;
    }

    m = /^\d+\.\s+(.+)$/.exec(trimmed);
    if (m) {
      flushParagraph();
      flushUl();
      flushQuote();
      olBuffer.push(m[1]);
      continue;
    }

    m = /^>\s?(.*)$/.exec(trimmed);
    if (m) {
      flushParagraph();
      flushUl();
      flushOl();
      quoteBuffer.push(m[1]);
      continue;
    }

    // Default — append to paragraph (flushing any open lists/quotes).
    flushAllExceptParagraph();
    paragraphBuffer.push(trimmed);
  }

  if (inCode) {
    out.push({ kind: 'code', text: codeBuffer.join('\n'), lang: codeLang });
  }
  flushAll();
  return out;
}

// --------- Inline rendering ----------------------------------------------
//
// We tokenize a single line into runs (`text` / `bold` / `italic` /
// `code` / `strike` / `link`). The order of replacement matters: code
// spans win over everything else (their contents are opaque), then
// links (because the link text may contain bold), then bold, italic,
// strike. We never produce HTML — the React renderer turns each token
// into a span/code/a element.

export type InlineToken =
  | { kind: 'text'; text: string }
  | { kind: 'bold'; text: string }
  | { kind: 'italic'; text: string }
  | { kind: 'code'; text: string }
  | { kind: 'strike'; text: string }
  | { kind: 'link'; text: string; href: string };

export function renderInline(line: string): InlineToken[] {
  // 1. Pull out code spans first (their contents are opaque).
  const codeParts: { i: number; text: string }[] = [];
  let cursor = 0;
  let working: (InlineToken | string)[] = [];
  while (cursor < line.length) {
    const start = line.indexOf('`', cursor);
    if (start === -1) {
      working.push(line.slice(cursor));
      break;
    }
    if (start > cursor) working.push(line.slice(cursor, start));
    const end = line.indexOf('`', start + 1);
    if (end === -1) {
      working.push(line.slice(start));
      break;
    }
    codeParts.push({ i: working.length, text: line.slice(start + 1, end) });
    working.push({ kind: 'code', text: line.slice(start + 1, end) });
    cursor = end + 1;
  }
  void codeParts;

  // 2. Walk every remaining string-typed slot and apply links → bold →
  // italic → strike, in that order, splitting around each match.
  const apply = (
    slot: string,
    pattern: RegExp,
    make: (m: RegExpMatchArray) => InlineToken,
  ): (InlineToken | string)[] => {
    const out: (InlineToken | string)[] = [];
    let last = 0;
    pattern.lastIndex = 0;
    let mm: RegExpExecArray | null;
    while ((mm = pattern.exec(slot)) !== null) {
      if (mm.index > last) out.push(slot.slice(last, mm.index));
      out.push(make(mm));
      last = mm.index + mm[0].length;
      if (mm[0].length === 0) pattern.lastIndex++; // safety
    }
    if (last < slot.length) out.push(slot.slice(last));
    return out;
  };

  const passes: { pattern: RegExp; make: (m: RegExpMatchArray) => InlineToken }[] = [
    {
      pattern: /\[([^\]]+)\]\(([^)]+)\)/g,
      make: (m) => ({ kind: 'link', text: m[1], href: m[2] }),
    },
    {
      pattern: /\*\*([^*]+)\*\*/g,
      make: (m) => ({ kind: 'bold', text: m[1] }),
    },
    {
      pattern: /\*([^*]+)\*/g,
      make: (m) => ({ kind: 'italic', text: m[1] }),
    },
    {
      pattern: /_([^_]+)_/g,
      make: (m) => ({ kind: 'italic', text: m[1] }),
    },
    {
      pattern: /~~([^~]+)~~/g,
      make: (m) => ({ kind: 'strike', text: m[1] }),
    },
  ];

  for (const { pattern, make } of passes) {
    const next: (InlineToken | string)[] = [];
    for (const slot of working) {
      if (typeof slot === 'string') {
        next.push(...apply(slot, pattern, make));
      } else {
        next.push(slot);
      }
    }
    working = next;
  }

  return working.map((s) =>
    typeof s === 'string' ? ({ kind: 'text', text: s } as InlineToken) : s,
  );
}
