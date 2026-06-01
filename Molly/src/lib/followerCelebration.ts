// Delight when Sallie logs a follower count. Composes the existing
// celebration primitives (sound + floating pill + encouragement toast),
// mirroring lib/celebration.ts — but tuned for follower growth:
//
//   * crossing the platform's follower GOAL → big fanfare + screen flash.
//   * a positive Δ → a green "+N 🎉" float, tiered by how big the jump is.
//   * flat / first-ever log → a gentle "Logged! 💖", no burst.
//   * a DECLINE → still kind: soft sound, warm toast, never red, never sad.
//   * backfilling a past date (`quiet`) → silent; growth deltas from an old
//     correction shouldn't ching.

import { pickEncouragement, type EncouragementTier } from './encouragements';
import { showEncouragement } from './encouragementToast';
import { showFloatingMoney, type CelebrationTier } from './floatingNumber';
import { playCoin, playGoalHit } from './coinSound';
import { playMilestoneFanfare } from './soundFx';
import { fmtFollowers } from './followerForecast';

const EMOJIS_BY_TIER: Record<CelebrationTier, readonly string[]> = {
  1: ['🌸'],
  2: ['💕'],
  3: ['🌸', '🌷', '✨'],
  4: ['🌸', '🌷', '✨', '💖', '🌟', '📈'],
  5: ['🌸', '🌷', '✨', '💖', '🌟', '📈', '🎉', '👑', '🚀', '💎'],
};

const TIER_TO_BANK: Record<CelebrationTier, EncouragementTier> = {
  1: 'tiny',
  2: 'small',
  3: 'medium',
  4: 'big',
  5: 'whale',
};

/** Map a positive follower jump to a celebration tier. */
export function tierForDelta(delta: number): CelebrationTier {
  if (delta < 50) return 1;
  if (delta < 200) return 2;
  if (delta < 1000) return 3;
  if (delta < 5000) return 4;
  return 5;
}

export function celebrateFollowerSave(opts: {
  platformName: string;
  delta: number | null; // null = first-ever log (no baseline)
  justHitGoal: boolean;
  goal: number;
  quiet?: boolean; // backfilling a past date — stay silent
}): void {
  const { platformName, delta, justHitGoal, goal, quiet } = opts;

  if (quiet) {
    showEncouragement('Backfilled 💖');
    return;
  }

  // Crossing the goal trumps everything.
  if (justHitGoal && goal > 0) {
    playMilestoneFanfare(100);
    showFloatingMoney({ amountDollars: 0, tier: 5, emojis: EMOJIS_BY_TIER[5], text: `🎯 ${fmtFollowers(goal)}!` });
    showEncouragement(`GOAL HIT on ${platformName}! You queen 👑✨`);
    return;
  }

  // A positive jump — green float + tiered sparkle.
  if (delta != null && delta > 0) {
    const tier = tierForDelta(delta);
    if (tier >= 3) playGoalHit();
    else playCoin();
    showFloatingMoney({ amountDollars: 0, tier, emojis: EMOJIS_BY_TIER[tier], text: `+${fmtFollowers(delta)} 🎉` });
    showEncouragement(pickEncouragement(TIER_TO_BANK[tier]));
    return;
  }

  // A dip — kind, never alarming.
  if (delta != null && delta < 0) {
    playCoin();
    showEncouragement('Logged 💖 every climb has dips — you’ve got this 🌸');
    return;
  }

  // Flat, or a first-ever log with no baseline.
  playCoin();
  showEncouragement('Logged! 💖');
}
