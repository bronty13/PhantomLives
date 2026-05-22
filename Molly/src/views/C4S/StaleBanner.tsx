import { useMemo } from 'react';

/**
 * Tiered, cute "X days old" banner for the most recent C4S import the
 * user is currently scoped to. The cuteness is intentional — Sallie
 * imports manually, and the dashboard is the only place Molly can nudge
 * her to refresh before the snapshot drifts too far from reality.
 *
 * The font rotates per page-render (subset of the SayingsBanner fonts)
 * so it feels alive without being chaotic. Background uses the active
 * persona's gradient.
 */

interface FontChoice {
  family: string;
  weight: number;
  size: string;
  letterSpacing: string;
}

const FONTS: readonly FontChoice[] = [
  { family: 'Pacifico',           weight: 400, size: '1.55rem', letterSpacing: '0.01em' },
  { family: 'Caveat',             weight: 700, size: '1.85rem', letterSpacing: '0' },
  { family: 'Dancing Script',     weight: 700, size: '1.75rem', letterSpacing: '0' },
  { family: 'Sacramento',         weight: 400, size: '1.85rem', letterSpacing: '0.01em' },
  { family: 'Indie Flower',       weight: 400, size: '1.55rem', letterSpacing: '0' },
  { family: 'Shadows Into Light', weight: 400, size: '1.55rem', letterSpacing: '0.01em' },
  { family: 'Patrick Hand',       weight: 400, size: '1.45rem', letterSpacing: '0.01em' },
  { family: 'Kalam',              weight: 400, size: '1.35rem', letterSpacing: '0' },
];

interface TierPick {
  emoji: string;
  text: string;
}

function pickTier(daysOld: number | null): TierPick {
  if (daysOld == null) return { emoji: '🌱', text: 'No C4S data yet — drop your latest export to get started!' };
  if (daysOld <= 1) return { emoji: '🌸', text: 'Fresh from C4S — just imported!' };
  if (daysOld <= 6) return { emoji: '✨', text: `${daysOld} days old — still pretty fresh` };
  if (daysOld <= 29) return { emoji: '🌷', text: `${daysOld} days old — might be worth a re-import soon` };
  return { emoji: '🌼', text: `${daysOld} days old — time for a fresh export?` };
}

interface Props {
  /** Most recent import for the current persona scope, or null if never imported. */
  importedAt: string | null;
  /** Optional CTA — click to open the import wizard. */
  onImport?: () => void;
}

export function StaleBanner({ importedAt, onImport }: Props) {
  const daysOld = useMemo<number | null>(() => {
    if (!importedAt) return null;
    // SQLite datetime('now') is UTC seconds-precision; the trailing 'Z' is
    // missing but we want days-rounded so the parse is forgiving.
    const t = Date.parse(importedAt.replace(' ', 'T') + 'Z');
    if (Number.isNaN(t)) return null;
    const ageMs = Date.now() - t;
    return Math.max(0, Math.floor(ageMs / 86_400_000));
  }, [importedAt]);

  const tier = pickTier(daysOld);
  const font = FONTS[Math.floor(Math.random() * FONTS.length)];

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
        <div className="text-3xl select-none" aria-hidden>{tier.emoji}</div>
        <div className="flex-1 min-w-0">
          <div
            style={{
              fontFamily: `"${font.family}", "Caveat", cursive`,
              fontWeight: font.weight,
              letterSpacing: font.letterSpacing,
              fontSize: font.size,
              lineHeight: 1.2,
              color: 'rgb(var(--persona-accent))',
            }}
          >
            {tier.text}
          </div>
          <div className="text-[11px] uppercase tracking-wider opacity-50 mt-2 font-mono">
            {importedAt ? `last refresh · ${importedAt}` : 'no imports on file'}
          </div>
        </div>
        {onImport && (
          <button type="button" onClick={onImport} className="pretty-button" title="Open the C4S import wizard">
            ✨ Import C4S CSV
          </button>
        )}
      </div>
    </div>
  );
}
