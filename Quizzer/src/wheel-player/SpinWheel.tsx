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

function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  if (max <= 1) return '…';
  return `${text.slice(0, max - 1).trimEnd()}…`;
}

export function SpinWheel({
  choices,
  colors,
  fontFamily,
  soundOn,
  canSpin,
  onResult,
  onSpinStart,
}: {
  choices: WheelChoice[];
  colors: BrandColors;
  fontFamily: string;
  soundOn: boolean;
  canSpin: boolean;
  onResult: (index: number) => void;
  onSpinStart?: () => void;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const rotationRef = useRef(0);
  const animatingRef = useRef(false);
  const soundOnRef = useRef(soundOn);

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
      // Font scales down gracefully with sector count but stays readable even at 30.
      const fontSize = Math.max(11, Math.min(24, 300 / n + 9));
      // Labels are drawn along the radius from the rim inward, so the available run
      // is (rim → hub). A bigger wheel + this budget fits noticeably longer text.
      const maxChars = Math.max(8, Math.floor((R - hub - 18) / (fontSize * 0.54)));

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
        ctx.font = `700 ${fontSize}px ${fontFamily}`;
        const textColor = readableText(fill);
        const label = truncate(choices[i].text || `Option ${i + 1}`, maxChars);
        // Subtle contrasting outline so labels stay legible on any brand color.
        ctx.lineJoin = 'round';
        ctx.lineWidth = Math.max(2, fontSize * 0.16);
        ctx.strokeStyle = textColor === '#ffffff' ? 'rgba(0,0,0,0.35)' : 'rgba(255,255,255,0.55)';
        ctx.strokeText(label, R - 14, 0);
        ctx.fillStyle = textColor;
        ctx.fillText(label, R - 14, 0);
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

    const base = targetAngle(winner, n, 0);
    const cur = rotationRef.current;
    const curMod = ((cur % TAU) + TAU) % TAU;
    const turns = 5 + Math.floor(Math.random() * 3); // 5..7 full turns
    const delta = (((base - curMod) % TAU) + TAU) % TAU + turns * TAU;
    const final = cur + delta;

    if (reduced) {
      rotationRef.current = final;
      draw(final);
      finish(winner);
      return;
    }

    animatingRef.current = true;
    const duration = 4200 + Math.random() * 1400;
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
  }, [canSpin, choices, draw, finish, onSpinStart]);

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
