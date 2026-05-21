import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { Tab, FitMode, FindMatch } from './types';
import { loadOutline } from './types';
import type { Annot, PdfRect, Tool } from '../annotate/types';
import { DEFAULT_COLORS, DEFAULT_SIZES, SIZE_STEPS, newId } from '../annotate/types';
import PageCanvas, { type PageViewportLike } from './PageCanvas';
import Thumbnails from './Thumbnails';
import OutlineTree from './OutlineTree';
import { projectPageOrderDetailed, type ProjectedSlot } from './projectOrder';
import FindBar from './FindBar';
import AnnotationLayer from '../annotate/AnnotationLayer';
import AccessibilityPanel from '../a11y/AccessibilityPanel';
import { runA11yChecks, type A11yReport } from '../a11y/checks';
import EditPalette from '../annotate/EditPalette';
import FormLayer from '../forms/FormLayer';
import FormsPanel from '../forms/FormsPanel';

type SidebarMode = 'thumbnails' | 'outline' | 'forms' | 'accessibility';

interface Props {
  tab: Tab;
  onUpdate: (patch: Partial<Tab>) => void;
  onSaveAs: () => void;
  onSave: () => void;
  onExportFormData: (format: 'json' | 'csv') => void;
  armedSignature: { bytes: Uint8Array; width: number; height: number } | null;
  /** Called when the user picks the Sign tool but has no signature armed. */
  onNeedSignature: () => void;
  onOpenProperties: () => void;
  /** Used by the Accessibility tab and Document → Accessibility Check menu. */
  a11yRefreshNonce: number;
}

