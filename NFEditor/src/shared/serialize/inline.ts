// Inline serialization with mark coalescing.
//
// ProseMirror stores marks per text node, so naive output would wrap every single
// character in its own <font>/<b>, exploding the 7K/14K character budget and not
// matching how NiteFlirt's own examples look. Instead we group consecutive text
// nodes that share an IDENTICAL mark set into one run and wrap that run once.

import type { DocNode, DocMark, OutputMode, NFSize } from '../model';
import { ptString } from '../model';
import { escapeText, escapeAttr } from './escape';

// Format marks render as nested inline tags (outer → inner in this order).
const FORMAT_TAGS: Array<{ mark: string; tag: string }> = [
  { mark: 'bold', tag: 'b' },
  { mark: 'italic', tag: 'i' },
  { mark: 'underline', tag: 'u' },
  { mark: 'strike', tag: 's' },
  { mark: 'superscript', tag: 'sup' },
  { mark: 'subscript', tag: 'sub' },
  { mark: 'small', tag: 'small' },
  { mark: 'big', tag: 'big' },
  { mark: 'highlight', tag: 'mark' },
];

interface FontSig {
  face?: string;
  size?: NFSize;
  color?: string;
}

function findMark(marks: DocMark[] | undefined, type: string): DocMark | undefined {
  return marks?.find((m) => m.type === type);
}

function fontSig(marks: DocMark[] | undefined): FontSig {
  const sig: FontSig = {};
  const font = findMark(marks, 'font')?.attrs;
  if (font) {
    if (typeof font.face === 'string' && font.face) sig.face = font.face;
    if (typeof font.size === 'number') sig.size = font.size as NFSize;
    if (typeof font.color === 'string' && font.color) sig.color = font.color;
  }
  return sig;
}

/** Stable signature string so adjacent text nodes with equal marks coalesce. */
function markSignature(marks: DocMark[] | undefined): string {
  if (!marks || marks.length === 0) return '';
  const parts = marks
    .map((m) => `${m.type}:${m.attrs ? JSON.stringify(m.attrs) : ''}`)
    .sort();
  return parts.join('|');
}

function openFont(sig: FontSig, mode: OutputMode): string {
  if (sig.face == null && sig.size == null && sig.color == null) return '';
  if (mode === 'legacy') {
    const attrs: string[] = [];
    if (sig.face) attrs.push(`face="${escapeAttr(sig.face)}"`);
    if (sig.size != null) attrs.push(`size="${sig.size}"`);
    if (sig.color) attrs.push(`color="${escapeAttr(sig.color)}"`);
    return `<font ${attrs.join(' ')}>`;
  }
  const styles: string[] = [];
  if (sig.face) styles.push(`font-family:${sig.face}`);
  if (sig.size != null) styles.push(`font-size:${ptString(sig.size)}`);
  if (sig.color) styles.push(`color:${sig.color}`);
  return `<span style="${escapeAttr(styles.join(';'))}">`;
}

function closeFont(sig: FontSig, mode: OutputMode): string {
  if (sig.face == null && sig.size == null && sig.color == null) return '';
  return mode === 'legacy' ? '</font>' : '</span>';
}

/** Wrap `inner` (already-escaped HTML) in this run's link + font + format tags. */
function wrapRun(inner: string, marks: DocMark[] | undefined, mode: OutputMode): string {
  let html = inner;

  // Innermost: format tags (in fixed order so output is deterministic).
  for (let i = FORMAT_TAGS.length - 1; i >= 0; i--) {
    if (findMark(marks, FORMAT_TAGS[i].mark)) {
      const t = FORMAT_TAGS[i].tag;
      html = `<${t}>${html}</${t}>`;
    }
  }

  // Font wrapper.
  const sig = fontSig(marks);
  html = `${openFont(sig, mode)}${html}${closeFont(sig, mode)}`;

  // Outermost: link.
  const link = findMark(marks, 'link');
  if (link?.attrs?.href) {
    const href = escapeAttr(String(link.attrs.href));
    const target = link.attrs.target ? ` target="${escapeAttr(String(link.attrs.target))}"` : '';
    const title = link.attrs.title ? ` title="${escapeAttr(String(link.attrs.title))}"` : '';
    html = `<a href="${href}"${target}${title}>${html}</a>`;
  }

  return html;
}

/** Serialize an array of inline nodes (text + hardBreak) for the given mode. */
export function serializeInline(nodes: DocNode[] | undefined, mode: OutputMode): string {
  if (!nodes || nodes.length === 0) return '';
  let out = '';
  let runText = '';
  let runSig: string | null = null;
  let runMarks: DocMark[] | undefined;

  const flush = () => {
    if (runText !== '') {
      out += wrapRun(runText, runMarks, mode);
    }
    runText = '';
    runSig = null;
    runMarks = undefined;
  };

  for (const node of nodes) {
    if (node.type === 'hardBreak') {
      flush();
      out += '<br>';
      continue;
    }
    if (node.type === 'text') {
      const sig = markSignature(node.marks);
      if (runSig === null || sig === runSig) {
        runSig = sig;
        runMarks = node.marks;
        runText += escapeText(node.text ?? '');
      } else {
        flush();
        runSig = sig;
        runMarks = node.marks;
        runText = escapeText(node.text ?? '');
      }
    }
  }
  flush();
  return out;
}
