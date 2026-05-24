// Tiny markdown renderer used by the DocDrawer for info.md previews.
// Handles: headings (# / ## / ###), unordered + ordered lists,
// blockquotes, fenced code blocks (```), inline code (`x`), bold (**x**),
// italic (*x* or _x_), links ([text](url)), horizontal rules (---).
//
// Does NOT support: tables, nested lists, footnotes, images, html
// passthrough. For Molly's info.md format (key/value lists + a few
// `## H2` sections) the supported subset is plenty.
//
// Output is a list of JSX-friendly Block descriptors so the caller can
// render with React (avoids dangerouslySetInnerHTML).

export interface MdInlineText { kind: 'text'; text: string }
export interface MdInlineCode { kind: 'code'; text: string }
export interface MdInlineBold { kind: 'bold'; text: string }
export interface MdInlineItalic { kind: 'italic'; text: string }
export interface MdInlineLink { kind: 'link'; text: string; url: string }
export type MdInline = MdInlineText | MdInlineCode | MdInlineBold | MdInlineItalic | MdInlineLink;

export interface MdHeading  { kind: 'heading';  level: 1 | 2 | 3; inline: MdInline[] }
export interface MdParagraph { kind: 'paragraph'; inline: MdInline[] }
export interface MdList     { kind: 'list'; ordered: boolean; items: MdInline[][] }
export interface MdQuote    { kind: 'quote'; inline: MdInline[] }
export interface MdCode     { kind: 'codeblock'; text: string }
export interface MdRule     { kind: 'rule' }
export type MdBlock = MdHeading | MdParagraph | MdList | MdQuote | MdCode | MdRule;

export function parseMarkdownLite(src: string): MdBlock[] {
  const lines = src.replace(/\r\n/g, '\n').split('\n');
  const out: MdBlock[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) { i++; continue; }

    // Fenced code blocks
    if (line.startsWith('```')) {
      const body: string[] = [];
      i++;
      while (i < lines.length && !lines[i].startsWith('```')) {
        body.push(lines[i]);
        i++;
      }
      i++; // skip closing fence (or EOF)
      out.push({ kind: 'codeblock', text: body.join('\n') });
      continue;
    }

    // Headings
    const h = /^(#{1,3})\s+(.*)$/.exec(line);
    if (h) {
      out.push({
        kind: 'heading',
        level: h[1].length as 1 | 2 | 3,
        inline: parseInline(h[2]),
      });
      i++;
      continue;
    }

    // Horizontal rule
    if (/^-{3,}\s*$/.test(line)) {
      out.push({ kind: 'rule' });
      i++;
      continue;
    }

    // Blockquote
    if (line.startsWith('> ')) {
      out.push({ kind: 'quote', inline: parseInline(line.slice(2)) });
      i++;
      continue;
    }

    // Lists (unordered + ordered)
    if (/^(?:[-*]|\d+\.)\s+/.test(line)) {
      const ordered = /^\d+\.\s/.test(line);
      const items: MdInline[][] = [];
      while (i < lines.length && /^(?:[-*]|\d+\.)\s+/.test(lines[i])) {
        const itemBody = lines[i].replace(/^(?:[-*]|\d+\.)\s+/, '');
        items.push(parseInline(itemBody));
        i++;
      }
      out.push({ kind: 'list', ordered, items });
      continue;
    }

    // Paragraph: consume consecutive non-blank non-special lines.
    const body: string[] = [line];
    i++;
    while (i < lines.length && lines[i].trim() && !isBlockStart(lines[i])) {
      body.push(lines[i]);
      i++;
    }
    out.push({ kind: 'paragraph', inline: parseInline(body.join(' ')) });
  }
  return out;
}

function isBlockStart(line: string): boolean {
  return /^(#{1,3}\s|>\s|[-*]\s|\d+\.\s|```|-{3,}\s*$)/.test(line);
}

// Inline parser — left-to-right pass, no nesting. Supports `code`,
// **bold**, *italic*, _italic_, [text](url).
function parseInline(src: string): MdInline[] {
  const out: MdInline[] = [];
  let i = 0;
  let buf = '';
  const flush = () => { if (buf) { out.push({ kind: 'text', text: buf }); buf = ''; } };

  while (i < src.length) {
    // Backtick code
    if (src[i] === '`') {
      const end = src.indexOf('`', i + 1);
      if (end > i) {
        flush();
        out.push({ kind: 'code', text: src.slice(i + 1, end) });
        i = end + 1;
        continue;
      }
    }
    // Bold **
    if (src.startsWith('**', i)) {
      const end = src.indexOf('**', i + 2);
      if (end > i + 2) {
        flush();
        out.push({ kind: 'bold', text: src.slice(i + 2, end) });
        i = end + 2;
        continue;
      }
    }
    // Italic * or _ (but not the next char of bold or underscore-in-word)
    if ((src[i] === '*' || src[i] === '_')
        && i + 1 < src.length && src[i + 1] !== ' ' && src[i + 1] !== src[i]) {
      const marker = src[i];
      const end = src.indexOf(marker, i + 1);
      if (end > i + 1) {
        flush();
        out.push({ kind: 'italic', text: src.slice(i + 1, end) });
        i = end + 1;
        continue;
      }
    }
    // [text](url)
    if (src[i] === '[') {
      const close = src.indexOf(']', i + 1);
      if (close > i && src[close + 1] === '(') {
        const urlEnd = src.indexOf(')', close + 2);
        if (urlEnd > close) {
          flush();
          out.push({
            kind: 'link',
            text: src.slice(i + 1, close),
            url: src.slice(close + 2, urlEnd),
          });
          i = urlEnd + 1;
          continue;
        }
      }
    }
    buf += src[i];
    i++;
  }
  flush();
  return out;
}
