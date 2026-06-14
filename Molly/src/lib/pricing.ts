// Content-bundle default pricing.
//
// Sallie sets a price (dollars/cents) on every content bundle. We DEFAULT it
// from the total duration of the bundle's videos so she rarely has to think
// about it, then let her override to any positive value (or mark it Free) on
// the review page. The algorithm is configurable in Settings; only the final
// "$X.99" snap is fixed.
//
//   minutes  = totalSeconds / 60
//   rawCents = baseCents + perMinuteCents * minutes
//   dollars  = max(floorDollars, round(rawCents / 100))
//   price    = dollars * 100 - 1                      // snap to $X.99
//
// Defaults (base $5.00 + $1.00/min, floor $8) track Sallie's "typical price"
// table: 4 min → $8.99, 6 min → $10.99, 8 min → $12.99, 12 min → $16.99.

export interface PricingSettings {
  /** Flat base added before the per-minute term, in cents. Default 500 ($5.00). */
  contentPriceBaseCents: number;
  /** Added per minute of total video, in cents. Default 100 ($1.00/min). */
  contentPricePerMinuteCents: number;
  /** Lowest whole-dollar price (before the $X.99 snap), in cents. Default 800 ($8). */
  contentPriceFloorCents: number;
}

export const DEFAULT_PRICING: PricingSettings = {
  contentPriceBaseCents: 500,
  contentPricePerMinuteCents: 100,
  contentPriceFloorCents: 800,
};

/**
 * Suggested default price (in cents) for a bundle whose videos total
 * `totalSeconds`. Always lands on a whole-dollar-minus-a-penny ($X.99).
 * `totalSeconds <= 0` (no readable videos) still yields the floor price.
 */
export function computeDefaultPriceCents(totalSeconds: number, s: PricingSettings): number {
  const minutes = Math.max(0, totalSeconds) / 60;
  const rawCents = s.contentPriceBaseCents + s.contentPricePerMinuteCents * minutes;
  const floorDollars = Math.round(s.contentPriceFloorCents / 100);
  const dollars = Math.max(floorDollars, Math.round(rawCents / 100));
  return dollars * 100 - 1; // snap to $X.99
}

/** Display a cents price: `0` → "Free", `null` → "—", else "$X.XX". */
export function formatPriceCents(cents: number | null): string {
  if (cents === 0) return 'Free';
  if (cents == null) return '—';
  return `$${(cents / 100).toFixed(2)}`;
}
