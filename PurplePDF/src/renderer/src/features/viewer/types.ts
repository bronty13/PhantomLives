import { pdfjsLib, type PDFDocumentProxy } from './pdfjs';
import type { Annot, Tool } from '../annotate/types';
import type { PageOp } from '../annotate/flatten';
import type { FormFieldInfo, FormValues } from '../forms/types';

export type FitMode = 'custom' | 'fit-width' | 'fit-page';

export interface OutlineNode {
  title: string;
  pageIndex: number | null;
  children: OutlineNode[];
}

export interface FindMatch {
  pageIndex: number;
  start: number;
  end: number;
}

export interface HistorySnapshot {
  annotations: Annot[];
  pageOps: PageOp[];
}

export interface Tab {
  id: string;
  path: string;
  name: string;
  doc: PDFDocumentProxy;
  /** Cloned at load; used by pdf-lib for save. Never given to pdfjs. */
  originalBytes: ArrayBuffer;
  numPages: number;
  currentPage: number; // 1-based
  zoom: number;
  fitMode: FitMode;
  rotation: 0 | 90 | 180 | 270;
  outline: OutlineNode[];

  // Find
  findQuery: string;
  findMatches: FindMatch[];
  findIndex: number;
  findVisible: boolean;

  // Edit
  tool: Tool;
  color: string;
  /** Stroke / size in PDF points used by the active drawing tool. */
  strokeWidth: number;
  /** Per-tool memory of last-used color & size. */
  toolPrefs: Partial<Record<Tool, { color: string; strokeWidth: number }>>;
  annotations: Annot[];
  pageOps: PageOp[];
  selectedAnnotId: string | null;
  past: HistorySnapshot[];
  future: HistorySnapshot[];
  dirty: boolean;

  // Forms (P5)
  formFields: FormFieldInfo[];
  formValues: FormValues;
  formInitial: FormValues;
  formDirty: boolean;

  // Document properties (P7) — when present, written into the doc on next save.
  // Loaded from the original doc info dictionary at open time.
  properties: {
    title: string;
    author: string;
    subject: string;
    keywords: string;
    language: string;
  };

  /** Transient status text shown while OCR is running. */
  ocrStatus?: string;
}

export async function loadDocument(data: ArrayBuffer): Promise<PDFDocumentProxy> {
  // pdfjs mutates the input buffer; clone defensively.
  const buf = data.slice(0);
  const task = pdfjsLib.getDocument({ data: buf });
  return task.promise;
}

export async function loadDocumentInfo(
  doc: PDFDocumentProxy
): Promise<{ title: string; author: string; subject: string; keywords: string; language: string }> {
  try {
    const meta = (await doc.getMetadata()) as unknown as { info?: Record<string, unknown> };
    const info = meta.info ?? {};
    return {
      title: String(info.Title ?? ''),
      author: String(info.Author ?? ''),
      subject: String(info.Subject ?? ''),
      keywords: String(info.Keywords ?? ''),
      language: String(info.Language ?? '')
    };
  } catch {
    return { title: '', author: '', subject: '', keywords: '', language: '' };
  }
}

interface PdfOutlineEntry {
  title: string;
  dest: unknown;
  items: PdfOutlineEntry[];
}

export async function loadOutline(doc: PDFDocumentProxy): Promise<OutlineNode[]> {
  const raw = (await doc.getOutline()) as PdfOutlineEntry[] | null;
  if (!raw) return [];

  const resolve = async (entry: PdfOutlineEntry): Promise<OutlineNode> => {
    let pageIndex: number | null = null;
    try {
      let dest = entry.dest;
      if (typeof dest === 'string') {
        dest = await doc.getDestination(dest);
      }
      if (Array.isArray(dest) && dest[0]) {
        const ref = dest[0] as { num: number; gen: number };
        pageIndex = await doc.getPageIndex(ref);
      }
    } catch {
      pageIndex = null;
    }
    const children = await Promise.all((entry.items ?? []).map(resolve));
    return { title: entry.title, pageIndex, children };
  };

  return Promise.all(raw.map(resolve));
}
