import { describe, it, expect } from 'vitest';
import { toCsv, toJson, toHtml, type ReportMeta } from '../../src/main/export/report';
import type { NodeRow } from '../../src/shared/types';

function row(p: Partial<NodeRow>): NodeRow {
  return {
    id: 1,
    name: 'x',
    aggSize: 0,
    fileCount: 0,
    isDir: false,
    isSymlink: false,
    permDenied: false,
    mtimeMs: 0,
    atimeMs: 0,
    childCount: 0,
    path: '/x',
    ...p
  };
}

const meta: ReportMeta = {
  rootPath: '/root',
  generatedMs: Date.UTC(2026, 5, 3),
  totalBytes: 1024,
  totalFiles: 2
};

describe('toCsv', () => {
  it('quotes fields containing commas and quotes', () => {
    const csv = toCsv([row({ path: '/a,b/"c".txt', aggSize: 10 })]);
    const lines = csv.trim().split('\n');
    expect(lines[0]).toBe('Path,Type,Size (bytes),Files,Modified');
    expect(lines[1]).toContain('"/a,b/""c"".txt"');
  });
  it('emits folder/file type', () => {
    const csv = toCsv([row({ isDir: true, path: '/d' })]);
    expect(csv).toContain('/d,folder,');
  });
});

describe('toHtml', () => {
  it('escapes HTML in paths', () => {
    const html = toHtml([row({ path: '/x/<script>&"' })], meta);
    expect(html).toContain('/x/&lt;script&gt;&amp;&quot;');
    expect(html).not.toContain('<script>');
  });
});

describe('toJson', () => {
  it('produces valid JSON with rows + meta', () => {
    const parsed = JSON.parse(toJson([row({ path: '/a', aggSize: 5, fileCount: 1 })], meta));
    expect(parsed.tool).toBe('Purple Tree');
    expect(parsed.rootPath).toBe('/root');
    expect(parsed.rows[0]).toMatchObject({ path: '/a', bytes: 5, files: 1, type: 'file' });
  });
});
