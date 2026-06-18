import { describe, it, expect } from 'vitest';
import { serialize } from '../src/shared/serialize';
import type { DocNode } from '../src/shared/model';

const doc = (...content: DocNode[]): DocNode => ({ type: 'doc', content });
const text = (t: string, marks?: DocNode['marks']): DocNode => ({ type: 'text', text: t, marks });

describe('serializer — font mark coalescing', () => {
  it('coalesces adjacent text nodes with identical font marks into ONE wrapper', () => {
    const d = doc({
      type: 'paragraph',
      content: [
        text('A', [{ type: 'font', attrs: { size: 5 } }, { type: 'bold' }]),
        text('B', [{ type: 'font', attrs: { size: 5 } }, { type: 'bold' }]),
      ],
    });
    expect(serialize(d, 'legacy')).toBe('<p><font size="5"><b>AB</b></font></p>');
    expect(serialize(d, 'compact')).toBe('<p><span style="font-size:18pt"><b>AB</b></span></p>');
  });

  it('does NOT merge runs with different marks', () => {
    const d = doc({
      type: 'paragraph',
      content: [
        text('A', [{ type: 'font', attrs: { size: 5 } }]),
        text('B', [{ type: 'font', attrs: { size: 6 } }]),
      ],
    });
    expect(serialize(d, 'legacy')).toBe('<p><font size="5">A</font><font size="6">B</font></p>');
  });
});

describe('serializer — modes diverge', () => {
  const section = doc({
    type: 'section',
    attrs: { width: 800, bgColor: '#fff0f5', align: 'center', padding: 16 },
    content: [{ type: 'paragraph', content: [text('hi')] }],
  });

  it('compact uses <div style>', () => {
    expect(serialize(section, 'compact')).toContain('<div style="width:800px;background-color:#fff0f5;text-align:center;padding:16px">');
  });

  it('legacy uses <table cellpadding bgcolor>', () => {
    const out = serialize(section, 'legacy');
    expect(out).toContain('<table width="800" bgcolor="#fff0f5" align="center" cellpadding="16" cellspacing="0">');
    expect(out).toContain('<td><p>hi</p></td>');
  });

  it('legacy output is longer than compact (char budget matters)', () => {
    expect(serialize(section, 'legacy').length).toBeGreaterThan(serialize(section, 'compact').length);
  });
});

describe('serializer — payment buttons are byte-identical in both modes', () => {
  const d = doc({
    type: 'goodyButton',
    attrs: { url: 'https://www.niteflirt.com/goodies/x', imageUrl: 'https://h/b.png', label: 'Buy', width: 200 },
  });
  const expected = '<a href="https://www.niteflirt.com/goodies/x"><img src="https://h/b.png" alt="Buy" width="200"></a>';
  it('compact', () => expect(serialize(d, 'compact')).toBe(expected));
  it('legacy', () => expect(serialize(d, 'legacy')).toBe(expected));
});

describe('serializer — escaping + structure', () => {
  it('escapes text and attributes', () => {
    const d = doc({ type: 'paragraph', content: [text('a < b & "c"')] });
    expect(serialize(d, 'compact')).toBe('<p>a &lt; b &amp; "c"</p>');
  });

  it('image with href wraps in an anchor; align wraps in a div', () => {
    const d = doc({ type: 'image', attrs: { src: 's.jpg', alt: 'x', href: 'https://e.com', align: 'center' } });
    expect(serialize(d, 'compact')).toBe(
      '<div style="text-align:center"><a href="https://e.com"><img src="s.jpg" alt="x"></a></div>',
    );
  });

  it('heading carries color (font in legacy, style in compact)', () => {
    const d = doc({ type: 'heading', attrs: { level: 2, color: '#c2185b' }, content: [text('Hi')] });
    expect(serialize(d, 'legacy')).toBe('<h2><font color="#c2185b">Hi</font></h2>');
    expect(serialize(d, 'compact')).toBe('<h2 style="color:#c2185b">Hi</h2>');
  });

  it('lists unwrap a single paragraph in <li>', () => {
    const d = doc({
      type: 'bulletList',
      content: [{ type: 'listItem', content: [{ type: 'paragraph', content: [text('one')] }] }],
    });
    expect(serialize(d, 'compact')).toBe('<ul><li>one</li></ul>');
  });
});
