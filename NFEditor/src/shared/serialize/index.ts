// The serializer: ProseMirror doc JSON -> NiteFlirt HTML, in one of two modes.
//
// This walks the doc JSON DIRECTLY (it does NOT wrap editor.getHTML()), because
// getHTML() won't reliably emit legacy <font>/<table> and normalizes against us.
// The same global OutputMode drives BOTH font flavor (handled in inline.ts) and
// container flavor (<div> vs <table>, handled here). Payment-button nodes emit the
// exact <a href><img></a> shape NiteFlirt generated, byte-for-byte, in both modes.

import type { DocNode, OutputMode } from '../model';
import { serializeInline } from './inline';
import { escapeAttr } from './escape';

/** ` name="value"`, or `''` when the value is empty/undefined. */
function attr(name: string, value: unknown): string {
  if (value == null || value === '') return '';
  return ` ${name}="${escapeAttr(String(value))}"`;
}

/** A bare boolean attribute (` controls`) when truthy. */
function boolAttr(name: string, value: unknown): string {
  return value ? ` ${name}` : '';
}

function children(node: DocNode, mode: OutputMode): string {
  return (node.content ?? []).map((c) => serializeNode(c, mode)).join('');
}

/** Serialize a single image element (no align wrapper, no link). */
function imgTag(a: Record<string, unknown>): string {
  return (
    `<img${attr('src', a.src)}${attr('alt', a.alt)}${attr('width', a.width)}` +
    `${attr('height', a.height)}${attr('title', a.title)}>`
  );
}

/** Wrap `inner` for block alignment, mode-aware. */
function alignWrap(inner: string, align: unknown, mode: OutputMode): string {
  if (!align || align === 'left') return inner;
  return mode === 'legacy'
    ? `<div align="${escapeAttr(String(align))}">${inner}</div>`
    : `<div style="text-align:${escapeAttr(String(align))}">${inner}</div>`;
}

/** A payment button / image link: <a href="url"><img ...></a>. Identical in both
 *  modes — this is the load-bearing round-trip property for NiteFlirt embeds. */
function paymentButton(a: Record<string, unknown>): string {
  const img = `<img${attr('src', a.imageUrl)}${attr('alt', a.label)}${attr('width', a.width)}${attr(
    'height',
    a.height,
  )}>`;
  return `<a href="${escapeAttr(String(a.url ?? ''))}">${img}</a>`;
}

