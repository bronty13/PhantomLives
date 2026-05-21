import type { PDFDocumentProxy } from '../viewer/pdfjs';

export type CheckSeverity = 'pass' | 'warn' | 'fail' | 'info';

export interface A11yCheck {
  id: string;
  label: string;
  severity: CheckSeverity;
  detail: string;
  fixable?: boolean;
}

export interface A11yReport {
  checks: A11yCheck[];
  pass: number;
  warn: number;
  fail: number;
}

export async function runA11yChecks(doc: PDFDocumentProxy): Promise<A11yReport> {
  const checks: A11yCheck[] = [];

  let title = '';
  let lang = '';
  let isTagged = false;
  try {
    const meta = (await doc.getMetadata()) as unknown as {
      info?: Record<string, unknown>;
    };
    const info = meta.info ?? {};
    title = String(info.Title ?? '').trim();
    lang = String(info.Language ?? '').trim();
    type MarkAware = { getMarkInfo?: () => Promise<{ Marked?: boolean } | null> };
    const docX = doc as unknown as MarkAware;
    if (typeof docX.getMarkInfo === 'function') {
      const mi = await docX.getMarkInfo();
      isTagged = !!mi?.Marked;
    }
  } catch {
    // tolerate
  }

  checks.push({
    id: 'title',
    label: 'Document title',
    severity: title ? 'pass' : 'fail',
    detail: title
      ? `Title: "${title}"`
      : 'No document title set. Assistive tech often reads the file name instead.',
    fixable: !title
  });

  checks.push({
    id: 'language',
    label: 'Document language',
    severity: lang ? 'pass' : 'warn',
    detail: lang
      ? `Language: ${lang}`
      : 'No language declared. Screen readers may use the wrong voice/pronunciation.',
    fixable: !lang
  });

  checks.push({
    id: 'tagged',
    label: 'Tagged PDF structure',
    severity: isTagged ? 'pass' : 'warn',
    detail: isTagged
      ? 'Document declares MarkInfo.Marked = true.'
      : 'Document does not declare a tagged structure tree. Reading order may not be reliable.'
  });

  try {
    const outline = await doc.getOutline();
    const has = Array.isArray(outline) && outline.length > 0;
    checks.push({
      id: 'outline',
      label: 'Bookmarks / outline',
      severity: has ? 'pass' : 'info',
      detail: has
        ? `${outline!.length} top-level bookmark(s).`
        : 'No outline. Navigation by section is unavailable.'
    });
  } catch {
    // ignore
  }

  const numPages = doc.numPages;
  checks.push({
    id: 'pagecount',
    label: 'Page count',
    severity: numPages > 0 ? 'pass' : 'fail',
    detail: `${numPages} page(s).`
  });

  const sampleCount = Math.min(numPages, 10);
  let totalChars = 0;
  const orientations = new Set<'portrait' | 'landscape'>();
  for (let i = 1; i <= sampleCount; i++) {
    try {
      const page = await doc.getPage(i);
      const vp = page.getViewport({ scale: 1 });
      orientations.add(vp.width > vp.height ? 'landscape' : 'portrait');
      const tc = await page.getTextContent();
      for (const it of tc.items as Array<{ str?: string }>) totalChars += (it.str ?? '').length;
    } catch {
      // skip
    }
  }
  const charsPerPage = sampleCount > 0 ? totalChars / sampleCount : 0;
  checks.push({
    id: 'extractable-text',
    label: 'Extractable text',
    severity: charsPerPage >= 30 ? 'pass' : 'warn',
    detail:
      charsPerPage >= 30
        ? `Average ${Math.round(charsPerPage)} text characters per page (sampled ${sampleCount}).`
        : `Very little extractable text detected (avg ${Math.round(charsPerPage)} chars/page). This document may be a scanned image and require OCR for screen-reader access.`
  });

  checks.push({
    id: 'orientation',
    label: 'Consistent page orientation',
    severity: orientations.size <= 1 ? 'pass' : 'info',
    detail:
      orientations.size <= 1
        ? `All sampled pages are ${[...orientations][0] ?? 'consistent'}.`
        : 'Mixed portrait/landscape pages detected. Verify reading order is preserved.'
  });

  const pass = checks.filter((c) => c.severity === 'pass').length;
  const warn = checks.filter((c) => c.severity === 'warn').length;
  const fail = checks.filter((c) => c.severity === 'fail').length;
  return { checks, pass, warn, fail };
}
