import {
  useEffect,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent
} from 'react';

interface Props {
  open: boolean;
  onCancel: () => void;
  onConfirm: (pngBytes: Uint8Array, width: number, height: number) => void;
}

type Mode = 'type' | 'draw';

const SIG_FONTS = [
  { label: 'Cursive', css: 'italic 700 64px "Snell Roundhand", "Brush Script MT", cursive' },
  { label: 'Italic Serif', css: 'italic 700 64px "Georgia", "Times New Roman", serif' },
  { label: 'Sans', css: '700 56px "Helvetica Neue", Arial, sans-serif' },
  { label: 'Mono', css: '600 56px "Menlo", "Courier New", monospace' }
];

const CANVAS_W = 600;
const CANVAS_H = 180;

export default function SignatureModal({ open, onCancel, onConfirm }: Props): JSX.Element | null {
  const [mode, setMode] = useState<Mode>('type');
  const [typedName, setTypedName] = useState('');
  const [fontIdx, setFontIdx] = useState(0);
  const typeCanvas = useRef<HTMLCanvasElement>(null);
  const drawCanvas = useRef<HTMLCanvasElement>(null);
  const drawingRef = useRef(false);
  const lastPtRef = useRef<{ x: number; y: number } | null>(null);
  const [drawDirty, setDrawDirty] = useState(false);

  // Render typed signature to its canvas whenever inputs change.
  useEffect(() => {
    if (!open || mode !== 'type') return;
    const c = typeCanvas.current;
    if (!c) return;
    const ctx = c.getContext('2d')!;
    ctx.clearRect(0, 0, c.width, c.height);
    ctx.fillStyle = '#0e0a1f';
    ctx.textBaseline = 'middle';
    ctx.font = SIG_FONTS[fontIdx].css;
    const label = typedName || 'Your Name';
    ctx.fillText(label, 20, c.height / 2);
  }, [open, mode, typedName, fontIdx]);

  // Reset state when reopened.
  useEffect(() => {
    if (open) {
      setMode('type');
      setTypedName('');
      setDrawDirty(false);
      const d = drawCanvas.current;
      if (d) d.getContext('2d')!.clearRect(0, 0, d.width, d.height);
    }
  }, [open]);

  if (!open) return null;

  const onDrawPointerDown = (e: ReactPointerEvent<HTMLCanvasElement>): void => {
    const c = drawCanvas.current!;
    c.setPointerCapture(e.pointerId);
    drawingRef.current = true;
    const rect = c.getBoundingClientRect();
    lastPtRef.current = {
      x: ((e.clientX - rect.left) / rect.width) * c.width,
      y: ((e.clientY - rect.top) / rect.height) * c.height
    };
  };
  const onDrawPointerMove = (e: ReactPointerEvent<HTMLCanvasElement>): void => {
    if (!drawingRef.current) return;
    const c = drawCanvas.current!;
    const rect = c.getBoundingClientRect();
    const x = ((e.clientX - rect.left) / rect.width) * c.width;
    const y = ((e.clientY - rect.top) / rect.height) * c.height;
    const ctx = c.getContext('2d')!;
    ctx.strokeStyle = '#0e0a1f';
    ctx.lineWidth = 3;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.beginPath();
    if (lastPtRef.current) ctx.moveTo(lastPtRef.current.x, lastPtRef.current.y);
    else ctx.moveTo(x, y);
    ctx.lineTo(x, y);
    ctx.stroke();
    lastPtRef.current = { x, y };
    setDrawDirty(true);
  };
  const onDrawPointerUp = (e: ReactPointerEvent<HTMLCanvasElement>): void => {
    drawingRef.current = false;
    lastPtRef.current = null;
    try {
      drawCanvas.current?.releasePointerCapture(e.pointerId);
    } catch {
      // ignore
    }
  };
  const clearDraw = (): void => {
    const d = drawCanvas.current;
    if (!d) return;
    d.getContext('2d')!.clearRect(0, 0, d.width, d.height);
    setDrawDirty(false);
  };

  const handleConfirm = async (): Promise<void> => {
    const src = mode === 'type' ? typeCanvas.current : drawCanvas.current;
    if (!src) return;
    const trimmed = trimCanvas(src);
    if (!trimmed) return;
    const blob = await new Promise<Blob | null>((resolve) =>
      trimmed.canvas.toBlob((b) => resolve(b), 'image/png')
    );
    if (!blob) return;
    const bytes = new Uint8Array(await blob.arrayBuffer());
    onConfirm(bytes, trimmed.canvas.width, trimmed.canvas.height);
  };

  const canConfirm = mode === 'type' ? typedName.trim().length > 0 : drawDirty;

  return (
    <div className="modal-backdrop" onClick={onCancel}>
      <div className="modal sig-modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-head">
          <h3>Create signature</h3>
          <button className="modal-close" onClick={onCancel} aria-label="Close">
            ×
          </button>
        </div>

        <div className="sig-tabs">
          <button
            className={mode === 'type' ? 'active' : ''}
            onClick={() => setMode('type')}
            type="button"
          >
            Type
          </button>
          <button
            className={mode === 'draw' ? 'active' : ''}
            onClick={() => setMode('draw')}
            type="button"
          >
            Draw
          </button>
        </div>

        {mode === 'type' && (
          <div className="sig-body">
            <input
              type="text"
              className="sig-name-input"
              placeholder="Your name"
              value={typedName}
              onChange={(e) => setTypedName(e.target.value)}
              autoFocus
            />
            <div className="sig-font-row">
              {SIG_FONTS.map((f, i) => (
                <button
                  key={f.label}
                  type="button"
                  className={`sig-font-btn${i === fontIdx ? ' active' : ''}`}
                  onClick={() => setFontIdx(i)}
                  style={{ font: f.css.replace(/\d+px/, '18px') }}
                >
                  {typedName || f.label}
                </button>
              ))}
            </div>
            <canvas
              ref={typeCanvas}
              width={CANVAS_W}
              height={CANVAS_H}
              className="sig-canvas"
            />
          </div>
        )}

        {mode === 'draw' && (
          <div className="sig-body">
            <p className="sig-hint">Draw your signature with your trackpad, mouse, or stylus.</p>
            <canvas
              ref={drawCanvas}
              width={CANVAS_W}
              height={CANVAS_H}
              className="sig-canvas sig-canvas-draw"
              onPointerDown={onDrawPointerDown}
              onPointerMove={onDrawPointerMove}
              onPointerUp={onDrawPointerUp}
              onPointerCancel={onDrawPointerUp}
            />
            <div className="sig-clear">
              <button type="button" onClick={clearDraw}>
                Clear
              </button>
            </div>
          </div>
        )}

        <div className="modal-actions">
          <button type="button" onClick={onCancel}>
            Cancel
          </button>
          <button
            type="button"
            className="primary"
            disabled={!canConfirm}
            onClick={() => void handleConfirm()}
          >
            Create
          </button>
        </div>
      </div>
    </div>
  );
}

function trimCanvas(src: HTMLCanvasElement): { canvas: HTMLCanvasElement } | null {
  const ctx = src.getContext('2d');
  if (!ctx) return null;
  const { width, height } = src;
  const data = ctx.getImageData(0, 0, width, height).data;
  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const a = data[(y * width + x) * 4 + 3];
      if (a > 8) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return null;
  const pad = 6;
  const x = Math.max(0, minX - pad);
  const y = Math.max(0, minY - pad);
  const w = Math.min(width - x, maxX - minX + 1 + pad * 2);
  const h = Math.min(height - y, maxY - minY + 1 + pad * 2);
  const out = document.createElement('canvas');
  out.width = w;
  out.height = h;
  out.getContext('2d')!.drawImage(src, x, y, w, h, 0, 0, w, h);
  return { canvas: out };
}