export default function PDFViewer({
  tab,
  onUpdate,
  onSave,
  onSaveAs,
  onExportFormData,
  armedSignature,
  onNeedSignature,
  onOpenProperties,
  a11yRefreshNonce
}: Props): JSX.Element {
  const [sidebar, setSidebar] = useState<SidebarMode>('thumbnails');
  const [findSearching, setFindSearching] = useState(false);
  const [viewport, setViewport] = useState<PageViewportLike | null>(null);
  const scrollerRef = useRef<HTMLDivElement>(null);
  const [a11yReport, setA11yReport] = useState<A11yReport | null>(null);
  const [a11yLoading, setA11yLoading] = useState(false);
  const [a11yLocalNonce, setA11yLocalNonce] = useState(0);

  // Run a11y checks whenever the panel is shown, the doc changes, or an
  // explicit re-check is requested (via menu or panel button).
  useEffect(() => {
    if (sidebar !== 'accessibility') return;
    let cancelled = false;
    setA11yLoading(true);
    runA11yChecks(tab.doc)
      .then((r) => {
        if (!cancelled) setA11yReport(r);
      })
      .catch(() => undefined)
      .finally(() => {
        if (!cancelled) setA11yLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [sidebar, tab.doc, a11yRefreshNonce, a11yLocalNonce]);

  useEffect(() => {
    if (tab.outline.length === 0) {
      loadOutline(tab.doc).then((o) => onUpdate({ outline: o }));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab.doc]);

  // ----- Projected page ordering (queued pageOps applied virtually) -----
  const projected: ProjectedSlot[] = useMemo(
    () => projectPageOrderDetailed(tab.pageOps, tab.numPages),
    [tab.pageOps, tab.numPages]
  );
  const displayTotal = projected.length || 1;
  // Keep currentPage within bounds when ops change the page count.
  useEffect(() => {
    if (tab.currentPage > displayTotal) onUpdate({ currentPage: displayTotal });
    else if (tab.currentPage < 1) onUpdate({ currentPage: 1 });
  }, [displayTotal, tab.currentPage, onUpdate]);
  const currentSlot: ProjectedSlot | null =
    projected.length > 0 ? projected[Math.min(displayTotal, Math.max(1, tab.currentPage)) - 1] : null;
  const currentSourceIdx: number | null = currentSlot?.source ?? null;

  // Compute zoom from fit mode against the container size.
  useEffect(() => {
    if (tab.fitMode === 'custom') return;
    const recompute = async (): Promise<void> => {
      const scroller = scrollerRef.current;
      if (!scroller) return;
      const srcPage = currentSourceIdx != null ? currentSourceIdx + 1 : 1;
      const page = await tab.doc.getPage(srcPage);
      const v = page.getViewport({ scale: 1, rotation: tab.rotation });
      const pad = 32;
      const availW = scroller.clientWidth - pad;
      const availH = scroller.clientHeight - pad;
      const scaleW = availW / v.width;
      const scaleH = availH / v.height;
      const scale = tab.fitMode === 'fit-width' ? scaleW : Math.min(scaleW, scaleH);
      if (Math.abs(scale - tab.zoom) > 0.005) onUpdate({ zoom: scale });
    };
    recompute();
    const ro = new ResizeObserver(() => void recompute());
    if (scrollerRef.current) ro.observe(scrollerRef.current);
    return () => ro.disconnect();
  }, [tab.doc, currentSourceIdx, tab.rotation, tab.fitMode, tab.zoom, onUpdate]);

  const goto = useCallback(
    (p: number) => onUpdate({ currentPage: Math.max(1, Math.min(displayTotal, p)) }),
    [onUpdate, displayTotal]
  );
  const zoomBy = useCallback(
    (factor: number) =>
      onUpdate({ zoom: Math.max(0.1, Math.min(8, tab.zoom * factor)), fitMode: 'custom' }),
    [onUpdate, tab.zoom]
  );
  const setFit = useCallback((mode: FitMode) => onUpdate({ fitMode: mode }), [onUpdate]);
  const rotate = useCallback(
    (dir: 'cw' | 'ccw') => {
      const delta = dir === 'cw' ? 90 : -90;
      const next = (((tab.rotation + delta) % 360) + 360) % 360;
      onUpdate({ rotation: next as 0 | 90 | 180 | 270 });
    },
    [onUpdate, tab.rotation]
  );

  // ----- Annotation history -----
  const commitHistory = useCallback(
    (patch: Partial<Tab>): Partial<Tab> => {
      const snapshot = { annotations: tab.annotations, pageOps: tab.pageOps };
      return {
        past: [...tab.past, snapshot].slice(-100),
        future: [],
        dirty: true,
        ...patch
      };
    },
    [tab.annotations, tab.pageOps, tab.past]
  );

  const createAnnot = useCallback(
    (a: Annot) => onUpdate(commitHistory({ annotations: [...tab.annotations, a] })),
    [commitHistory, onUpdate, tab.annotations]
  );
  const updateAnnot = useCallback(
    (id: string, patch: Partial<Annot>) =>
      onUpdate(
        commitHistory({
          annotations: tab.annotations.map((a) =>
            a.id === id ? ({ ...a, ...patch } as Annot) : a
          )
        })
      ),
    [commitHistory, onUpdate, tab.annotations]
  );
  const deleteAnnot = useCallback(
    (id: string) =>
      onUpdate(commitHistory({ annotations: tab.annotations.filter((a) => a.id !== id) })),
    [commitHistory, onUpdate, tab.annotations]
  );

  // ----- Page ops -----
  const queuePageOp = useCallback(
    (op: {
      kind: 'delete' | 'rotate' | 'insert-blank' | 'duplicate' | 'move' | 'crop';
      page: number;
      degrees?: number;
      to?: number;
      crop?: { x: number; y: number; width: number; height: number };
    }) => onUpdate(commitHistory({ pageOps: [...tab.pageOps, op] })),
    [commitHistory, onUpdate, tab.pageOps]
  );

  const deletePage = useCallback(() => {
    if (displayTotal <= 1 || currentSourceIdx == null) return;
    queuePageOp({ kind: 'delete', page: currentSourceIdx });
  }, [queuePageOp, displayTotal, currentSourceIdx]);
  const rotatePage = useCallback(() => {
    if (currentSourceIdx == null) return;
    queuePageOp({ kind: 'rotate', page: currentSourceIdx, degrees: 90 });
  }, [queuePageOp, currentSourceIdx]);
  const insertBlank = useCallback(() => {
    if (currentSourceIdx == null) return;
    queuePageOp({ kind: 'insert-blank', page: currentSourceIdx });
  }, [queuePageOp, currentSourceIdx]);

  /** Handler for the Thumbnails right-click context menu. `pageNumber` is 1-based. */
  const onThumbAction = useCallback(
    (action: 'delete' | 'rotate-cw' | 'rotate-ccw' | 'duplicate' | 'insert-blank' | 'extract', pageNumber: number) => {
      const idx = pageNumber - 1;
      if (action === 'delete') {
        if (tab.numPages <= 1) return;
        queuePageOp({ kind: 'delete', page: idx });
      } else if (action === 'rotate-cw') {
        queuePageOp({ kind: 'rotate', page: idx, degrees: 90 });
      } else if (action === 'rotate-ccw') {
        queuePageOp({ kind: 'rotate', page: idx, degrees: 270 });
      } else if (action === 'duplicate') {
        queuePageOp({ kind: 'duplicate', page: idx });
      } else if (action === 'insert-blank') {
        queuePageOp({ kind: 'insert-blank', page: idx });
      } else if (action === 'extract') {
        window.dispatchEvent(
          new CustomEvent('purplepdf:extract-page', { detail: { page: pageNumber } })
        );
      }
    },
    [queuePageOp, tab.numPages]
  );

  /** Drag-and-drop reorder from the Thumbnails sidebar.
   * `from` is 1-based projected position; `to` is 0-based insertion index
   * in the current ordering. Translate to the original-index space used by
   * the move op. */
  const onThumbReorder = useCallback(
    (from: number, to: number) => {
      const slot = projected[from - 1];
      if (!slot || slot.source == null) return;
      queuePageOp({ kind: 'move', page: slot.source, to });
    },
    [queuePageOp, projected]
  );

  // ----- Undo / redo -----
  const undo = useCallback(() => {
    if (tab.past.length === 0) return;
    const prev = tab.past[tab.past.length - 1];
    const newPast = tab.past.slice(0, -1);
    onUpdate({
      past: newPast,
      future: [{ annotations: tab.annotations, pageOps: tab.pageOps }, ...tab.future],
      annotations: prev.annotations,
      pageOps: prev.pageOps,
      dirty: newPast.length > 0
    });
  }, [onUpdate, tab.past, tab.future, tab.annotations, tab.pageOps]);

  const redo = useCallback(() => {
    if (tab.future.length === 0) return;
    const next = tab.future[0];
    onUpdate({
      past: [...tab.past, { annotations: tab.annotations, pageOps: tab.pageOps }],
      future: tab.future.slice(1),
      annotations: next.annotations,
      pageOps: next.pageOps,
      dirty: true
    });
  }, [onUpdate, tab.past, tab.future, tab.annotations, tab.pageOps]);

  const setTool = useCallback(
    (t: Tool) => {
      const prevTool = tab.tool;
      const prevPrefs = tab.toolPrefs ?? {};
      // Save the current color+size as the prefs for the OLD tool (unless it's select).
      const nextPrefs = { ...prevPrefs };
      if (prevTool !== 'select') {
        nextPrefs[prevTool] = { color: tab.color, strokeWidth: tab.strokeWidth ?? 2 };
      }
      // Restore prefs for the NEW tool, else use defaults.
      const restored = nextPrefs[t];
      const patch: Partial<Tab> = {
        tool: t,
        color: restored?.color ?? DEFAULT_COLORS[t] ?? tab.color,
        strokeWidth: restored?.strokeWidth ?? DEFAULT_SIZES[t] ?? 2,
        toolPrefs: nextPrefs
      };
      onUpdate(patch);
      // Auto-prompt the signature modal when picking Sign with no armed signature.
      if (t === 'signature' && !armedSignature) {
        onNeedSignature();
      }
    },
    [onUpdate, tab.tool, tab.color, tab.strokeWidth, tab.toolPrefs, armedSignature, onNeedSignature]
  );

  const setColor = useCallback(
    (c: string) => {
      const prefs = { ...(tab.toolPrefs ?? {}) };
      if (tab.tool !== 'select') {
        prefs[tab.tool] = { color: c, strokeWidth: tab.strokeWidth ?? 2 };
      }
      onUpdate({ color: c, toolPrefs: prefs });
    },
    [onUpdate, tab.tool, tab.strokeWidth, tab.toolPrefs]
  );

  const setStrokeWidth = useCallback(
    (w: number) => {
      const prefs = { ...(tab.toolPrefs ?? {}) };
      if (tab.tool !== 'select') {
        prefs[tab.tool] = { color: tab.color, strokeWidth: w };
      }
      onUpdate({ strokeWidth: w, toolPrefs: prefs });
    },
    [onUpdate, tab.tool, tab.color, tab.toolPrefs]
  );

  // ----- Keyboard shortcuts: tools & size -----
  useEffect(() => {
    const handler = (e: KeyboardEvent): void => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const target = e.target as HTMLElement | null;
      if (target) {
        const tag = target.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
        if (target.isContentEditable) return;
      }
      const KEY_TO_TOOL: Record<string, Tool> = {
        v: 'select',
        h: 'highlight',
        u: 'underline',
        s: 'strikethrough',
        n: 'note',
        p: 'freehand',
        r: 'rect',
        t: 'textbox',
        g: 'signature',
        x: 'redact'
      };
      const k = e.key.toLowerCase();
      if (k in KEY_TO_TOOL) {
        e.preventDefault();
        setTool(KEY_TO_TOOL[k]);
        return;
      }
      if (e.key === '[' || e.key === ']') {
        const steps = SIZE_STEPS as readonly number[];
        const cur = tab.strokeWidth ?? 2;
        let idx = steps.findIndex((s) => Math.abs(s - cur) < 0.5);
        if (idx < 0) idx = 1;
        const next = e.key === '[' ? Math.max(0, idx - 1) : Math.min(steps.length - 1, idx + 1);
        if (next !== idx) {
          e.preventDefault();
          setStrokeWidth(steps[next]);
        }
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [setTool, setStrokeWidth, tab.strokeWidth]);

  // ----- Find -----
  const runFind = useCallback(
    async (q: string): Promise<void> => {
      onUpdate({ findQuery: q });
      if (!q) {
        onUpdate({ findMatches: [], findIndex: -1 });
        return;
      }
      setFindSearching(true);
      const results: FindMatch[] = [];
      const lower = q.toLowerCase();
      for (let p = 1; p <= tab.numPages; p++) {
        const page = await tab.doc.getPage(p);
        const tc = await page.getTextContent();
        const full = (tc.items as Array<{ str: string }>).map((i) => i.str).join('');
        const hay = full.toLowerCase();
        let from = 0;
        for (;;) {
          const idx = hay.indexOf(lower, from);
          if (idx === -1) break;
          results.push({ pageIndex: p - 1, start: idx, end: idx + q.length });
          from = idx + Math.max(1, q.length);
        }
      }
      setFindSearching(false);
      // Translate origin page idx -> first projected position that holds it.
      const firstResultProjected = (origIdx: number): number => {
        const i = projected.findIndex((s) => s.source === origIdx);
        return i >= 0 ? i + 1 : tab.currentPage;
      };
      onUpdate({
        findMatches: results,
        findIndex: results.length > 0 ? 0 : -1,
        currentPage: results.length > 0 ? firstResultProjected(results[0].pageIndex) : tab.currentPage
      });
    },
    [onUpdate, tab.doc, tab.numPages, tab.currentPage, projected]
  );

  const stepMatch = useCallback(
    (delta: number) => {
      if (tab.findMatches.length === 0) return;
      const next = (tab.findIndex + delta + tab.findMatches.length) % tab.findMatches.length;
      const m = tab.findMatches[next];
      const projIdx = projected.findIndex((s) => s.source === m.pageIndex);
      onUpdate({ findIndex: next, currentPage: projIdx >= 0 ? projIdx + 1 : tab.currentPage });
    },
    [onUpdate, tab.findMatches, tab.findIndex, projected, tab.currentPage]
  );

  const currentHighlight = useMemo(() => {
    if (tab.findIndex < 0) return null;
    const m = tab.findMatches[tab.findIndex];
    if (currentSourceIdx == null || m.pageIndex !== currentSourceIdx) return null;
    return { start: m.start, end: m.end };
  }, [tab.findIndex, tab.findMatches, currentSourceIdx]);

  // ----- Markup creation from text selection -----
  const onCreateMarkup = useCallback(
    (rects: PdfRect[]) => {
      if (tab.tool !== 'highlight' && tab.tool !== 'underline' && tab.tool !== 'strikethrough') {
        return;
      }
      if (currentSourceIdx == null) return;
      const a: Annot = {
        id: newId(),
        page: currentSourceIdx,
        kind: tab.tool,
        rects,
        color: tab.color
      };
      createAnnot(a);
    },
    [createAnnot, tab.tool, tab.color, currentSourceIdx]
  );

  const handleViewportReady = useCallback((vp: PageViewportLike) => {
    setViewport(vp);
  }, []);

  const annotsThisPage = useMemo(
    () =>
      currentSourceIdx == null
        ? []
        : tab.annotations.filter((a) => a.page === currentSourceIdx),
    [tab.annotations, currentSourceIdx]
  );

  return (
    <div className="viewer">
      <div className="toolbar" role="toolbar" aria-label="Viewer toolbar">
        <div className="toolbar-group">
          <button
            type="button"
            onClick={() => setSidebar(sidebar === 'thumbnails' ? 'outline' : 'thumbnails')}
            title="Toggle sidebar"
            aria-label="Toggle sidebar"
          >
            ☰
          </button>
        </div>
        <div className="toolbar-group">
          <button type="button" onClick={() => goto(tab.currentPage - 1)} aria-label="Previous page">
            ‹
          </button>
          <input
            className="page-input"
            type="number"
            min={1}
            max={displayTotal}
            value={tab.currentPage}
            onChange={(e) => goto(parseInt(e.target.value, 10) || 1)}
            aria-label="Current page"
          />
          <span className="page-of">/ {displayTotal}</span>
          <button type="button" onClick={() => goto(tab.currentPage + 1)} aria-label="Next page">
            ›
          </button>
        </div>
        <div className="toolbar-group">
          <button type="button" onClick={() => zoomBy(1 / 1.2)} aria-label="Zoom out">
            −
          </button>
          <span className="zoom-label">{Math.round(tab.zoom * 100)}%</span>
          <button type="button" onClick={() => zoomBy(1.2)} aria-label="Zoom in">
            +
          </button>
          <button type="button" onClick={() => setFit('fit-width')} title="Fit width">
            ⇔
          </button>
          <button type="button" onClick={() => setFit('fit-page')} title="Fit page">
            ⛶
          </button>
        </div>
        <div className="toolbar-group">
          <button type="button" onClick={() => rotate('ccw')} aria-label="Rotate view counterclockwise">
            ↺
          </button>
          <button type="button" onClick={() => rotate('cw')} aria-label="Rotate view clockwise">
            ↻
          </button>
        </div>
        <div className="toolbar-group">
          <button type="button" onClick={undo} disabled={tab.past.length === 0} title="Undo (⌘Z)">
            ⤺
          </button>
          <button type="button" onClick={redo} disabled={tab.future.length === 0} title="Redo (⌘⇧Z)">
            ⤻
          </button>
        </div>
        <div className="toolbar-group toolbar-grow" />
        <div className="toolbar-group">
          <button type="button" onClick={onSave} title="Save (⌘S)" disabled={!tab.dirty}>
            Save{tab.dirty ? ' •' : ''}
          </button>
          <button type="button" onClick={onSaveAs} title="Save As… (⌘⇧S)">
            Save As…
          </button>
          <button
            type="button"
            onClick={() => onUpdate({ findVisible: !tab.findVisible })}
            aria-label="Find"
            title="Find (⌘F)"
          >
            🔍
          </button>
        </div>
      </div>

      <EditPalette
        tool={tab.tool}
        color={tab.color}
        strokeWidth={tab.strokeWidth ?? 2}
        onToolChange={setTool}
        onColorChange={setColor}
        onStrokeWidthChange={setStrokeWidth}
        onDeletePage={deletePage}
        onRotatePage={rotatePage}
        onInsertBlank={insertBlank}
      />

      <ToolHint tool={tab.tool} armedSignature={!!armedSignature} />

      {tab.findVisible && (
        <FindBar
          query={tab.findQuery}
          matches={tab.findMatches}
          index={tab.findIndex}
          searching={findSearching}
          onChange={(q) => void runFind(q)}
          onNext={() => stepMatch(1)}
          onPrev={() => stepMatch(-1)}
          onClose={() => onUpdate({ findVisible: false })}
        />
      )}

      <div className="viewer-body">
        <aside className="sidebar" aria-label="Document sidebar">
          <div className="sidebar-tabs" role="tablist">
            <button
              role="tab"
              aria-selected={sidebar === 'thumbnails'}
              className={sidebar === 'thumbnails' ? 'active' : ''}
              onClick={() => setSidebar('thumbnails')}
            >
              Pages
            </button>
            <button
              role="tab"
              aria-selected={sidebar === 'outline'}
              className={sidebar === 'outline' ? 'active' : ''}
              onClick={() => setSidebar('outline')}
            >
              Outline
            </button>
            <button
              role="tab"
              aria-selected={sidebar === 'forms'}
              className={sidebar === 'forms' ? 'active' : ''}
              onClick={() => setSidebar('forms')}
            >
              Forms{tab.formFields.length > 0 ? ` (${new Set(tab.formFields.map((f) => f.fieldName)).size})` : ''}
            </button>
            <button
              role="tab"
              aria-selected={sidebar === 'accessibility'}
              className={sidebar === 'accessibility' ? 'active' : ''}
              onClick={() => setSidebar('accessibility')}
              title="Accessibility check"
            >
              A11y
            </button>
          </div>
          <div className="sidebar-body">
            {sidebar === 'thumbnails' && (
              <Thumbnails
                doc={tab.doc}
                numPages={tab.numPages}
                currentPage={tab.currentPage}
                projectedOrder={projected.map((s) => (s.source == null ? -1 : s.source))}
                currentIndex={tab.currentPage - 1}
                onSelect={goto}
                onPageAction={onThumbAction}
                onReorder={onThumbReorder}
              />
            )}
            {sidebar === 'outline' && <OutlineTree outline={tab.outline} onSelect={goto} />}
            {sidebar === 'forms' && (
              <FormsPanel
                fields={tab.formFields}
                values={tab.formValues}
                onJump={(pageIndex) => goto(pageIndex)}
                onReset={() =>
                  onUpdate({ formValues: { ...tab.formInitial }, formDirty: false })
                }
                onExportJson={() => onExportFormData('json')}
                onExportCsv={() => onExportFormData('csv')}
              />
            )}
            {sidebar === 'accessibility' && (
              <AccessibilityPanel
                report={a11yReport}
                loading={a11yLoading}
                onRecheck={() => setA11yLocalNonce((n) => n + 1)}
                onOpenProperties={onOpenProperties}
              />
            )}
          </div>
        </aside>

        <div className="page-scroller" ref={scrollerRef}>
          <div className="page-stack">
            <PageCanvas
              doc={tab.doc}
              pageNumber={currentSourceIdx == null ? null : currentSourceIdx + 1}
              zoom={tab.zoom}
              rotation={tab.rotation}
              extraRotation={currentSlot?.rotation ?? 0}
              cropOverlay={currentSlot?.crop ?? null}
              highlight={currentHighlight}
              tool={tab.tool}
              onViewportReady={handleViewportReady}
              onCreateMarkup={onCreateMarkup}
            />
            {viewport && currentSourceIdx != null && (
              <FormLayer
                pageIndex={currentSourceIdx}
                viewport={viewport}
                fields={tab.formFields}
                values={tab.formValues}
                enabled={tab.tool === 'select'}
                onChange={(fieldName, value) =>
                  onUpdate({
                    formValues: { ...tab.formValues, [fieldName]: value },
                    formDirty: true,
                    dirty: true
                  })
                }
              />
            )}
            {viewport && currentSourceIdx != null && (
              <AnnotationLayer
                pageIndex={currentSourceIdx}
                viewport={viewport}
                annotations={annotsThisPage}
                tool={tab.tool}
                color={tab.color}
                strokeWidth={tab.strokeWidth ?? 2}
                armedSignature={armedSignature}
                onCreate={createAnnot}
                onUpdate={updateAnnot}
                onDelete={deleteAnnot}
                selectedId={tab.selectedAnnotId}
                onSelect={(id) => onUpdate({ selectedAnnotId: id })}
              />
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

const TOOL_HINTS: Record<Tool, { label: string; how: string }> = {
  select: {
    label: 'Select',
    how: 'Click an annotation to select it; press Delete to remove. Drag handles to move/resize.'
  },
  highlight: {
    label: 'Highlight',
    how: 'Drag a rectangle over the text or area you want to highlight. Pick a color from the palette.'
  },
  underline: {
    label: 'Underline',
    how: 'Drag a rectangle over the text you want to underline.'
  },
  strikethrough: {
    label: 'Strikethrough',
    how: 'Drag a rectangle over the text you want to strike through.'
  },
  note: { label: 'Sticky Note', how: 'Click anywhere to drop a note; type your comment.' },
  freehand: { label: 'Draw', how: 'Click and drag to draw freehand strokes.' },
  rect: { label: 'Rectangle', how: 'Click and drag to draw a rectangle outline.' },
  textbox: {
    label: 'Text Box',
    how: 'Drag a rectangle where you want text; type to fill it. To replace existing text, use Redact (■) over the old text first, then add a Text Box.'
  },
  signature: {
    label: 'Sign',
    how: 'Create or select a signature in the dialog that just opened, then click on the page to place it.'
  },
  redact: {
    label: 'Redact / Whiteout',
    how: 'Drag a rectangle to cover content. On Save, the underlying text/image is permanently removed.'
  },
  crop: {
    label: 'Crop Page',
    how: 'Drag a rectangle to set the crop box for the current page. The crop is applied on Save.'
  }
};

function ToolHint({
  tool,
  armedSignature
}: {
  tool: Tool;
  armedSignature: boolean;
}): JSX.Element {
  const info = TOOL_HINTS[tool];
  const extra =
    tool === 'signature' && !armedSignature
      ? ' (No signature yet — pick "Add Signature" in the dialog.)'
      : '';
  return (
    <div className="tool-hint" role="status" aria-live="polite">
      <span className="tool-hint-label">{info.label}</span>
      <span className="tool-hint-sep">·</span>
      <span className="tool-hint-how">
        {info.how}
        {extra}
      </span>
    </div>
  );
}
