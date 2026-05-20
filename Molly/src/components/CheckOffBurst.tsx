import { useEffect, useState, type ReactNode } from 'react';

interface Props {
  fire: number;          // bump this number to trigger another burst (key)
  color?: string;        // persona color
  emoji?: string;
}

/**
 * Tiny CSS-only confetti burst, persona-tinted. Mounted once at the
 * app root; bump `fire` (use Date.now()) to launch.
 *
 * No canvas-confetti dep — keeps the bundle small and the animation
 * matches the cute/pastel theme better than the default lib palette.
 */
export function CheckOffBurst({ fire, color = '#FFC0CB', emoji = '✨' }: Props) {
  const [active, setActive] = useState(false);
  const [bits, setBits] = useState<ReactNode[]>([]);

  useEffect(() => {
    if (!fire) return;
    setActive(true);
    const N = 16;
    const items: ReactNode[] = [];
    for (let i = 0; i < N; i++) {
      const angle = (Math.PI * 2 * i) / N + Math.random() * 0.4;
      const dist = 80 + Math.random() * 70;
      const dx = Math.cos(angle) * dist;
      const dy = Math.sin(angle) * dist;
      const rot = -60 + Math.random() * 120;
      const delay = Math.random() * 40;
      const useEmoji = i % 3 === 0;
      items.push(
        <span
          key={`${fire}-${i}`}
          style={{
            position: 'absolute',
            left: '50%',
            top: '50%',
            ['--dx' as string]: `${dx}px`,
            ['--dy' as string]: `${dy}px`,
            ['--rot' as string]: `${rot}deg`,
            animation: `burst 800ms cubic-bezier(.18,.84,.4,1) ${delay}ms forwards`,
            color,
            background: useEmoji ? 'transparent' : color,
            width: useEmoji ? 'auto' : 10,
            height: useEmoji ? 'auto' : 10,
            borderRadius: useEmoji ? 0 : 999,
            fontSize: useEmoji ? 18 : 0,
            transform: 'translate(-50%, -50%)',
            pointerEvents: 'none',
            opacity: 0,
          }}
        >
          {useEmoji ? (i % 6 === 0 ? '💕' : emoji) : null}
        </span>,
      );
    }
    setBits(items);
    const t = setTimeout(() => setActive(false), 1000);
    return () => clearTimeout(t);
  }, [fire, color, emoji]);

  if (!active) return null;
  return (
    <div
      aria-hidden
      style={{
        position: 'fixed',
        inset: 0,
        display: 'grid',
        placeItems: 'center',
        pointerEvents: 'none',
        zIndex: 60,
      }}
    >
      <div style={{ position: 'relative', width: 0, height: 0 }}>{bits}</div>
      <style>{`
        @keyframes burst {
          0%   { opacity: 1; transform: translate(-50%, -50%) scale(0.5) rotate(0deg); }
          70%  { opacity: 1; }
          100% { opacity: 0; transform:
            translate(calc(-50% + var(--dx)), calc(-50% + var(--dy)))
            scale(1.05) rotate(var(--rot)); }
        }
      `}</style>
    </div>
  );
}
