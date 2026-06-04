import { useEffect, useRef, useState, useCallback } from 'react';
import type { ArcNode } from '../../../../shared/types';
import { formatBytes, depthColor } from '../common/format';

const api = window.purpleTree;
const HALF_PI = Math.PI / 2;

interface Props {
  scanId: string;
  focusId: number;
  /** Drill into a folder (dir) or act on a file (leaf). */
  onPick: (node: ArcNode) => void;
  /** Clicking the center disc navigates up one level. */
  onUp: () => void;
}

export default function SunburstCanvas({ scanId, focusId, onPick, onUp }: Props): JSX.Element {
  const wrapRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const arcsRef = useRef<ArcNode[]>([]);
  const geomRef = useRef({ cx: 0, cy: 0, maxR: 0 });
  const [size, setSize] = useState({ w: 0, h: 0 });
  const [hover, setHover] = useState<{ node: ArcNode; x: number; y: number } | null>(null);

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

  const paint = useCallback((arcs: ArcNode[], w: number, h: number) => {
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

    const cx = w / 2;
    const cy = h / 2;
    const maxR = Math.max(0, Math.min(w, h) / 2 - 8);
    geomRef.current = { cx, cy, maxR };

    for (const a of arcs) {
      const rIn = a.r0 * maxR;
      const rOut = a.r1 * maxR;
      const s = a.a0 - HALF_PI;
      const e = a.a1 - HALF_PI;
      ctx.beginPath();
      ctx.arc(cx, cy, rOut, s, e);
      ctx.arc(cx, cy, rIn, e, s, true);
      ctx.closePath();
      ctx.fillStyle = a.depth === 0 ? '#4c1d95' : depthColor(a.depth);
      ctx.fill();
      ctx.strokeStyle = 'rgba(255,255,255,0.6)';
      ctx.lineWidth = 1;
      ctx.stroke();
    }

    // Center label (focus node name, "up" affordance).
    const center = arcs.find((a) => a.depth === 0);
    if (center) {
      ctx.fillStyle = '#fff';
      ctx.font = '12px -apple-system, system-ui, sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      const label = center.name.length > 16 ? center.name.slice(0, 15) + '…' : center.name;
      ctx.fillText(label, cx, cy - 6);
      ctx.fillStyle = 'rgba(255,255,255,0.75)';
      ctx.font = '10px -apple-system, system-ui, sans-serif';
      ctx.fillText(formatBytes(center.size), cx, cy + 9);
    }
  }, []);

  useEffect(() => {
    let cancelled = false;
    if (size.w <= 0 || size.h <= 0) return;
    void api.getSunburst(scanId, focusId).then((arcs) => {
      if (cancelled) return;
      arcsRef.current = arcs;
      paint(arcs, size.w, size.h);
    });
    return () => {
      cancelled = true;
    };
  }, [scanId, focusId, size, paint]);

  const hitTest = (x: number, y: number): ArcNode | null => {
    const { cx, cy, maxR } = geomRef.current;
    const dx = x - cx;
    const dy = y - cy;
    const radius = Math.sqrt(dx * dx + dy * dy);
    if (radius > maxR) return null;
    let angle = Math.atan2(dy, dx) + HALF_PI;
    if (angle < 0) angle += 2 * Math.PI;
    for (const a of arcsRef.current) {
      if (radius >= a.r0 * maxR && radius < a.r1 * maxR && angle >= a.a0 && angle < a.a1) return a;
    }
    return null;
  };

  const onClick = (e: React.MouseEvent): void => {
    const rect = canvasRef.current!.getBoundingClientRect();
    const node = hitTest(e.clientX - rect.left, e.clientY - rect.top);
    if (!node) return;
    if (node.depth === 0) onUp();
    else onPick(node);
  };

  const onMove = (e: React.MouseEvent): void => {
    const rect = canvasRef.current!.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    const node = hitTest(x, y);
    setHover(node ? { node, x, y } : null);
  };

  return (
    <div className="treemap-wrap sunburst-wrap" ref={wrapRef}>
      <canvas ref={canvasRef} onClick={onClick} onMouseMove={onMove} onMouseLeave={() => setHover(null)} />
      {hover && (
        <div className="treemap-tip" style={{ left: hover.x + 12, top: hover.y + 12 }}>
          <strong>{hover.node.name}</strong>
          <br />
          {formatBytes(hover.node.size)}
          {hover.node.depth === 0
            ? ' · center (click to go up)'
            : hover.node.isDir
              ? ' · folder (click to open)'
              : ' · file'}
        </div>
      )}
    </div>
  );
}
