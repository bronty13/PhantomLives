// Round-trip: parse real-shaped NiteFlirt HTML through the actual Tiptap schema,
// then serialize it back. This is the correctness gate the build plan calls out —
// especially the payment-button vs plain-linked-image disambiguation.

import { describe, it, expect } from 'vitest';
import { Editor } from '@tiptap/core';
import { buildExtensions } from '../src/shared/schema';
import { serialize } from '../src/shared/serialize';
import type { DocNode } from '../src/shared/model';

function parse(html: string): DocNode {
  const editor = new Editor({ extensions: buildExtensions(), content: html });
  const json = editor.getJSON() as DocNode;
  editor.destroy();
  return json;
}

function typesIn(doc: DocNode): string[] {
  const out: string[] = [];
  const walk = (n: DocNode) => {
    out.push(n.type);
    (n.content ?? []).forEach(walk);
  };
  walk(doc);
  return out;
}

describe('round-trip import', () => {
  it('imports a NiteFlirt Goody button as a structured button node', () => {
    const html = '<a href="https://www.niteflirt.com/goodies/123"><img src="https://h/buy.png" alt="Buy"></a>';
    const doc = parse(html);
    expect(typesIn(doc)).toContain('goodyButton');
    expect(serialize(doc, 'legacy')).toBe(html);
    expect(serialize(doc, 'compact')).toBe(html);
  });

  it('imports an EXTERNAL linked image as a plain image (not a button)', () => {
    const html = '<a href="https://example.com/page"><img src="https://h/pic.jpg" alt="pic"></a>';
    const doc = parse(html);
    expect(typesIn(doc)).toContain('image');
    expect(typesIn(doc)).not.toContain('goodyButton');
    expect(serialize(doc, 'compact')).toContain('<a href="https://example.com/page">');
    expect(serialize(doc, 'compact')).toContain('<img src="https://h/pic.jpg"');
  });

  it('round-trips <font> face/size/color into marks and back', () => {
    const doc = parse('<p><font size="5" color="#ff0000">Hi</font></p>');
    const legacy = serialize(doc, 'legacy');
    expect(legacy).toContain('size="5"');
    expect(legacy).toContain('color="#ff0000"');
    expect(legacy).toContain('Hi');
  });

  it('snaps a CSS pt font-size to the nearest NiteFlirt size on import', () => {
    const doc = parse('<p><span style="font-size:24pt">Big</span></p>');
    expect(serialize(doc, 'legacy')).toContain('size="6"'); // 24pt = size 6
  });
});
