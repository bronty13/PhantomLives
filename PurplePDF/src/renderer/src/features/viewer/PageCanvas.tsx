import { useEffect, useRef } from 'react';
import { pdfjsLib, type PDFDocumentProxy } from './pdfjs';
import type { PdfRect, Tool } from '../annotate/types';

export interface PageViewportLike {
  width: number;
  height: number;
  scale: number;
  rotation: number;
  convertToViewportPoint: (x: number, y: number) => number[];
  convertToPdfPoint: (x: number, y: number) => number[];
}

interface Props {
  doc: PDFDocumentProxy;
  /** 1-based source page number, or null for a queued blank-insert preview. */
  pageNumber: number | null;
  zoom: number;
  rotation: 0 | 90 | 180 | 270;
  /** Additional rotation (deg, clockwise) from queued rotate ops. */
  extraRotation?: number;
  /** Crop preview overlay in PDF point coords (origin bottom-left). */
  cropOverlay?: { x: number; y: number; width: number; height: number } | null;
  highlight: { start: number; end: number } | null;
  tool: Tool;
  onViewportReady: (vp: PageViewportLike) => void;
  onCreateMarkup: (rects: PdfRect[]) => void;
}

export default function PageCanvas({
  doc,
  pageNumber,
  zoom,
  rotation,
  extraRotation = 0,
  cropOverlay,
  highlight,
  tool,
  onViewportReady,
  onCreateMarkup
}: Props): JSX.Element {
  const wrapRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const textLayerRef = useRef<HTMLDivElement>(null);
  const overlayRef = useRef<HTMLDivElement>(null);
  const viewportRef = useRef<PageViewportLike | null>(null);

  useEffect(() => {
    let cancelled = false;
    let renderTask: { cancel: () => void } | null = null;

    (async () => {
      const totalRotation = (((rotation + extraRotation) % 360) + 360) % 360;
      const canvas = canvasRef.current;
      const wrap = wrapRef.current;
      const textLayer = textLayerRef.current;
      const overlay = overlayRef.current;
      if (!canvas || !wrap || !textLayer || !overlay) return;

      // Blank-slot preview: render a white page sized to the previous page
      // (or Letter as a fallback). No text layer, no markup.
      if (pageNumber == null) {
        const baseW = 612;
        const baseH = 792;
        const swap = totalRotation === 90 || totalRotation === 270;
        const vw = (swap ? baseH : baseW) * zoom;
        const vh = (swap ? baseW : baseH) * zoom;
        const dpr = window.devicePixelRatio || 1;
        canvas.width = Math.floor(vw * dpr);
        canvas.height = Math.floor(vh * dpr);
        canvas.style.width = `${vw}px`;
        canvas.style.height = `${vh}px`;
        wrap.style.width = `${vw}px`;
        wrap.style.height = `${vh}px`;
        const ctx = canvas.getContext('2d');
        if (!ctx) return;
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(0, 0, vw, vh);
        ctx.strokeStyle = '#c8c8d8';
        ctx.lineWidth = 1;
        ctx.strokeRect(0.5, 0.5, vw - 1, vh - 1);
        ctx.fillStyle = '#9999aa';
        ctx.font = '14px sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText('(blank page — queued)', vw / 2, vh / 2);
        textLayer.innerHTML = '';
        textLayer.style.width = `${vw}px`;
        textLayer.style.height = `${vh}px`;
        overlay.style.width = `${vw}px`;
        overlay.style.height = `${vh}px`;
        overlay.innerHTML = '';
        viewportRef.current = null;
        return;
      }

      const page = await doc.getPage(pageNumber);
      if (cancelled) return;

      const viewport = page.getViewport({ scale: zoom, rotation: totalRotation });
      viewportRef.current = viewport;
      onViewportReady(viewport);

      const dpr = window.devicePixelRatio || 1;
      canvas.width = Math.floor(viewport.width * dpr);
      canvas.height = Math.floor(viewport.height * dpr);
      canvas.style.width = `${viewport.width}px`;
      canvas.style.height = `${viewport.height}px`;
      wrap.style.width = `${viewport.width}px`;
      wrap.style.height = `${viewport.height}px`;

      const ctx = canvas.getContext('2d');
      if (!ctx) return;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

      const task = page.render({ canvasContext: ctx, viewport });
      renderTask = task;
      try {
        await task.promise;
      } catch {
        return;
      }
      if (cancelled) return;

      textLayer.innerHTML = '';
      textLayer.style.width = `${viewport.width}px`;
      textLayer.style.height = `${viewport.height}px`;
      overlay.style.width = `${viewport.width}px`;
      overlay.style.height = `${viewport.height}px`;
      overlay.innerHTML = '';

      // Crop preview: dim the area OUTSIDE the crop rectangle and draw a
      // dashed border around the kept area.
      if (cropOverlay) {
        const [x1, y1] = viewport.convertToViewportPoint(cropOverlay.x, cropOverlay.y);
        const [x2, y2] = viewport.convertToViewportPoint(
          cropOverlay.x + cropOverlay.width,
          cropOverlay.y + cropOverlay.height
        );
        const left = Math.min(x1, x2);
        const top = Math.min(y1, y2);
        const w = Math.abs(x2 - x1);
        const h = Math.abs(y2 - y1);
        const mask = document.createElement('div');
        mask.className = 'crop-preview-mask';
        const box = document.createElement('div');
        box.className = 'crop-preview-box';
        box.style.left = `${left}px`;
        box.style.top = `${top}px`;
        box.style.width = `${w}px`;
        box.style.height = `${h}px`;
        const tag = document.createElement('span');
        tag.className = 'crop-preview-tag';
        tag.textContent = 'Crop on save';
        box.appendChild(tag);
        overlay.appendChild(mask);
        overlay.appendChild(box);
        mask.style.clipPath = `polygon(
          0 0, 100% 0, 100% 100%, 0 100%, 0 0,
          ${left}px ${top}px,
          ${left}px ${top + h}px,
          ${left + w}px ${top + h}px,
          ${left + w}px ${top}px,
          ${left}px ${top}px
        )`;
      }

      const textContent = await page.getTextContent();
      if (cancelled) return;

      const spans: { el: HTMLSpanElement; start: number; end: number }[] = [];
      let cursor = 0;
      for (const item of textContent.items as Array<{
        str: string;
        transform: number[];
        width: number;
        height: number;
      }>) {
        if (!item.str) continue;
        const tx = pdfjsLib.Util.transform(viewport.transform, item.transform);
        const fontHeight = Math.hypot(tx[2], tx[3]);
        const span = document.createElement('span');
        span.textContent = item.str;
        span.style.position = 'absolute';
        span.style.left = `${tx[4]}px`;
        span.style.top = `${tx[5] - fontHeight}px`;
        span.style.fontSize = `${fontHeight}px`;
        span.style.fontFamily = 'sans-serif';
        span.style.whiteSpace = 'pre';
        span.style.color = 'transparent';
        span.style.cursor = 'text';
        textLayer.appendChild(span);
        spans.push({ el: span, start: cursor, end: cursor + item.str.length });
        cursor += item.str.length;
      }

      if (highlight) {
        for (const s of spans) {
          if (s.end <= highlight.start || s.start >= highlight.end) continue;
          const localStart = Math.max(0, highlight.start - s.start);
          const localEnd = Math.min(s.end - s.start, highlight.end - s.start);
          const text = s.el.textContent ?? '';
          s.el.textContent = '';
          s.el.appendChild(document.createTextNode(text.slice(0, localStart)));
          const mark = document.createElement('mark');
          mark.className = 'find-hit';
          mark.textContent = text.slice(localStart, localEnd);
          s.el.appendChild(mark);
          s.el.appendChild(document.createTextNode(text.slice(localEnd)));
        }
      }
    })();

    return () => {
      cancelled = true;
      renderTask?.cancel();
    };
  }, [doc, pageNumber, zoom, rotation, extraRotation, cropOverlay, highlight, onViewportReady]);

  useEffect(() => {
    // intentionally empty — kept as a hook anchor for future text-snap logic
  }, [tool, onCreateMarkup]);

  return (
    <div className="page-wrap" ref={wrapRef}>
      <canvas ref={canvasRef} aria-label={pageNumber == null ? 'Blank page (queued)' : `Page ${pageNumber}`} />
      <div
        className="text-layer"
        ref={textLayerRef}
        style={{
          pointerEvents: tool === 'select' ? 'auto' : 'none'
        }}
      />
      <div className="page-overlay" ref={overlayRef} aria-hidden="true" />
    </div>
  );
}
