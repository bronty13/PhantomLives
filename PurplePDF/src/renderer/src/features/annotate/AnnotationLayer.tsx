import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react';
import type {
  Annot,
  NoteAnnot,
  PdfPoint,
  SignatureAnnot,
  RedactAnnot,
  StampAnnot,
  ImageAnnot,
  Tool
} from './types';
import { newId } from './types';
import { buildStampSubtext, primeStampUser } from './userInfo';

void primeStampUser();

interface Viewport {
  width: number;
  height: number;
  convertToViewportPoint: (x: number, y: number) => number[];
  convertToPdfPoint: (x: number, y: number) => number[];
}

/** Result returned by the stamp picker when user clicks a preset. */
export interface ArmedStamp {
  label: string;
  style: 'rect' | 'mark';
  color: string;
  width: number;
  height: number;
  /** When true, current date/time is frozen onto the stamp at placement. */
  includeDate: boolean;
  /** When true, "By {user}" is added to the subtitle. */
  includeUser: boolean;
}

/** Image bytes ready to drop on the page (PNG/JPEG, with intrinsic
 *  pixel dimensions for aspect-ratio defaults). */
export interface ArmedImage {
  bytes: Uint8Array;
  mime: 'image/png' | 'image/jpeg';
  naturalWidth: number;
  naturalHeight: number;
  /** Default placement width in PDF points (height derived from aspect). */
  placeWidthPt?: number;
  /** Optional alt text passed through to the annotation. */
  alt?: string;
  /** When true, freeze a "By {user} at {date}" caption onto the image at
   *  placement (rendered as a bottom-edge overlay band). Comes from a
   *  custom image stamp's `defaultIncludeSubtitle`. */
  includeSubtitle?: boolean;
}

interface Props {
  pageIndex: number; // 0-based
  viewport: Viewport;
  annotations: Annot[];
  tool: Tool;
  color: string;
  /** Stroke width in PDF points for freehand / rect / underline / strikethrough. */
  strokeWidth: number;
  /** PNG bytes of the "armed" signature; when set and tool='signature',
   * clicking on the page places it at click point with derived size. */
  armedSignature: { bytes: Uint8Array; width: number; height: number } | null;
  /** Aspect-ratio-preserving default width in PDF points used for signature placement. */
  signaturePlaceWidthPt?: number;
  /** Currently-armed stamp preset; when set and tool='stamp', clicking on the page places it. */
  armedStamp: ArmedStamp | null;
  /** Currently-armed image; when set and tool='image', clicking on the page places it. */
  armedImage: ArmedImage | null;
  onCreate: (a: Annot) => void;
  onUpdate: (id: string, patch: Partial<Annot>) => void;
  onDelete: (id: string) => void;
  selectedId: string | null;
  onSelect: (id: string | null) => void;
}

function pdfToVp(vp: Viewport, x: number, y: number): [number, number] {
  const r = vp.convertToViewportPoint(x, y);
  return [r[0], r[1]];
}

function pdfRectToSvg(
  vp: Viewport,
  r: { x: number; y: number; w: number; h: number }
): { x: number; y: number; w: number; h: number } {
  const [x1, y1] = pdfToVp(vp, r.x, r.y);
  const [x2, y2] = pdfToVp(vp, r.x + r.w, r.y + r.h);
  return {
    x: Math.min(x1, x2),
    y: Math.min(y1, y2),
    w: Math.abs(x2 - x1),
    h: Math.abs(y2 - y1)
  };
}

/** Annotation kinds whose bounding rect can be drag-resized via handles. */
type ResizableKind = 'rect' | 'textbox' | 'signature' | 'redact' | 'stamp' | 'image';
function isResizable(a: Annot): a is Extract<Annot, { kind: ResizableKind }> {
  return (
    a.kind === 'rect' ||
    a.kind === 'textbox' ||
    a.kind === 'signature' ||
    a.kind === 'redact' ||
    a.kind === 'stamp' ||
    a.kind === 'image'
  );
}

interface DraftFreehand {
  kind: 'freehand';
  vpPoints: { x: number; y: number }[];
}
interface DraftRect {
  kind: 'rect' | 'textbox' | 'redact' | 'highlight' | 'underline' | 'strikethrough' | 'crop';
  x0: number;
  y0: number;
  x1: number;
  y1: number;
}
type Draft = DraftFreehand | DraftRect | null;

type HandleId = 'nw' | 'n' | 'ne' | 'e' | 'se' | 's' | 'sw' | 'w';

interface DragState {
  kind: 'move';
  id: string;
  startVp: { x: number; y: number };
  dxVp: number;
  dyVp: number;
}
interface ResizeState {
  kind: 'resize';
  id: string;
  handle: HandleId;
  startVp: { x: number; y: number };
  origPdf: { x: number; y: number; w: number; h: number };
}
type Interaction = DragState | ResizeState | null;