export function serializeNode(node: DocNode, mode: OutputMode): string {
  const a = node.attrs ?? {};
  switch (node.type) {
    case 'doc':
      return children(node, mode);

    case 'paragraph': {
      const inner = serializeInline(node.content, mode);
      if (mode === 'legacy') {
        return `<p${attr('align', a.align && a.align !== 'left' ? a.align : '')}>${inner}</p>`;
      }
      const style = a.align && a.align !== 'left' ? ` style="text-align:${escapeAttr(String(a.align))}"` : '';
      return `<p${style}>${inner}</p>`;
    }

    case 'heading': {
      const level = Math.min(6, Math.max(1, Number(a.level) || 1));
      const inner = serializeInline(node.content, mode);
      if (mode === 'legacy') {
        const aln = a.align && a.align !== 'left' ? attr('align', a.align) : '';
        const body = a.color ? `<font${attr('color', a.color)}>${inner}</font>` : inner;
        return `<h${level}${aln}>${body}</h${level}>`;
      }
      const styles: string[] = [];
      if (a.color) styles.push(`color:${a.color}`);
      if (a.align && a.align !== 'left') styles.push(`text-align:${a.align}`);
      const style = styles.length ? ` style="${escapeAttr(styles.join(';'))}"` : '';
      return `<h${level}${style}>${inner}</h${level}>`;
    }

    case 'image': {
      let html = imgTag(a);
      if (a.href) html = `<a href="${escapeAttr(String(a.href))}">${html}</a>`;
      return alignWrap(html, a.align, mode);
    }

    case 'goodyButton':
    case 'tributeButton':
    case 'flirtButton':
      return paymentButton(a);

    case 'wishlistLink': {
      if (a.imageUrl) return paymentButton(a);
      return `<a href="${escapeAttr(String(a.url ?? ''))}">${escapeAttr(String(a.label ?? 'Wishlist'))}</a>`;
    }

    case 'section': {
      const inner = children(node, mode);
      if (mode === 'legacy') {
        const w = a.width ? attr('width', a.width) : '';
        const bg = a.bgColor ? attr('bgcolor', a.bgColor) : '';
        const aln = a.align ? attr('align', a.align) : '';
        const pad = a.padding != null ? attr('cellpadding', a.padding) : '';
        return `<table${w}${bg}${aln}${pad} cellspacing="0"><tbody><tr><td>${inner}</td></tr></tbody></table>`;
      }
      const styles: string[] = [];
      if (a.width) styles.push(`width:${typeof a.width === 'number' ? `${a.width}px` : a.width}`);
      if (a.bgColor) styles.push(`background-color:${a.bgColor}`);
      if (a.align) styles.push(`text-align:${a.align}`);
      if (a.padding != null) styles.push(`padding:${typeof a.padding === 'number' ? `${a.padding}px` : a.padding}`);
      const style = styles.length ? ` style="${escapeAttr(styles.join(';'))}"` : '';
      return `<div${style}>${inner}</div>`;
    }

    case 'video': {
      const inner = a.src
        ? attr('src', a.src)
        : (node.content ?? []).map((s) => `<source${attr('src', s.attrs?.src)}${attr('type', s.attrs?.type)}>`).join('');
      const tagAttrs =
        attr('src', a.src) +
        attr('poster', a.poster) +
        attr('width', a.width) +
        attr('height', a.height) +
        boolAttr('controls', a.controls) +
        boolAttr('autoplay', a.autoplay) +
        boolAttr('loop', a.loop) +
        boolAttr('muted', a.muted);
      const sources = a.src ? '' : inner;
      return `<video${tagAttrs}>${sources}</video>`;
    }

    case 'imageMap': {
      const name = String(a.mapName ?? 'nfmap');
      const img = `<img${attr('src', a.src)}${attr('width', a.width)}${attr('height', a.height)} usemap="#${escapeAttr(name)}">`;
      const areas = (Array.isArray(a.areas) ? a.areas : [])
        .map((ar: Record<string, unknown>) => `<area${attr('shape', ar.shape)}${attr('coords', ar.coords)}${attr('href', ar.href)}${attr('alt', ar.alt)}>`)
        .join('');
      return `${img}<map name="${escapeAttr(name)}">${areas}</map>`;
    }

    case 'marquee': {
      const inner = serializeInline(node.content, mode);
      return `<marquee${attr('direction', a.direction)}${attr('behavior', a.behavior)}${attr('scrollamount', a.scrollamount)}>${inner}</marquee>`;
    }

    case 'details': {
      const kids = node.content ?? [];
      const summaryNode = kids.find((k) => k.type === 'summary');
      const rest = kids.filter((k) => k.type !== 'summary');
      const summary = `<summary>${serializeInline(summaryNode?.content, mode)}</summary>`;
      const body = rest.map((c) => serializeNode(c, mode)).join('');
      return `<details${boolAttr('open', a.open)}>${summary}${body}</details>`;
    }

    case 'summary':
      return `<summary>${serializeInline(node.content, mode)}</summary>`;

    case 'bulletList':
      return `<ul>${children(node, mode)}</ul>`;
    case 'orderedList':
      return `<ol>${children(node, mode)}</ol>`;
    case 'listItem': {
      // Unwrap a single paragraph so we emit <li>text</li>, not <li><p>text</p></li>.
      const kids = node.content ?? [];
      if (kids.length === 1 && kids[0].type === 'paragraph') {
        return `<li>${serializeInline(kids[0].content, mode)}</li>`;
      }
      return `<li>${children(node, mode)}</li>`;
    }

    case 'horizontalRule':
      return '<hr>';

    case 'hardBreak':
      return '<br>';

    case 'text':
      // A stray top-level text node — wrap via the inline serializer.
      return serializeInline([node], mode);

    default:
      // Unknown node types are dropped (schema should prevent them existing).
      return children(node, mode);
  }
}

/** Serialize a whole document for the given output mode. */
export function serialize(doc: DocNode, mode: OutputMode): string {
  return serializeNode(doc, mode);
}
