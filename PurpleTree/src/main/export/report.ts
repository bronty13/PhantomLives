/**
 * @file report.ts — pure CSV / HTML / JSON serializers for scan results.
 *
 * No fs, no electron — given rows + metadata, returns a string. The main
 * process writes the returned string to a user-chosen path.
 */
import type { NodeRow, ExportFormat } from '../../shared/types';

export interface ReportMeta {
  rootPath: string;
  generatedMs: number;
  totalBytes: number;
  totalFiles: number;
}

function csvField(s: string): string {
  if (/[",\n\r]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
  return s;
}

function htmlEscape(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function isoOrEmpty(ms: number): string {
  return ms > 0 ? new Date(ms).toISOString() : '';
}

export function toCsv(rows: NodeRow[]): string {
  const header = ['Path', 'Type', 'Size (bytes)', 'Files', 'Modified'];
  const lines = [header.join(',')];
  for (const r of rows) {
    lines.push(
      [
        csvField(r.path),
        r.isDir ? 'folder' : 'file',
        String(r.aggSize),
        String(r.fileCount),
        csvField(isoOrEmpty(r.mtimeMs))
      ].join(',')
    );
  }
  return lines.join('\n') + '\n';
}

export function toJson(rows: NodeRow[], meta: ReportMeta): string {
  return (
    JSON.stringify(
      {
        tool: 'Purple Tree',
        rootPath: meta.rootPath,
        generated: isoOrEmpty(meta.generatedMs),
        totalBytes: meta.totalBytes,
        totalFiles: meta.totalFiles,
        rows: rows.map((r) => ({
          path: r.path,
          type: r.isDir ? 'folder' : 'file',
          bytes: r.aggSize,
          files: r.fileCount,
          modified: isoOrEmpty(r.mtimeMs)
        }))
      },
      null,
      2
    ) + '\n'
  );
}

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  let v = n / 1024;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return `${v.toFixed(1)} ${units[i]}`;
}

export function toHtml(rows: NodeRow[], meta: ReportMeta): string {
  const body = rows
    .map(
      (r) =>
        `    <tr><td>${htmlEscape(r.path)}</td><td>${r.isDir ? 'folder' : 'file'}</td>` +
        `<td class="num">${formatBytes(r.aggSize)}</td><td class="num">${r.fileCount}</td>` +
        `<td>${htmlEscape(isoOrEmpty(r.mtimeMs))}</td></tr>`
    )
    .join('\n');
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8" />
<title>Purple Tree report — ${htmlEscape(meta.rootPath)}</title>
<style>
  body { font: 14px -apple-system, system-ui, sans-serif; margin: 2rem; color: #1a0b2e; }
  h1 { color: #4c1d95; } .meta { color: #6b21a8; margin-bottom: 1rem; }
  table { border-collapse: collapse; width: 100%; }
  th, td { text-align: left; padding: 4px 10px; border-bottom: 1px solid #e9d5ff; }
  th { background: #4c1d95; color: #fff; } .num { text-align: right; font-variant-numeric: tabular-nums; }
</style></head><body>
<h1>Purple Tree report</h1>
<div class="meta">Root: ${htmlEscape(meta.rootPath)} &middot; ${formatBytes(meta.totalBytes)} in ${meta.totalFiles.toLocaleString()} files &middot; generated ${htmlEscape(isoOrEmpty(meta.generatedMs))}</div>
<table><thead><tr><th>Path</th><th>Type</th><th>Size</th><th>Files</th><th>Modified</th></tr></thead>
<tbody>
${body}
</tbody></table>
</body></html>
`;
}

export function serializeReport(rows: NodeRow[], meta: ReportMeta, format: ExportFormat): string {
  switch (format) {
    case 'csv':
      return toCsv(rows);
    case 'html':
      return toHtml(rows, meta);
    case 'json':
      return toJson(rows, meta);
  }
}
