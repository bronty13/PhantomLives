import { useEffect, useMemo, useState } from 'react';
import { SAYINGS } from '../data/sayings';

/**
 * Cute saying displayed somewhere in the UI to encourage the creator.
 * Picks one of ~1000 hand-picked sayings + one of 10 cute fonts at
 * random on mount. The shuffle button re-rolls both.
 *
 * Two display sizes: `compact` (sidebar subtitle) and `hero` (Home
 * dashboard card). Both share the same font/saying state per component
 * instance so the user can have a different saying glowing at each
 * spot at once.
 */

// Ten cute display fonts loaded in index.html. Each one is paired with
// a font-size hint that flatters its proportions and a small inline
// style override (mostly letter-spacing) where the default reads weird.
interface FontChoice {
  family: string;
  weight: number;
  letterSpacing: string;
  sizeHero: string;
  sizeCompact: string;
}

const FONTS: readonly FontChoice[] = [
  { family: 'Pacifico',            weight: 400, letterSpacing: '0.01em', sizeHero: '1.95rem', sizeCompact: '0.95rem' },
  { family: 'Caveat',              weight: 700, letterSpacing: '0',      sizeHero: '2.30rem', sizeCompact: '1.05rem' },
  { family: 'Dancing Script',      weight: 700, letterSpacing: '0',      sizeHero: '2.15rem', sizeCompact: '1.00rem' },
  { family: 'Sacramento',          weight: 400, letterSpacing: '0.01em', sizeHero: '2.35rem', sizeCompact: '1.05rem' },
  { family: 'Indie Flower',        weight: 400, letterSpacing: '0',      sizeHero: '1.85rem', sizeCompact: '0.92rem' },
  { family: 'Shadows Into Light',  weight: 400, letterSpacing: '0.01em', sizeHero: '1.95rem', sizeCompact: '0.95rem' },
  { family: 'Patrick Hand',        weight: 400, letterSpacing: '0.01em', sizeHero: '1.75rem', sizeCompact: '0.92rem' },
  { family: 'Kalam',               weight: 400, letterSpacing: '0',      sizeHero: '1.70rem', sizeCompact: '0.90rem' },
  { family: 'Chewy',               weight: 400, letterSpacing: '0.02em', sizeHero: '1.55rem', sizeCompact: '0.88rem' },
  { family: 'Comfortaa',           weight: 600, letterSpacing: '0',      sizeHero: '1.55rem', sizeCompact: '0.88rem' },
];

function pickIndex<T>(arr: readonly T[]): number {
  return Math.floor(Math.random() * arr.length);
}

interface Props {
  variant?: 'hero' | 'compact';
  /** Bump to force a reroll from the parent (e.g. on persona switch). */
  rerollKey?: unknown;
}

export function SayingsBanner({ variant = 'hero', rerollKey }: Props) {
  const [seed, setSeed] = useState<number>(() => Date.now());

  // Reroll if parent bumps the key.
  useEffect(() => {
    setSeed(Date.now());
  }, [rerollKey]);

  const { saying, font } = useMemo(() => {
    // Use the seed to make the choice deterministic per render — re-renders
    // (e.g. persona theme swap recoloring children) shouldn't change the
    // current quote; only an actual reroll should.
    void seed;
    return {
      saying: SAYINGS[pickIndex(SAYINGS)],
      font: FONTS[pickIndex(FONTS)],
    };
  }, [seed]);

  if (variant === 'compact') {
    return (
      <button
        type="button"
        onClick={() => setSeed(Date.now())}
        title="✨ another saying"
        className="block w-full text-left transition hover:opacity-80"
        style={{
          fontFamily: `"${font.family}", "Caveat", cursive`,
          fontWeight: font.weight,
          letterSpacing: font.letterSpacing,
          fontSize: font.sizeCompact,
          lineHeight: 1.25,
          color: 'rgb(var(--persona-accent))',
        }}
      >
        “{saying}”
      </button>
    );
  }

  return (
    <div
      className="pretty-card relative overflow-hidden"
      style={{
        background:
          'linear-gradient(135deg, rgb(var(--persona-tint)) 0%, rgb(var(--persona-secondary) / 0.55) 100%)',
        border: '1px solid rgb(var(--persona-primary) / 0.45)',
      }}
    >
      <div className="flex items-start gap-3">
        <div className="text-3xl select-none" aria-hidden>💕</div>
        <div className="flex-1 min-w-0">
          <div
            style={{
              fontFamily: `"${font.family}", "Caveat", cursive`,
              fontWeight: font.weight,
              letterSpacing: font.letterSpacing,
              fontSize: font.sizeHero,
              lineHeight: 1.2,
              color: 'rgb(var(--persona-accent))',
            }}
          >
            “{saying}”
          </div>
          <div className="text-[11px] uppercase tracking-wider opacity-50 mt-2 font-mono">
            for sallie · {font.family.toLowerCase()}
          </div>
        </div>
        <button
          type="button"
          onClick={() => setSeed(Date.now())}
          className="pretty-button secondary"
          title="another saying"
        >
          ✨ another
        </button>
      </div>
    </div>
  );
}
