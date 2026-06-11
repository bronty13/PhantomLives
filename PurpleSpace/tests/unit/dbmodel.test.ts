import { describe, it, expect } from 'vitest';
import {
  parseDbConfig,
  parseRowValues,
  viewRows,
  matchesFilter,
  cellToText,
  databaseToMarkdown,
  DEFAULT_DB_CONFIG,
  type DbConfig,
  type RowData
} from '../../src/shared/dbmodel';

const cfg: DbConfig = {
  properties: [
    { id: 'title', name: 'Name', type: 'title' },
    { id: 'p_num', name: 'Score', type: 'number' },
    { id: 'p_tag', name: 'Status', type: 'select', options: [
      { id: 'o1', name: 'Open', color: 0 },
      { id: 'o2', name: 'Done', color: 1 }
    ] },
    { id: 'p_multi', name: 'Tags', type: 'multiSelect', options: [
      { id: 'm1', name: 'home', color: 0 },
      { id: 'm2', name: 'work', color: 1 }
    ] },
    { id: 'p_done', name: 'Done?', type: 'checkbox' },
    { id: 'p_date', name: 'Due', type: 'date' }
  ],
  sorts: [],
  filters: []
};

function row(id: string, title: string, values: RowData['values'], createdAt = 0): RowData {
  return { id, title, icon: null, values, createdAt };
}

const rows: RowData[] = [
  row('1', 'Beta', { p_num: 5, p_tag: 'o1', p_multi: ['m1'], p_done: false, p_date: '2026-06-01' }, 1),
  row('2', 'alpha', { p_num: 12, p_tag: 'o2', p_multi: ['m1', 'm2'], p_done: true, p_date: '2026-01-15' }, 2),
  row('3', 'Gamma', { p_num: null, p_multi: [], p_done: false }, 3)
];

describe('parseDbConfig', () => {
  it('falls back to defaults on garbage', () => {
    expect(parseDbConfig('not json').properties).toEqual(DEFAULT_DB_CONFIG.properties);
    expect(parseDbConfig(null).properties[0].type).toBe('title');
  });
  it('round-trips a real config', () => {
    expect(parseDbConfig(JSON.stringify(cfg))).toEqual(cfg);
  });
});

describe('parseRowValues', () => {
  it('returns {} on garbage or null', () => {
    expect(parseRowValues(null)).toEqual({});
    expect(parseRowValues('[]')).toEqual({});
    expect(parseRowValues('{bad')).toEqual({});
  });
});

describe('sorting', () => {
  it('sorts numbers numerically with empties first (asc)', () => {
    const sorted = viewRows(rows, { ...cfg, sorts: [{ propId: 'p_num', dir: 'asc' }] });
    expect(sorted.map((r) => r.id)).toEqual(['3', '1', '2']);
  });
  it('sorts titles case-insensitively', () => {
    const sorted = viewRows(rows, { ...cfg, sorts: [{ propId: 'title', dir: 'asc' }] });
    expect(sorted.map((r) => r.title)).toEqual(['alpha', 'Beta', 'Gamma']);
  });
  it('sorts selects by option name, descending', () => {
    const sorted = viewRows(rows, { ...cfg, sorts: [{ propId: 'p_tag', dir: 'desc' }] });
    expect(sorted[0].id).toBe('1'); // Open > Done > (empty)
  });
  it('falls back to creation order when no sorts', () => {
    expect(viewRows(rows, cfg).map((r) => r.id)).toEqual(['1', '2', '3']);
  });
});

describe('filtering', () => {
  it('contains is case-insensitive and matches titles', () => {
    const out = viewRows(rows, { ...cfg, filters: [{ propId: 'title', op: 'contains', value: 'ALPHA' }] });
    expect(out.map((r) => r.id)).toEqual(['2']);
  });
  it('select is/isNot match by option id', () => {
    expect(viewRows(rows, { ...cfg, filters: [{ propId: 'p_tag', op: 'is', value: 'o2' }] }).map((r) => r.id)).toEqual(['2']);
    expect(viewRows(rows, { ...cfg, filters: [{ propId: 'p_tag', op: 'isNot', value: 'o2' }] }).map((r) => r.id)).toEqual(['1', '3']);
  });
  it('multiSelect is matches membership', () => {
    const out = viewRows(rows, { ...cfg, filters: [{ propId: 'p_multi', op: 'is', value: 'm2' }] });
    expect(out.map((r) => r.id)).toEqual(['2']);
  });
  it('checkbox checked/unchecked', () => {
    expect(viewRows(rows, { ...cfg, filters: [{ propId: 'p_done', op: 'checked' }] }).map((r) => r.id)).toEqual(['2']);
    expect(viewRows(rows, { ...cfg, filters: [{ propId: 'p_done', op: 'unchecked' }] }).map((r) => r.id)).toEqual(['1', '3']);
  });
  it('number gt/lt coerce', () => {
    expect(viewRows(rows, { ...cfg, filters: [{ propId: 'p_num', op: 'gt', value: '6' }] }).map((r) => r.id)).toEqual(['2']);
  });
  it('isEmpty/isNotEmpty treat null, [] and false as empty', () => {
    expect(viewRows(rows, { ...cfg, filters: [{ propId: 'p_num', op: 'isEmpty' }] }).map((r) => r.id)).toEqual(['3']);
    expect(viewRows(rows, { ...cfg, filters: [{ propId: 'p_multi', op: 'isNotEmpty' }] }).map((r) => r.id)).toEqual(['1', '2']);
  });
  it('ignores rules for deleted properties', () => {
    expect(matchesFilter(rows[0], { propId: 'gone', op: 'contains', value: 'x' }, cfg.properties)).toBe(true);
  });
});

describe('cellToText', () => {
  it('renders selects/multiSelects by option name', () => {
    expect(cellToText('o1', cfg.properties[2])).toBe('Open');
    expect(cellToText(['m1', 'm2'], cfg.properties[3])).toBe('home, work');
  });
  it('renders checkboxes as ✓ / empty', () => {
    expect(cellToText(true, cfg.properties[4])).toBe('✓');
    expect(cellToText(false, cfg.properties[4])).toBe('');
  });
});

describe('databaseToMarkdown', () => {
  it('produces a well-formed table with escaped pipes', () => {
    const md = databaseToMarkdown('My DB', JSON.stringify(cfg), [
      row('1', 'A | B', { p_num: 3, p_tag: 'o1' })
    ]);
    expect(md).toContain('# My DB');
    expect(md).toContain('| Name | Score | Status | Tags | Done? | Due |');
    expect(md).toContain('| A \\| B | 3 | Open |');
  });
  it('uses Untitled for empty titles', () => {
    const md = databaseToMarkdown('X', JSON.stringify(cfg), [row('1', '', {})]);
    expect(md).toContain('| Untitled |');
  });
});
