import { useCallback, useEffect, useRef } from 'react';
import type { BrandColors, WheelChoice } from '../shared/model';
import {
  easeOutCubic,
  landedIndex,
  pickWinner,
  sectorCrossings,
  sectorStep,
  TAU,
  targetAngle,
} from './spinMath';
import { playChime, playTick, unlockAudio } from './sound';

const SIZE = 460; // logical drawing size; CSS scales it down on small screens.

function hexLuminance(hex: string): number {
  const m = /^#?([0-9a-f]{6})$/i.exec((hex ?? '').trim());
  if (!m) return 0.5;
  const n = parseInt(m[1], 16);
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((c) => c / 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** Pick a legible text color (near-white or near-black) for a given sector fill. */
function readableText(bg: string): string {
  return hexLuminance(bg) > 0.55 ? '#1a1a1a' : '#ffffff';
}

interface FittedLabel {
  text: string;
  fontSize: number;
}

/**
 * Shrink the font until the label fits the available radial run; only truncate (with
 * an ellipsis) as a last resort once we hit the minimum readable size. Returns the
 * text + font size to draw.
 */
function fitLabel(
  ctx: CanvasRenderingContext2D,
  raw: string,
  family: string,
  maxFont: number,
  minFont: number,
  availLen: number,
): FittedLabel {
  let fontSize = maxFont;
  ctx.font = `700 ${fontSize}px ${family}`;
  while (fontSize > minFont && ctx.measureText(raw).width > availLen) {
    fontSize -= 0.5;
    ctx.font = `700 ${fontSize}px ${family}`;
  }
  let text = raw;
  if (ctx.measureText(text).width > availLen) {
    while (text.length > 1 && ctx.measureText(`${text}…`).width > availLen) {
      text = text.slice(0, -1);
    }
    text = `${text.trimEnd()}…`;
  }
  return { text, fontSize };
}

export function SpinWheel({
  choices,
  colors,
  fontFamily,
  soundOn,
  canSpin,
  spinSeconds,
  onResult,
  onSpinStart,
}: {
  choices: WheelChoice[];
  colors: BrandColors;
  fontFamily: string;
  soundOn: boolean;
  canSpin: boolean;
  spinSeconds: number;
  onResult: (index: number) => void;
  onSpinStart?: () => void;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const rotationRef = useRef(0);
  const animatingRef = useRef(false);
  const soundOnRef = useRef(soundOn);
  // Cache fitted labels so we don't re-measure every animation frame.
  const layoutRef = useRef<{ sig: string; items: FittedLabel[] }>({ sig: '', items: [] });

  useEffect(() => {
    soundOnRef.current = soundOn;
  }, [soundOn]);

  const draw = useCallback(
    (rotation: number) => {
      const canvas = canvasRef.current;
      if (!canvas) return;
      const ctx = canvas.getContext('2d');
      if (!ctx) return;
      const n = choices.length;
      const step = sectorStep(n);
      const c = SIZE / 2;
      const R = c - 8;

      const palette = [colors.primary, colors.secondary];
      const hub = Math.max(14, R * 0.11);
      // Upper font bound scales down with sector count so labels don't overlap
      // vertically; fitLabel then shrinks each label further to fit its radial run.
      const maxFont = Math.max(11, Math.min(26, 300 / n + 10));
      const minFont = 7;
      const availLen = R - 14 - hub - 4;

      // Recompute fitted labels only when the text/size/font actually change.
      const sig = `${n}|${Math.round(R)}|${fontFamily}|${choices.map((c) => c.text).join('')}`;
      if (layoutRef.current.sig !== sig) {
        layoutRef.current = {
          sig,
          items: choices.map((c, i) =>
            fitLabel(ctx, c.text || `Option ${i + 1}`, fontFamily, maxFont, minFont, availLen),
          ),
        };
      }
      const layout = layoutRef.current.items;

      ctx.clearRect(0, 0, SIZE, SIZE);
      for (let i = 0; i < n; i++) {
        const startA = -Math.PI / 2 + rotation + i * step;
        const endA = startA + step;
        // Avoid same color meeting at the wrap when n is odd.
        const fill = n % 2 === 1 && i === n - 1 ? colors.accent : palette[i % 2];
        ctx.beginPath();
        ctx.moveTo(c, c);
        ctx.arc(c, c, R, startA, endA);
        ctx.closePath();
        ctx.fillStyle = fill;
        ctx.fill();

        // Label, drawn along the sector's radius.
        ctx.save();
        ctx.translate(c, c);
        ctx.rotate(startA + step / 2);
        ctx.textAlign = 'right';
        ctx.textBaseline = 'middle';
        const fit = layout[i] ?? { text: choices[i].text, fontSize: maxFont };
        ctx.font = `700 ${fit.fontSize}px ${fontFamily}`;
        const textColor = readableText(fill);
        // Subtle contrasting outline so labels stay legible on any brand color.
        ctx.lineJoin = 'round';
        ctx.lineWidth = Math.max(2, fit.fontSize * 0.16);
        ctx.strokeStyle = textColor === '#ffffff' ? 'rgba(0,0,0,0.35)' : 'rgba(255,255,255,0.55)';
        ctx.strokeText(fit.text, R - 14, 0);
        ctx.fillStyle = textColor;
        ctx.fillText(fit.text, R - 14, 0);
        ctx.restore();
      }

      // Rim + center hub.
      ctx.beginPath();
      ctx.arc(c, c, R, 0, TAU);
      ctx.lineWidth = 4;
      ctx.strokeStyle = colors.text;
      ctx.globalAlpha = 0.15;
      ctx.stroke();
      ctx.globalAlpha = 1;
      ctx.beginPath();
      ctx.arc(c, c, hub, 0, TAU);
      ctx.fillStyle = colors.bg;
      ctx.fill();
      ctx.lineWidth = 3;
      ctx.strokeStyle = colors.accent;
      ctx.stroke();
    },
    [choices, colors, fontFamily],
  );

  // Size the canvas for the device pixel ratio and (re)draw on changes.
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const dpr = Math.min(3, window.devicePixelRatio || 1);
    canvas.width = SIZE * dpr;
    canvas.height = SIZE * dpr;
    const ctx = canvas.getContext('2d');
    if (ctx) ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    draw(rotationRef.current);
  }, [draw]);

  const finish = useCallback(
    (winner: number) => {
      if (soundOnRef.current) playChime();
      onResult(winner);
    },
    [onResult],
  );

  const spin = useCallback(() => {
    if (!canSpin || animatingRef.current) return;
    if (soundOnRef.current) unlockAudio();
    onSpinStart?.();

    const n = choices.length;
    const winner = pickWinner(choices, Math.random);
    const reduced =
      typeof window.matchMedia === 'function' &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    const secs = Math.min(30, Math.max(1, spinSeconds || 6));
    const base = targetAngle(winner, n, 0);
    const cur = rotationRef.current;
    const curMod = ((cur % TAU) + TAU) % TAU;
    // More turns for a longer spin so the wheel keeps a lively pace, not a crawl.
    const turns = Math.max(4, Math.round(secs * 1.4)) + Math.floor(Math.random() * 3);
    const delta = (((base - curMod) % TAU) + TAU) % TAU + turns * TAU;
    const final = cur + delta;

    if (reduced) {
      rotationRef.current = final;
      draw(final);
      finish(winner);
      return;
    }

    animatingRef.current = true;
    const duration = secs * 1000;
    const start = performance.now();
    let prev = cur;

    const frame = (now: number) => {
      const t = Math.min(1, (now - start) / duration);
      const rot = cur + delta * easeOutCubic(t);
      if (soundOnRef.current && sectorCrossings(prev, rot, n) > 0) playTick(1 - t);
      prev = rot;
      rotationRef.current = rot;
      draw(rot);
      if (t < 1) {
        requestAnimationFrame(frame);
      } else {
        rotationRef.current = final;
        draw(final);
        animatingRef.current = false;
        finish(landedIndex(final, n));
      }
    };
    requestAnimationFrame(frame);
  }, [canSpin, choices, draw, finish, onSpinStart, spinSeconds]);

  return (
    <div className="wheel-stage">
      <div className="wheel-pointer" aria-hidden />
      <canvas ref={canvasRef} className="wheel-canvas" role="img" aria-label="Prize wheel" />
      <button className="btn spin-btn" onClick={spin} disabled={!canSpin}>
        {canSpin ? 'SPIN' : 'No spins left'}
      </button>
    </div>
  );
}