export default function AnnotationLayer({
  pageIndex,
  viewport,
  annotations,
  tool,
  color,
  strokeWidth,
  armedSignature,
  signaturePlaceWidthPt = 140,
  armedStamp,
  armedImage,
  onCreate,
  onUpdate,
  onDelete,
  selectedId,
  onSelect
}: Props): JSX.Element {
  const svgRef = useRef<SVGSVGElement>(null);
  const [draft, setDraft] = useState<Draft>(null);
  const [interaction, setInteraction] = useState<Interaction>(null);
  const [editingNoteId, setEditingNoteId] = useState<string | null>(null);
  const [editingTextboxId, setEditingTextboxId] = useState<string | null>(null);

  // Pointer events only intercepted when a creating tool is active.
  const interactive =
    tool === 'freehand' ||
    tool === 'rect' ||
    tool === 'textbox' ||
    tool === 'note' ||
    tool === 'select' ||
    tool === 'redact' ||
    tool === 'highlight' ||
    tool === 'underline' ||
    tool === 'strikethrough' ||
    tool === 'crop' ||
    (tool === 'signature' && !!armedSignature) ||
    (tool === 'stamp' && !!armedStamp) ||
    (tool === 'image' && !!armedImage);

  const localPoint = (e: ReactPointerEvent<SVGSVGElement>): { x: number; y: number } => {
    const rect = svgRef.current!.getBoundingClientRect();
    return { x: e.clientX - rect.left, y: e.clientY - rect.top };
  };

  const onPointerDown = (e: ReactPointerEvent<SVGSVGElement>): void => {
    if (tool === 'select') {
      // Click on empty area clears selection (AnnotShape calls stopPropagation
      // when the hit lands on a real annotation).
      if (e.target === e.currentTarget) onSelect(null);
      return;
    }
    if (tool === 'note') {
      const { x, y } = localPoint(e);
      const [px, py] = viewport.convertToPdfPoint(x, y);
      const note: NoteAnnot = {
        id: newId(),
        page: pageIndex,
        kind: 'note',
        x: px,
        y: py,
        text: '',
        color
      };
      onCreate(note);
      setEditingNoteId(note.id);
      return;
    }
    if (tool === 'signature' && armedSignature) {
      const { x, y } = localPoint(e);
      const [px, py] = viewport.convertToPdfPoint(x, y);
      const w = signaturePlaceWidthPt;
      const h = (armedSignature.height / armedSignature.width) * w;
      // Click point becomes top-left; PDF y-axis is up, so subtract h from py.
      const sig: SignatureAnnot = {
        id: newId(),
        page: pageIndex,
        kind: 'signature',
        x: px,
        y: py - h,
        w,
        h,
        pngBytes: armedSignature.bytes,
        color
      };
      onCreate(sig);
      return;
    }
    if (tool === 'stamp' && armedStamp) {
      const { x, y } = localPoint(e);
      const [px, py] = viewport.convertToPdfPoint(x, y);
      const sub =
        armedStamp.style === 'mark'
          ? ''
          : buildStampSubtext({
              includeUser: armedStamp.includeUser,
              includeDate: armedStamp.includeDate
            });
      const stamp: StampAnnot = {
        id: newId(),
        page: pageIndex,
        kind: 'stamp',
        x: px - armedStamp.width / 2,
        y: py - armedStamp.height / 2,
        w: armedStamp.width,
        h: armedStamp.height,
        label: armedStamp.label,
        subtext: sub || undefined,
        style: armedStamp.style,
        color: armedStamp.color,
        borderColor: armedStamp.color
      };
      onCreate(stamp);
      return;
    }
    if (tool === 'image' && armedImage) {
      const { x, y } = localPoint(e);
      const [px, py] = viewport.convertToPdfPoint(x, y);
      const w = armedImage.placeWidthPt ?? 200;
      const h = (armedImage.naturalHeight / Math.max(1, armedImage.naturalWidth)) * w;
      // Freeze a user+date caption when the source stamp opted in. Mirrors
      // the rect-stamp subtitle, but always carries both (the image-stamp
      // toggle is a single boolean — see CustomImageStamp.defaultIncludeSubtitle).
      const imgSub = armedImage.includeSubtitle
        ? buildStampSubtext({ includeUser: true, includeDate: true })
        : '';
      const img: ImageAnnot = {
        id: newId(),
        page: pageIndex,
        kind: 'image',
        x: px - w / 2,
        y: py - h / 2,
        w,
        h,
        bytes: armedImage.bytes,
        mime: armedImage.mime,
        naturalWidth: armedImage.naturalWidth,
        naturalHeight: armedImage.naturalHeight,
        alt: armedImage.alt,
        subtext: imgSub || undefined,
        color
      };
      onCreate(img);
      return;
    }
    const p = localPoint(e);
    svgRef.current!.setPointerCapture(e.pointerId);
    if (tool === 'freehand') {
      setDraft({ kind: 'freehand', vpPoints: [p] });
    } else if (
      tool === 'rect' ||
      tool === 'textbox' ||
      tool === 'redact' ||
      tool === 'highlight' ||
      tool === 'underline' ||
      tool === 'strikethrough' ||
      tool === 'crop'
    ) {
      setDraft({ kind: tool, x0: p.x, y0: p.y, x1: p.x, y1: p.y });
    }
  };

  const onPointerMove = (e: ReactPointerEvent<SVGSVGElement>): void => {
    if (interaction) {
      const p = localPoint(e);
      if (interaction.kind === 'move') {
        setInteraction({
          ...interaction,
          dxVp: p.x - interaction.startVp.x,
          dyVp: p.y - interaction.startVp.y
        });
      } else {
        // resize uses startVp + handle to compute new rect on commit; track current
        // pointer by stashing into startVp delta via re-render trigger.
        setInteraction({ ...interaction, startVp: interaction.startVp /* keep */ });
        // We need the live pointer for preview. Store on a ref pattern below.
        livePointerRef.current = p;
        // Force a render by toggling a no-op state via setInteraction above.
      }
      return;
    }
    if (!draft) return;
    const p = localPoint(e);
    if (draft.kind === 'freehand') {
      setDraft({ kind: 'freehand', vpPoints: [...draft.vpPoints, p] });
    } else {
      setDraft({ ...draft, x1: p.x, y1: p.y });
    }
  };

  const livePointerRef = useRef<{ x: number; y: number } | null>(null);

  const onPointerUp = (e: ReactPointerEvent<SVGSVGElement>): void => {
    if (interaction) {
      const annot = annotations.find((a) => a.id === interaction.id);
      try {
        svgRef.current!.releasePointerCapture(e.pointerId);
      } catch {
        // pointer wasn't captured here — fine
      }
      if (annot) {
        if (interaction.kind === 'move') {
          commitMove(annot, interaction.dxVp, interaction.dyVp);
        } else {
          const live = livePointerRef.current ?? interaction.startVp;
          commitResize(annot, interaction, live);
        }
      }
      livePointerRef.current = null;
      setInteraction(null);
      return;
    }
    if (!draft) return;
    svgRef.current!.releasePointerCapture(e.pointerId);
    if (draft.kind === 'freehand' && draft.vpPoints.length > 1) {
      const points: PdfPoint[] = draft.vpPoints.map((pt) => {
        const [px, py] = viewport.convertToPdfPoint(pt.x, pt.y);
        return { x: px, y: py };
      });
      onCreate({
        id: newId(),
        page: pageIndex,
        kind: 'freehand',
        points,
        color,
        width: strokeWidth
      });
    } else if (
      draft.kind === 'rect' ||
      draft.kind === 'textbox' ||
      draft.kind === 'redact' ||
      draft.kind === 'highlight' ||
      draft.kind === 'underline' ||
      draft.kind === 'strikethrough' ||
      draft.kind === 'crop'
    ) {
      const [x1, y1] = viewport.convertToPdfPoint(draft.x0, draft.y0);
      const [x2, y2] = viewport.convertToPdfPoint(draft.x1, draft.y1);
      const x = Math.min(x1, x2);
      const y = Math.min(y1, y2);
      const w = Math.abs(x2 - x1);
      const h = Math.abs(y2 - y1);
      if (w >= 2 && h >= 2) {
        if (draft.kind === 'crop') {
          window.dispatchEvent(
            new CustomEvent('purplepdf:crop-region', {
              detail: { page: pageIndex, x, y, width: w, height: h }
            })
          );
        } else if (draft.kind === 'rect') {
          onCreate({
            id: newId(),
            page: pageIndex,
            kind: 'rect',
            x,
            y,
            w,
            h,
            color,
            strokeWidth
          });
        } else if (draft.kind === 'redact') {
          const r: RedactAnnot = {
            id: newId(),
            page: pageIndex,
            kind: 'redact',
            x,
            y,
            w,
            h,
            color: '#000000'
          };
          onCreate(r);
        } else if (
          draft.kind === 'highlight' ||
          draft.kind === 'underline' ||
          draft.kind === 'strikethrough'
        ) {
          onCreate({
            id: newId(),
            page: pageIndex,
            kind: draft.kind,
            rects: [{ x, y, w, h }],
            color,
            strokeWidth
          });
        } else {
          const id = newId();
          onCreate({
            id,
            page: pageIndex,
            kind: 'textbox',
            x,
            y,
            w,
            h,
            text: '',
            color,
            fontSize: Math.max(8, Math.round(strokeWidth * 6))
          });
          setEditingTextboxId(id);
        }
      }
    }
    setDraft(null);
  };

  /** Apply a viewport-space translation to any annotation and commit via onUpdate. */
  function commitMove(annot: Annot, dxVp: number, dyVp: number): void {
    if (Math.abs(dxVp) < 1 && Math.abs(dyVp) < 1) return; // treat as click
    // Convert viewport-space delta to PDF-space delta.
    const [x0p, y0p] = viewport.convertToPdfPoint(0, 0);
    const [x1p, y1p] = viewport.convertToPdfPoint(dxVp, dyVp);
    const dx = x1p - x0p;
    const dy = y1p - y0p;
    onUpdate(annot.id, translateAnnot(annot, dx, dy));
  }

  /** Resize a rect-shaped annotation given the active handle + current pointer. */
  function commitResize(
    annot: Annot,
    state: ResizeState,
    live: { x: number; y: number }
  ): void {
    if (!isResizable(annot)) return;
    const newRect = computeResizedRect(state, live, viewport);
    if (newRect.w < 4 || newRect.h < 4) return;
    onUpdate(annot.id, newRect as Partial<Annot>);
  }

  const startMove = (id: string, vp: { x: number; y: number }, pid: number): void => {
    setInteraction({ kind: 'move', id, startVp: vp, dxVp: 0, dyVp: 0 });
    try {
      svgRef.current!.setPointerCapture(pid);
    } catch {
      // best effort
    }
  };

  const startResize = (
    annot: Annot,
    handle: HandleId,
    vp: { x: number; y: number },
    pid: number
  ): void => {
    if (!isResizable(annot)) return;
    setInteraction({
      kind: 'resize',
      id: annot.id,
      handle,
      startVp: vp,
      origPdf: { x: annot.x, y: annot.y, w: annot.w, h: annot.h }
    });
    try {
      svgRef.current!.setPointerCapture(pid);
    } catch {
      // best effort
    }
  };

  // Keyboard: delete the selected annotation
  useEffect(() => {
    const onKey = (ev: KeyboardEvent): void => {
      if ((ev.key === 'Delete' || ev.key === 'Backspace') && selectedId && tool === 'select') {
        if ((ev.target as HTMLElement)?.tagName === 'INPUT') return;
        if ((ev.target as HTMLElement)?.tagName === 'TEXTAREA') return;
        if ((ev.target as HTMLElement)?.isContentEditable) return;
        ev.preventDefault();
        onDelete(selectedId);
        onSelect(null);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [selectedId, tool, onDelete, onSelect]);

  const cursor =
    tool === 'select'
      ? 'default'
      : tool === 'note'
        ? 'copy'
        : tool === 'signature'
          ? armedSignature
            ? 'copy'
            : 'not-allowed'
          : tool === 'stamp'
            ? armedStamp
              ? 'copy'
              : 'not-allowed'
            : tool === 'image'
              ? armedImage
                ? 'copy'
                : 'not-allowed'
              : tool === 'redact'
                ? 'crosshair'
                : tool === 'freehand'
                  ? 'crosshair'
                  : 'crosshair';

  // Live transform that the selected annotation should preview during drag/resize.
  const previewById = (id: string): { dx?: number; dy?: number; rect?: { x: number; y: number; w: number; h: number } } | null => {
    if (!interaction || interaction.id !== id) return null;
    if (interaction.kind === 'move') {
      const [x0p, y0p] = viewport.convertToPdfPoint(0, 0);
      const [x1p, y1p] = viewport.convertToPdfPoint(interaction.dxVp, interaction.dyVp);
      return { dx: x1p - x0p, dy: y1p - y0p };
    }
    const live = livePointerRef.current ?? interaction.startVp;
    return { rect: computeResizedRect(interaction, live, viewport) };
  };

  return (
    <svg
      ref={svgRef}
      className="annot-layer"
      width={viewport.width}
      height={viewport.height}
      style={{
        position: 'absolute',
        inset: 0,
        pointerEvents: interactive ? 'auto' : 'none',
        cursor
      }}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
    >
      {annotations.map((a) => (
        <AnnotShape
          key={a.id}
          a={a}
          vp={viewport}
          selected={a.id === selectedId}
          isSelectTool={tool === 'select'}
          preview={previewById(a.id)}
          onSelect={() => onSelect(a.id)}
          onStartMove={(vp, pid) => startMove(a.id, vp, pid)}
          onStartResize={(h, vp, pid) => startResize(a, h, vp, pid)}
          onOpenNote={(id) => setEditingNoteId(id)}
          onOpenTextbox={(id) => setEditingTextboxId(id)}
        />
      ))}
      {draft && draft.kind === 'freehand' && (
        <polyline
          points={draft.vpPoints.map((p) => `${p.x},${p.y}`).join(' ')}
          fill="none"
          stroke={color}
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      )}
      {draft && draft.kind === 'crop' && (
        <rect
          x={Math.min(draft.x0, draft.x1)}
          y={Math.min(draft.y0, draft.y1)}
          width={Math.abs(draft.x1 - draft.x0)}
          height={Math.abs(draft.y1 - draft.y0)}
          fill="rgba(167, 139, 250, 0.15)"
          stroke="#A78BFA"
          strokeDasharray="6 4"
          strokeWidth={2}
        />
      )}
      {draft &&
        (draft.kind === 'rect' ||
          draft.kind === 'textbox' ||
          draft.kind === 'redact' ||
          draft.kind === 'highlight' ||
          draft.kind === 'underline' ||
          draft.kind === 'strikethrough') && (
          <rect
            x={Math.min(draft.x0, draft.x1)}
            y={Math.min(draft.y0, draft.y1)}
            width={Math.abs(draft.x1 - draft.x0)}
            height={Math.abs(draft.y1 - draft.y0)}
            fill={
              draft.kind === 'redact'
                ? 'rgba(0,0,0,0.6)'
                : draft.kind === 'highlight'
                  ? color
                  : 'none'
            }
            fillOpacity={
              draft.kind === 'highlight'
                ? Math.max(0.2, Math.min(0.8, 0.2 + (strokeWidth / 16) * 0.6))
                : undefined
            }
            stroke={draft.kind === 'redact' ? '#000' : color}
            strokeDasharray="4 3"
            strokeWidth={1.5}
          />
        )}

      {/* Inline editors as <foreignObject> overlays */}
      {editingNoteId && (
        <NoteEditor
          annot={annotations.find((a) => a.id === editingNoteId) as NoteAnnot | undefined}
          vp={viewport}
          onChange={(text) => onUpdate(editingNoteId, { text } as Partial<Annot>)}
          onClose={() => setEditingNoteId(null)}
        />
      )}
      {editingTextboxId && (
        <TextboxEditor
          annot={annotations.find((a) => a.id === editingTextboxId)}
          vp={viewport}
          onChange={(text) => onUpdate(editingTextboxId, { text } as Partial<Annot>)}
          onClose={() => setEditingTextboxId(null)}
        />
      )}
    </svg>
  );
}

/** Returns a Partial<Annot> patch that translates the annotation by (dx, dy) in PDF points. */
function translateAnnot(a: Annot, dx: number, dy: number): Partial<Annot> {
  if (
    a.kind === 'rect' ||
    a.kind === 'textbox' ||
    a.kind === 'signature' ||
    a.kind === 'redact' ||
    a.kind === 'stamp' ||
    a.kind === 'image' ||
    a.kind === 'note'
  ) {
    return { x: a.x + dx, y: a.y + dy } as Partial<Annot>;
  }
  if (a.kind === 'freehand') {
    return { points: a.points.map((p) => ({ x: p.x + dx, y: p.y + dy })) } as Partial<Annot>;
  }
  if (a.kind === 'highlight' || a.kind === 'underline' || a.kind === 'strikethrough') {
    return {
      rects: a.rects.map((r) => ({ x: r.x + dx, y: r.y + dy, w: r.w, h: r.h }))
    } as Partial<Annot>;
  }
  return {};
}

/** Compute the resized PDF-space rect given a resize gesture and live pointer (vp px). */
function computeResizedRect(
  state: ResizeState,
  live: { x: number; y: number },
  vp: Viewport
): { x: number; y: number; w: number; h: number } {
  // Convert the original PDF rect to viewport-space.
  const [vx1, vy1] = vp.convertToViewportPoint(state.origPdf.x, state.origPdf.y);
  const [vx2, vy2] = vp.convertToViewportPoint(
    state.origPdf.x + state.origPdf.w,
    state.origPdf.y + state.origPdf.h
  );
  let left = Math.min(vx1, vx2);
  let right = Math.max(vx1, vx2);
  let top = Math.min(vy1, vy2);
  let bottom = Math.max(vy1, vy2);

  const h = state.handle;
  if (h === 'w' || h === 'nw' || h === 'sw') left = live.x;
  if (h === 'e' || h === 'ne' || h === 'se') right = live.x;
  if (h === 'n' || h === 'nw' || h === 'ne') top = live.y;
  if (h === 's' || h === 'sw' || h === 'se') bottom = live.y;

  // Normalize (allow flipping during drag).
  const nl = Math.min(left, right);
  const nr = Math.max(left, right);
  const nt = Math.min(top, bottom);
  const nb = Math.max(top, bottom);

  // Convert back to PDF space (note y axis flip).
  const [px1, py1] = vp.convertToPdfPoint(nl, nt);
  const [px2, py2] = vp.convertToPdfPoint(nr, nb);
  const x = Math.min(px1, px2);
  const y = Math.min(py1, py2);
  const w = Math.abs(px2 - px1);
  const ht = Math.abs(py2 - py1);
  return { x, y, w, h: ht };
}

function formatStampDateLocal(d: Date = new Date()): string {
  // Retained for backwards compatibility; new stamps use userInfo.formatStampDateTime.
  void d;
  return '';
}
void formatStampDateLocal;

interface AnnotShapeProps {
  a: Annot;
  vp: Viewport;
  selected: boolean;
  isSelectTool: boolean;
  preview: { dx?: number; dy?: number; rect?: { x: number; y: number; w: number; h: number } } | null;
  onSelect: () => void;
  onStartMove: (vp: { x: number; y: number }, pointerId: number) => void;
  onStartResize: (handle: HandleId, vp: { x: number; y: number }, pointerId: number) => void;
  onOpenNote: (id: string) => void;
  onOpenTextbox: (id: string) => void;
}

function AnnotShape({
  a,
  vp,
  selected,
  isSelectTool,
  preview,
  onSelect,
  onStartMove,
  onStartResize,
  onOpenNote,
  onOpenTextbox
}: AnnotShapeProps): JSX.Element {
  // Build a hit handler that selects + starts a drag in one gesture.
  const hitHandler = (e: React.PointerEvent<SVGElement>): void => {
    if (!isSelectTool) return;
    e.stopPropagation();
    const root = (e.currentTarget.ownerSVGElement ?? e.currentTarget) as SVGSVGElement;
    const rect = root.getBoundingClientRect();
    const vpPt = { x: e.clientX - rect.left, y: e.clientY - rect.top };
    onSelect();
    onStartMove(vpPt, e.pointerId);
  };

  // Common selection visual + interactive props for hit-test shapes.
  // pointerEvents:'all' makes fill="none" shapes selectable everywhere
  // (not just on the stroke); this is THE key fix for the select-tool bug.
  const hitProps = isSelectTool
    ? {
        onPointerDown: hitHandler,
        style: { cursor: selected ? 'move' : 'pointer' as const, pointerEvents: 'all' as const }
      }
    : { style: { pointerEvents: 'none' as const } };

  // Effective rect used for rendering + handle placement, accounting for
  // an in-progress drag/resize preview.
  let effRect: { x: number; y: number; w: number; h: number } | null = null;
  if (isResizable(a)) {
    effRect = { x: a.x, y: a.y, w: a.w, h: a.h };
    if (preview?.rect) effRect = preview.rect;
    else if (preview?.dx !== undefined) {
      effRect = { x: a.x + (preview.dx ?? 0), y: a.y + (preview.dy ?? 0), w: a.w, h: a.h };
    }
  }

  // Live translation (for non-resizable kinds during a drag preview).
  const tx = preview?.dx ?? 0;
  const ty = preview?.dy ?? 0;

  const outline = selected ? { stroke: '#A78BFA', strokeDasharray: '3 2', strokeWidth: 1 } : {};

  if (a.kind === 'highlight') {
    const op = Math.max(0.2, Math.min(0.8, 0.2 + ((a.strokeWidth ?? 2) / 16) * 0.6));
    return (
      <g>
        {a.rects.map((r, i) => {
          const sv = pdfRectToSvg(vp, { x: r.x + tx, y: r.y + ty, w: r.w, h: r.h });
          return (
            <rect
              key={i}
              {...hitProps}
              x={sv.x}
              y={sv.y}
              width={sv.w}
              height={sv.h}
              fill={a.color}
              opacity={op}
              {...(selected && i === 0 ? outline : {})}
            />
          );
        })}
      </g>
    );
  }

  if (a.kind === 'underline' || a.kind === 'strikethrough') {
    const lw = a.strokeWidth ?? 1.5;
    return (
      <g>
        {a.rects.map((r, i) => {
          const sv = pdfRectToSvg(vp, { x: r.x + tx, y: r.y + ty, w: r.w, h: r.h });
          const y = a.kind === 'underline' ? sv.y + sv.h : sv.y + sv.h / 2;
          return (
            <g key={i}>
              {/* Invisible hit-target so the entire run is clickable, not just the thin line. */}
              {isSelectTool && (
                <rect
                  {...hitProps}
                  x={sv.x}
                  y={sv.y}
                  width={sv.w}
                  height={sv.h}
                  fill="transparent"
                />
              )}
              <line
                x1={sv.x}
                x2={sv.x + sv.w}
                y1={y}
                y2={y}
                stroke={a.color}
                strokeWidth={lw}
                style={{ pointerEvents: 'none' }}
                {...(selected && i === 0 ? outline : {})}
              />
            </g>
          );
        })}
      </g>
    );
  }

  if (a.kind === 'note') {
    const [vx, vy] = pdfToVp(vp, a.x + tx, a.y + ty);
    const size = 18;
    return (
      <g
        onDoubleClick={(e) => {
          e.stopPropagation();
          onOpenNote(a.id);
        }}
      >
        <rect
          {...hitProps}
          x={vx - size / 2}
          y={vy - size}
          width={size}
          height={size}
          fill={a.color}
          stroke={selected ? '#A78BFA' : '#222'}
          strokeWidth={selected ? 1.5 : 0.5}
          rx={2}
        />
        <text
          x={vx}
          y={vy - size / 2 + 4}
          textAnchor="middle"
          fontSize={11}
          fill="#222"
          style={{ pointerEvents: 'none' }}
        >
          ✎
        </text>
      </g>
    );
  }

  if (a.kind === 'freehand') {
    if (a.points.length < 2) return <g />;
    const pts = a.points.map((p) => {
      const [x, y] = pdfToVp(vp, p.x + tx, p.y + ty);
      return `${x},${y}`;
    });
    return (
      <g>
        {/* Invisible thick stroke for easier hit-testing in select mode. */}
        {isSelectTool && (
          <polyline
            {...hitProps}
            points={pts.join(' ')}
            fill="none"
            stroke="transparent"
            strokeWidth={Math.max(12, (a.width ?? 1.5) + 10)}
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        )}
        <polyline
          points={pts.join(' ')}
          fill="none"
          stroke={a.color}
          strokeWidth={a.width ?? 1.5}
          strokeLinecap="round"
          strokeLinejoin="round"
          style={{ pointerEvents: 'none' }}
          {...(selected ? outline : {})}
        />
      </g>
    );
  }

  if (a.kind === 'rect') {
    const sv = pdfRectToSvg(vp, effRect ?? a);
    return (
      <g>
        <rect
          {...hitProps}
          x={sv.x}
          y={sv.y}
          width={sv.w}
          height={sv.h}
          fill="transparent"
          stroke={a.color}
          strokeWidth={a.strokeWidth ?? 1.5}
          {...(selected ? outline : {})}
        />
        {selected && isSelectTool && effRect && (
          <ResizeHandles rectVp={sv} onStartResize={onStartResize} />
        )}
      </g>
    );
  }

  if (a.kind === 'textbox') {
    const sv = pdfRectToSvg(vp, effRect ?? a);
    const [, y0] = pdfToVp(vp, 0, 0);
    const [, y1] = pdfToVp(vp, 0, a.fontSize);
    const fs = Math.abs(y1 - y0);
    return (
      <g
        onDoubleClick={(e) => {
          e.stopPropagation();
          onOpenTextbox(a.id);
        }}
      >
        <rect
          {...hitProps}
          x={sv.x}
          y={sv.y}
          width={sv.w}
          height={sv.h}
          fill="transparent"
          stroke={selected ? '#A78BFA' : 'rgba(167,139,250,0.4)'}
          strokeDasharray={selected ? '3 2' : '2 3'}
          strokeWidth={1}
        />
        <foreignObject x={sv.x + 2} y={sv.y + 2} width={Math.max(0, sv.w - 4)} height={Math.max(0, sv.h - 4)}>
          <div
            style={{
              color: a.color,
              fontSize: `${fs}px`,
              lineHeight: 1.2,
              whiteSpace: 'pre-wrap',
              wordBreak: 'break-word',
              pointerEvents: 'none'
            }}
          >
            {a.text}
          </div>
        </foreignObject>
        {selected && isSelectTool && effRect && (
          <ResizeHandles rectVp={sv} onStartResize={onStartResize} />
        )}
      </g>
    );
  }

  if (a.kind === 'signature') {
    const sv = pdfRectToSvg(vp, effRect ?? a);
    const href = signatureHref(a.pngBytes);
    return (
      <g>
        <image
          href={href}
          x={sv.x}
          y={sv.y}
          width={sv.w}
          height={sv.h}
          preserveAspectRatio="none"
          style={{ pointerEvents: 'none' }}
        />
        {/* Transparent hit overlay so the entire signature is clickable. */}
        {isSelectTool && (
          <rect
            {...hitProps}
            x={sv.x}
            y={sv.y}
            width={sv.w}
            height={sv.h}
            fill="transparent"
          />
        )}
        {selected && (
          <rect
            x={sv.x}
            y={sv.y}
            width={sv.w}
            height={sv.h}
            fill="none"
            stroke="#A78BFA"
            strokeDasharray="3 2"
            strokeWidth={1}
            style={{ pointerEvents: 'none' }}
          />
        )}
        {selected && isSelectTool && effRect && (
          <ResizeHandles rectVp={sv} onStartResize={onStartResize} />
        )}
      </g>
    );
  }

  if (a.kind === 'redact') {
    const sv = pdfRectToSvg(vp, effRect ?? a);
    return (
      <g>
        <rect
          {...hitProps}
          x={sv.x}
          y={sv.y}
          width={sv.w}
          height={sv.h}
          fill="#000"
        />
        {selected && (
          <rect
            x={sv.x}
            y={sv.y}
            width={sv.w}
            height={sv.h}
            fill="none"
            stroke="#A78BFA"
            strokeDasharray="3 2"
            strokeWidth={1}
            style={{ pointerEvents: 'none' }}
          />
        )}
        {selected && isSelectTool && effRect && (
          <ResizeHandles rectVp={sv} onStartResize={onStartResize} />
        )}
      </g>
    );
  }

  if (a.kind === 'stamp') {
    const sv = pdfRectToSvg(vp, effRect ?? a);
    return (
      <g>
        <StampShape sv={sv} a={a} hitProps={hitProps} />
        {selected && (
          <rect
            x={sv.x - 2}
            y={sv.y - 2}
            width={sv.w + 4}
            height={sv.h + 4}
            fill="none"
            stroke="#A78BFA"
            strokeDasharray="3 2"
            strokeWidth={1}
            style={{ pointerEvents: 'none' }}
          />
        )}
        {selected && isSelectTool && effRect && (
          <ResizeHandles rectVp={sv} onStartResize={onStartResize} />
        )}
      </g>
    );
  }

  if (a.kind === 'image') {
    const sv = pdfRectToSvg(vp, effRect ?? a);
    const href = imageHref(a.bytes, a.mime);
    const hasSub = !!(a.subtext && a.subtext.trim());
    // Caption overlay band hugging the image's bottom edge. White italic
    // text on a translucent dark strip so it stays legible over any image.
    const bandH = Math.max(12, Math.min(sv.h * 0.18, 18));
    const capFs = bandH * 0.66;
    return (
      <g>
        <image
          href={href}
          x={sv.x}
          y={sv.y}
          width={sv.w}
          height={sv.h}
          preserveAspectRatio="none"
          style={{ pointerEvents: 'none' }}
        />
        {hasSub && (
          <>
            <rect
              x={sv.x}
              y={sv.y + sv.h - bandH}
              width={sv.w}
              height={bandH}
              fill="rgba(0, 0, 0, 0.55)"
              style={{ pointerEvents: 'none' }}
            />
            <text
              x={sv.x + sv.w / 2}
              y={sv.y + sv.h - bandH / 2 + capFs * 0.35}
              textAnchor="middle"
              fontSize={capFs}
              fontStyle="italic"
              fontFamily="'Helvetica Neue', Helvetica, Arial, sans-serif"
              fill="#ffffff"
              style={{ pointerEvents: 'none', userSelect: 'none' }}
            >
              {a.subtext}
            </text>
          </>
        )}
        {isSelectTool && (
          <rect
            {...hitProps}
            x={sv.x}
            y={sv.y}
            width={sv.w}
            height={sv.h}
            fill="transparent"
          />
        )}
        {selected && (
          <rect
            x={sv.x}
            y={sv.y}
            width={sv.w}
            height={sv.h}
            fill="none"
            stroke="#A78BFA"
            strokeDasharray="3 2"
            strokeWidth={1}
            style={{ pointerEvents: 'none' }}
          />
        )}
        {selected && isSelectTool && effRect && (
          <ResizeHandles rectVp={sv} onStartResize={onStartResize} />
        )}
      </g>
    );
  }

  return <g />;
}

/** SVG rendering of a stamp (rect-style bordered box, or single glyph mark). */
function StampShape({
  sv,
  a,
  hitProps
}: {
  sv: { x: number; y: number; w: number; h: number };
  a: { label: string; subtext?: string; style: 'rect' | 'mark'; borderColor: string };
  hitProps: Record<string, unknown>;
}): JSX.Element {
  if (a.style === 'mark') {
    const size = Math.min(sv.w, sv.h);
    return (
      <g>
        <rect
          {...hitProps}
          x={sv.x}
          y={sv.y}
          width={sv.w}
          height={sv.h}
          fill="transparent"
        />
        <text
          x={sv.x + sv.w / 2}
          y={sv.y + sv.h / 2 + size * 0.34}
          textAnchor="middle"
          fontSize={size * 0.95}
          fontWeight={900}
          fill={a.borderColor}
          style={{ pointerEvents: 'none', userSelect: 'none' }}
        >
          {a.label}
        </text>
      </g>
    );
  }
  const hasSub = !!(a.subtext && a.subtext.trim());
  const labelFs = hasSub ? Math.min(sv.h * 0.40, 22) : Math.min(sv.h * 0.55, 26);
  const subFs = Math.min(sv.h * 0.22, 13);
  const padX = 12;
  const padY = hasSub ? 6 : 0;
  const labelY = hasSub
    ? sv.y + padY + labelFs * 0.95
    : sv.y + sv.h / 2 + labelFs * 0.35;
  const subY = sv.y + sv.h - padY - subFs * 0.25;
  const radius = Math.min(10, sv.h * 0.22);
  const fillRgb = hexToRgbString(a.borderColor);
  return (
    <g>
      {/* Tinted fill background + rounded outer border (also the hit target). */}
      <rect
        {...hitProps}
        x={sv.x}
        y={sv.y}
        width={sv.w}
        height={sv.h}
        rx={radius}
        ry={radius}
        fill={`rgba(${fillRgb}, 0.14)`}
        stroke={a.borderColor}
        strokeWidth={1.5}
      />
      <text
        x={sv.x + padX}
        y={labelY}
        textAnchor="start"
        fontSize={labelFs}
        fontWeight={800}
        fontStyle="italic"
        fontFamily="'Helvetica Neue', Helvetica, Arial, sans-serif"
        fill={a.borderColor}
        style={{ pointerEvents: 'none', userSelect: 'none', letterSpacing: '0.5px' }}
      >
        {a.label}
      </text>
      {hasSub && (
        <text
          x={sv.x + padX}
          y={subY}
          textAnchor="start"
          fontSize={subFs}
          fontStyle="italic"
          fontFamily="'Helvetica Neue', Helvetica, Arial, sans-serif"
          fill={a.borderColor}
          style={{ pointerEvents: 'none', userSelect: 'none' }}
        >
          {a.subtext}
        </text>
      )}
    </g>
  );
}

function hexToRgbString(hex: string): string {
  const h = hex.replace('#', '');
  const full =
    h.length === 3
      ? h
          .split('')
          .map((c) => c + c)
          .join('')
      : h;
  const r = parseInt(full.slice(0, 2), 16) || 0;
  const g = parseInt(full.slice(2, 4), 16) || 0;
  const b = parseInt(full.slice(4, 6), 16) || 0;
  return `${r}, ${g}, ${b}`;
}

const HANDLE_SPECS: { id: HandleId; cursor: string; cx: (r: { x: number; y: number; w: number; h: number }) => number; cy: (r: { x: number; y: number; w: number; h: number }) => number }[] = [
  { id: 'nw', cursor: 'nwse-resize', cx: (r) => r.x,           cy: (r) => r.y },
  { id: 'n',  cursor: 'ns-resize',   cx: (r) => r.x + r.w / 2, cy: (r) => r.y },
  { id: 'ne', cursor: 'nesw-resize', cx: (r) => r.x + r.w,     cy: (r) => r.y },
  { id: 'e',  cursor: 'ew-resize',   cx: (r) => r.x + r.w,     cy: (r) => r.y + r.h / 2 },
  { id: 'se', cursor: 'nwse-resize', cx: (r) => r.x + r.w,     cy: (r) => r.y + r.h },
  { id: 's',  cursor: 'ns-resize',   cx: (r) => r.x + r.w / 2, cy: (r) => r.y + r.h },
  { id: 'sw', cursor: 'nesw-resize', cx: (r) => r.x,           cy: (r) => r.y + r.h },
  { id: 'w',  cursor: 'ew-resize',   cx: (r) => r.x,           cy: (r) => r.y + r.h / 2 }
];

function ResizeHandles({
  rectVp,
  onStartResize
}: {
  rectVp: { x: number; y: number; w: number; h: number };
  onStartResize: (handle: HandleId, vp: { x: number; y: number }, pointerId: number) => void;
}): JSX.Element {
  const s = 8; // handle size in viewport px
  return (
    <g>
      {HANDLE_SPECS.map((h) => {
        const cx = h.cx(rectVp);
        const cy = h.cy(rectVp);
        return (
          <rect
            key={h.id}
            x={cx - s / 2}
            y={cy - s / 2}
            width={s}
            height={s}
            fill="#fff"
            stroke="#A78BFA"
            strokeWidth={1}
            style={{ cursor: h.cursor, pointerEvents: 'all' }}
            onPointerDown={(e) => {
              e.stopPropagation();
              const root = (e.currentTarget.ownerSVGElement ?? e.currentTarget) as SVGSVGElement;
              const rect = root.getBoundingClientRect();
              onStartResize(
                h.id,
                { x: e.clientX - rect.left, y: e.clientY - rect.top },
                e.pointerId
              );
            }}
          />
        );
      })}
    </g>
  );
}

// Cache data: URLs per PNG byte reference so we don't rebuild huge strings each render.
const signatureHrefCache = new WeakMap<Uint8Array, string>();
function signatureHref(bytes: Uint8Array): string {
  const cached = signatureHrefCache.get(bytes);
  if (cached) return cached;
  let bin = '';
  for (let i = 0; i < bytes.byteLength; i++) bin += String.fromCharCode(bytes[i]);
  const href = `data:image/png;base64,${btoa(bin)}`;
  signatureHrefCache.set(bytes, href);
  return href;
}

const imageHrefCache = new WeakMap<Uint8Array, string>();
function imageHref(bytes: Uint8Array, mime: 'image/png' | 'image/jpeg'): string {
  const cached = imageHrefCache.get(bytes);
  if (cached) return cached;
  let bin = '';
  for (let i = 0; i < bytes.byteLength; i++) bin += String.fromCharCode(bytes[i]);
  const href = `data:${mime};base64,${btoa(bin)}`;
  imageHrefCache.set(bytes, href);
  return href;
}

function NoteEditor({
  annot,
  vp,
  onChange,
  onClose
}: {
  annot: NoteAnnot | undefined;
  vp: Viewport;
  onChange: (text: string) => void;
  onClose: () => void;
}): JSX.Element | null {
  if (!annot) return null;
  const [vx, vy] = pdfToVp(vp, annot.x, annot.y);
  return (
    <foreignObject x={vx + 12} y={vy - 70} width={220} height={120}>
      <div className="note-editor">
        <textarea
          autoFocus
          value={annot.text}
          onChange={(e) => onChange(e.target.value)}
          onBlur={onClose}
          onKeyDown={(e) => {
            if (e.key === 'Escape') {
              e.preventDefault();
              onClose();
            }
          }}
          placeholder="Note…"
        />
      </div>
    </foreignObject>
  );
}

function TextboxEditor({
  annot,
  vp,
  onChange,
  onClose
}: {
  annot: Annot | undefined;
  vp: Viewport;
  onChange: (text: string) => void;
  onClose: () => void;
}): JSX.Element | null {
  if (!annot || annot.kind !== 'textbox') return null;
  const sv = pdfRectToSvg(vp, annot);
  const [, y0] = pdfToVp(vp, 0, 0);
  const [, y1] = pdfToVp(vp, 0, annot.fontSize);
  const fs = Math.abs(y1 - y0);
  return (
    <foreignObject x={sv.x} y={sv.y} width={sv.w} height={sv.h}>
      <textarea
        autoFocus
        className="textbox-editor"
        value={annot.text}
        onChange={(e) => onChange(e.target.value)}
        onBlur={onClose}
        onKeyDown={(e) => {
          if (e.key === 'Escape') {
            e.preventDefault();
            onClose();
          }
        }}
        style={{
          width: '100%',
          height: '100%',
          fontSize: `${fs}px`,
          color: annot.color,
          background: 'rgba(255,255,255,0.05)',
          border: 'none',
          resize: 'none',
          padding: 2
        }}
      />
    </foreignObject>
  );
}
