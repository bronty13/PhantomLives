import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react';
import type {
  Annot,
  NoteAnnot,
  PdfPoint,
  SignatureAnnot,
  RedactAnnot,
  Tool
} from './types';
import { newId } from './types';

interface Viewport {
  width: number;
  height: number;
  convertToViewportPoint: (x: number, y: number) => number[];
  convertToPdfPoint: (x: number, y: number) => number[];
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

export default function AnnotationLayer({
  pageIndex,
  viewport,
  annotations,
  tool,
  color,
  strokeWidth,
  armedSignature,
  signaturePlaceWidthPt = 140,
  onCreate,
  onUpdate,
  onDelete,
  selectedId,
  onSelect
}: Props): JSX.Element {
  const svgRef = useRef<SVGSVGElement>(null);
  const [draft, setDraft] = useState<Draft>(null);
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
    (tool === 'signature' && !!armedSignature);

  const localPoint = (e: ReactPointerEvent<SVGSVGElement>): { x: number; y: number } => {
    const rect = svgRef.current!.getBoundingClientRect();
    return { x: e.clientX - rect.left, y: e.clientY - rect.top };
  };

  const onPointerDown = (e: ReactPointerEvent<SVGSVGElement>): void => {
    if (tool === 'select') {
      // Click on empty area clears selection
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
    if (!draft) return;
    const p = localPoint(e);
    if (draft.kind === 'freehand') {
      setDraft({ kind: 'freehand', vpPoints: [...draft.vpPoints, p] });
    } else {
      setDraft({ ...draft, x1: p.x, y1: p.y });
    }
  };

  const onPointerUp = (e: ReactPointerEvent<SVGSVGElement>): void => {
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

  // Keyboard: delete the selected annotation
  useEffect(() => {
    const onKey = (ev: KeyboardEvent): void => {
      if ((ev.key === 'Delete' || ev.key === 'Backspace') && selectedId && tool === 'select') {
        if ((ev.target as HTMLElement)?.tagName === 'INPUT') return;
        if ((ev.target as HTMLElement)?.tagName === 'TEXTAREA') return;
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
          : tool === 'redact'
            ? 'crosshair'
            : tool === 'freehand'
              ? 'crosshair'
              : 'crosshair';

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
          onSelect={() => onSelect(a.id)}
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

function AnnotShape({
  a,
  vp,
  selected,
  isSelectTool,
  onSelect,
  onOpenNote,
  onOpenTextbox
}: {
  a: Annot;
  vp: Viewport;
  selected: boolean;
  isSelectTool: boolean;
  onSelect: () => void;
  onOpenNote: (id: string) => void;
  onOpenTextbox: (id: string) => void;
}): JSX.Element {
  const selectProps = isSelectTool
    ? {
        onPointerDown: (e: React.PointerEvent) => {
          e.stopPropagation();
          onSelect();
        },
        style: { cursor: 'pointer' as const }
      }
    : { style: { pointerEvents: 'none' as const } };

  const outline = selected ? { stroke: '#A78BFA', strokeDasharray: '3 2', strokeWidth: 1 } : {};

  if (a.kind === 'highlight') {
    const op = Math.max(0.2, Math.min(0.8, 0.2 + ((a.strokeWidth ?? 2) / 16) * 0.6));
    return (
      <g {...selectProps}>
        {a.rects.map((r, i) => {
          const sv = pdfRectToSvg(vp, r);
          return (
            <rect
              key={i}
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
      <g {...selectProps}>
        {a.rects.map((r, i) => {
          const sv = pdfRectToSvg(vp, r);
          const y = a.kind === 'underline' ? sv.y + sv.h : sv.y + sv.h / 2;
          return (
            <line
              key={i}
              x1={sv.x}
              x2={sv.x + sv.w}
              y1={y}
              y2={y}
              stroke={a.color}
              strokeWidth={lw}
              {...(selected && i === 0 ? outline : {})}
            />
          );
        })}
      </g>
    );
  }

  if (a.kind === 'note') {
    const [vx, vy] = pdfToVp(vp, a.x, a.y);
    const size = 18;
    return (
      <g
        {...selectProps}
        onDoubleClick={(e) => {
          e.stopPropagation();
          onOpenNote(a.id);
        }}
      >
        <rect
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
      const [x, y] = pdfToVp(vp, p.x, p.y);
      return `${x},${y}`;
    });
    return (
      <polyline
        {...selectProps}
        points={pts.join(' ')}
        fill="none"
        stroke={a.color}
        strokeWidth={a.width ?? 1.5}
        strokeLinecap="round"
        strokeLinejoin="round"
        {...outline}
      />
    );
  }

  if (a.kind === 'rect') {
    const sv = pdfRectToSvg(vp, a);
    return (
      <rect
        {...selectProps}
        x={sv.x}
        y={sv.y}
        width={sv.w}
        height={sv.h}
        fill="none"
        stroke={a.color}
        strokeWidth={a.strokeWidth ?? 1.5}
        {...outline}
      />
    );
  }

  if (a.kind === 'textbox') {
    const sv = pdfRectToSvg(vp, a);
    // Approximate font size in viewport pixels
    const [, y0] = pdfToVp(vp, 0, 0);
    const [, y1] = pdfToVp(vp, 0, a.fontSize);
    const fs = Math.abs(y1 - y0);
    return (
      <g
        {...selectProps}
        onDoubleClick={(e) => {
          e.stopPropagation();
          onOpenTextbox(a.id);
        }}
      >
        <rect
          x={sv.x}
          y={sv.y}
          width={sv.w}
          height={sv.h}
          fill="none"
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
      </g>
    );
  }

  if (a.kind === 'signature') {
    const sv = pdfRectToSvg(vp, a);
    const href = signatureHref(a.pngBytes);
    return (
      <g {...selectProps}>
        <image href={href} x={sv.x} y={sv.y} width={sv.w} height={sv.h} preserveAspectRatio="none" />
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
          />
        )}
      </g>
    );
  }

  if (a.kind === 'redact') {
    const sv = pdfRectToSvg(vp, a);
    return (
      <g {...selectProps}>
        <rect x={sv.x} y={sv.y} width={sv.w} height={sv.h} fill="#000" />
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
          />
        )}
      </g>
    );
  }

  return <g />;
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
