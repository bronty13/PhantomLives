import { describe, it, expect } from 'vitest';
import { parsePipeCsv, parsePipeCsvToObjects } from './csvPipe';

describe('parsePipeCsv', () => {
  it('parses a simple two-row table', () => {
    const m = parsePipeCsv('a|b|c\n1|2|3\n');
    expect(m).toEqual([['a', 'b', 'c'], ['1', '2', '3']]);
  });

  it('handles quoted fields with embedded pipes', () => {
    const m = parsePipeCsv('a|b\n"hello|world"|x\n');
    expect(m).toEqual([['a', 'b'], ['hello|world', 'x']]);
  });

  it('handles quoted fields with embedded newlines (the C4S Description case)', () => {
    const m = parsePipeCsv('a|b\n"line one\nline two\n\nline four"|done\n');
    expect(m).toEqual([['a', 'b'], ['line one\nline two\n\nline four', 'done']]);
  });

  it('handles CRLF line endings', () => {
    const m = parsePipeCsv('a|b\r\n1|2\r\n');
    expect(m).toEqual([['a', 'b'], ['1', '2']]);
  });

  it('handles escaped double-quotes inside a quoted field', () => {
    const m = parsePipeCsv('"she said ""hi"""|x\n');
    expect(m).toEqual([['she said "hi"', 'x']]);
  });

  it('strips a leading UTF-8 BOM', () => {
    const m = parsePipeCsv('﻿a|b\n1|2\n');
    expect(m).toEqual([['a', 'b'], ['1', '2']]);
  });

  it('preserves empty cells', () => {
    const m = parsePipeCsv('a|b|c\n1||3\n');
    expect(m).toEqual([['a', 'b', 'c'], ['1', '', '3']]);
  });

  it('handles a trailing record without a final newline', () => {
    const m = parsePipeCsv('a|b\n1|2');
    expect(m).toEqual([['a', 'b'], ['1', '2']]);
  });

  it('returns an empty array for empty input', () => {
    expect(parsePipeCsv('')).toEqual([]);
  });

  it('drops a single trailing empty row from a stray final newline', () => {
    // The parser's "drop single-cell empty row at end" rule matches the
    // standard CSV/MasterClipperImport behavior — a file that ends with
    // an extra blank line should not produce a spurious empty record.
    expect(parsePipeCsv('a|b\n1|2\n\n')).toEqual([['a', 'b'], ['1', '2']]);
  });
});

describe('parsePipeCsvToObjects', () => {
  it('keys rows by header', () => {
    const r = parsePipeCsvToObjects('"Clip Status"|"Clip ID"|"Clip Title"\n"active"|"123"|"hello"\n');
    expect(r.header).toEqual(['Clip Status', 'Clip ID', 'Clip Title']);
    expect(r.rows).toEqual([
      { 'Clip Status': 'active', 'Clip ID': '123', 'Clip Title': 'hello' },
    ]);
  });

  it('fills missing trailing cells with empty strings', () => {
    const r = parsePipeCsvToObjects('a|b|c\n1|2\n');
    expect(r.rows).toEqual([{ a: '1', b: '2', c: '' }]);
  });

  it('parses a realistic C4S-shaped row with multi-line description', () => {
    const text = [
      '"Clip Status"|"Clip ID"|"Clip Title"|"Clip Description"|"Performers"|"Price"',
      '"active"|"21775109"|"Test"|"line A\nline B\n\nline C"|"CoC"|"15.99"',
      '',
    ].join('\n');
    const r = parsePipeCsvToObjects(text);
    expect(r.rows).toHaveLength(1);
    expect(r.rows[0]['Clip Description']).toBe('line A\nline B\n\nline C');
    expect(r.rows[0]['Performers']).toBe('CoC');
    expect(r.rows[0]['Price']).toBe('15.99');
  });
});
