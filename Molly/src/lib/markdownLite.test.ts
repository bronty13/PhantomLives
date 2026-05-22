import { describe, it, expect } from 'vitest';
import { parseMarkdown, renderInline } from './markdownLite';

describe('parseMarkdown', () => {
  it('parses h1/h2/h3/h4', () => {
    const b = parseMarkdown('# A\n## B\n### C\n#### D\n');
    expect(b).toEqual([
      { kind: 'h1', text: 'A' },
      { kind: 'h2', text: 'B' },
      { kind: 'h3', text: 'C' },
      { kind: 'h4', text: 'D' },
    ]);
  });

  it('joins consecutive non-blank lines into one paragraph', () => {
    const b = parseMarkdown('line one\nline two\n\nseparate\n');
    expect(b).toEqual([
      { kind: 'p', text: 'line one line two' },
      { kind: 'p', text: 'separate' },
    ]);
  });

  it('groups consecutive `- ` items into a single ul', () => {
    const b = parseMarkdown('- one\n- two\n- three\n');
    expect(b).toEqual([{ kind: 'ul', items: ['one', 'two', 'three'] }]);
  });

  it('groups consecutive `N. ` items into a single ol', () => {
    const b = parseMarkdown('1. foo\n2. bar\n');
    expect(b).toEqual([{ kind: 'ol', items: ['foo', 'bar'] }]);
  });

  it('recognizes blockquotes and horizontal rules', () => {
    const b = parseMarkdown('> hello\n\n---\n\n> world\n');
    expect(b).toEqual([
      { kind: 'blockquote', text: 'hello' },
      { kind: 'hr' },
      { kind: 'blockquote', text: 'world' },
    ]);
  });

  it('captures fenced code blocks verbatim with language hint', () => {
    const b = parseMarkdown('```sql\nSELECT * FROM clips;\n```\n');
    expect(b).toEqual([{ kind: 'code', text: 'SELECT * FROM clips;', lang: 'sql' }]);
  });

  it('flushes open lists when a heading appears', () => {
    const b = parseMarkdown('- one\n- two\n## heading\n');
    expect(b).toEqual([
      { kind: 'ul', items: ['one', 'two'] },
      { kind: 'h2', text: 'heading' },
    ]);
  });
});

describe('renderInline', () => {
  it('extracts code spans first', () => {
    const t = renderInline('hit `the` button');
    expect(t).toEqual([
      { kind: 'text', text: 'hit ' },
      { kind: 'code', text: 'the' },
      { kind: 'text', text: ' button' },
    ]);
  });

  it('recognises **bold** and *italic*', () => {
    const t = renderInline('**big** and *small*');
    expect(t).toEqual([
      { kind: 'bold', text: 'big' },
      { kind: 'text', text: ' and ' },
      { kind: 'italic', text: 'small' },
    ]);
  });

  it('handles links', () => {
    const t = renderInline('go to [the docs](https://example.com)');
    expect(t).toEqual([
      { kind: 'text', text: 'go to ' },
      { kind: 'link', text: 'the docs', href: 'https://example.com' },
    ]);
  });

  it('preserves plain text without any markup', () => {
    const t = renderInline('just text here');
    expect(t).toEqual([{ kind: 'text', text: 'just text here' }]);
  });

  it('does not interpret markdown inside code spans', () => {
    const t = renderInline('`**not bold**`');
    expect(t).toEqual([{ kind: 'code', text: '**not bold**' }]);
  });
});
