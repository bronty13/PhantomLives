import { useEffect, useRef, useState, useCallback } from 'react';
import type { RectNode } from '../../../../shared/types';
import { formatBytes, depthColor } from '../common/format';

const api = window.purpleTree;

interface Props {
  scanId: string;
  focusId: number;
  /** Drill into a folder (dir) or act on a file (leaf). */
  onPick: (node: RectNode) => void;
}

export default function TreemapCanvas({ scanId, focusId, onPick }: Props): JSX.Element {
  const wrapRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const rectsRef = useRef<RectNode[]>([]);
  const [size, setSize] = useState({ w: 0, h: 0 });
  const [hover, setHover] = useState<{ node: RectNode; x: number; y: number } | null>(null);

  // Track container size (debounced).
  useEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    let t: ReturnType<typeof setTimeout> | null = null;
    const ro = new ResizeObserver(() => {
      if (t) clearTimeout(t);
      t = setTimeout(() => {
        const r = el.getBoundingClientRect();
        setSize({ w: Math.floor(r.width), h: Math.floor(r.height) });
      }, 120);
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const paint = useCallback((rects: RectNode[], w: number, h: number) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const dpr = window.devicePixelRatio || 1;
    canvas.width = w * dpr;
    canvas.height = h * dpr;
    canvas.style.width = `${w}px`;
    canvas.style.height = `${h}px`;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.scale(dpr, dpr);
    ctx.clearRect(0, 0, w, h);
    ctx.font = '11px -apple-system, system-ui, sans-serif';
    ctx.textBaseline = 'top';
    for (const r of rects) {
      if (r.depth === 0) continue; // the focus node is the backdrop
      ctx.fillStyle = depthColor(r.depth);
      ctx.fillRect(r.x, r.y, r.w, r.h);
      ctx.strokeStyle = 'rgba(26,11,46,0.35)';
      ctx.lineWidth = 1;
      ctx.strokeRect(r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1);
      if (r.w > 46 && r.h > 16) {
        ctx.fillStyle = r.depth <= 2 ? '#fff' : '#2e1065';
        const label = r.name;
        ctx.save();
        ctx.beginPath();
        ctx.rect(r.x + 3, r.y + 2, r.w - 6, r.h - 4);
        ctx.clip();
        ctx.fillText(label, r.x + 4, r.y + 3);
        if (r.h > 30) {
          ctx.fillStyle = r.depth <= 2 ? 'rgba(255,255,255,0.85)' : 'rgba(46,16,101,0.7)';
          ctx.fillText(formatBytes(r.size), r.x + 4, r.y + 16);
        }
        ctx.restore();
      }
    }
  }, []);

  // Fetch + paint when scan/focus/size changes.
  useEffect(() => {
    let cancelled = false;
    if (size.w <= 0 || size.h <= 0) return;
    void api.getTreemap(scanId, focusId, size.w, size.h).then((rects) => {
      if (cancelled) return;
      rectsRef.current = rects;
      paint(rects, size.w, size.h);
    });
    return () => {
      cancelled = true;
    };
  }, [scanId, focusId, size, paint]);

  const hitTest = (x: number, y: number): RectNode | null => {
    let best: RectNode | null = null;
    for (const r of rectsRef.current) {
      if (r.depth === 0) continue;
      if (x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h) {
        if (!best || r.depth > best.depth) best = r;
      }
    }
    return best;
  };

  const onClick = (e: React.MouseEvent): void => {
    const rect = canvasRef.current!.getBoundingClientRect();
    const node = hitTest(e.clientX - rect.left, e.clientY - rect.top);
    if (node) onPick(node);
  };

  const onMove = (e: React.MouseEvent): void => {
    const rect = canvasRef.current!.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    const node = hitTest(x, y);
    setHover(node ? { node, x, y } : null);
  };

  return (
    <div className="treemap-wrap" ref={wrapRef}>
      <canvas
        ref={canvasRef}
        onClick={onClick}
        onMouseMove={onMove}
        onMouseLeave={() => setHover(null)}
      />
      {hover && (
        <div className="treemap-tip" style={{ left: hover.x + 12, top: hover.y + 12 }}>
          <strong>{hover.node.name}</strong>
          <br />
          {formatBytes(hover.node.size)}
          {hover.node.isDir ? ' · folder (click to open)' : ' · file'}
        </div>
      )}
    </div>
  );
}
