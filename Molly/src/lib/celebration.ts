// Orchestrator for income-save celebrations. Single entry point
// (`celebrateIncome`) called from every income-create site (the
// Adhoc Income view and the Customer Sale editor). Composes a
// tier-keyed sound + tier-keyed encouragement toast + a floating
// "+$X" pill with emoji burst, and layers a separate milestone
// fanfare + toast when this save crosses a monthly-goal milestone.
//
// Goal-only inputs (totalBefore, totalAfter, goalDollars) drive the
// milestone check — the tier sound + toast + visual fire regardless,
// so saves still feel good even when there's no goal set or the goal
// is already smashed.

import { pickEncouragement, pickMilestoneEncouragement, type EncouragementTier } from './encouragements';
import { showEncouragement } from './encouragementToast';
import { showFloatingMoney, type CelebrationTier } from './floatingNumber';
import {
  playCashRegister,
  playCashRegisterBig,
  playCashRegisterMega,
  playCashRegisterMedium,
  playCashRegisterTiny,
  playMilestoneFanfare,
} from './soundFx';

export const MILESTONES: readonly number[] = [25, 50, 75, 100, 150, 200];

const EMOJIS_BY_TIER: Record<CelebrationTier, readonly string[]> = {
  1: ['🌸'],
  2: ['💕'],
  3: ['🌸', '🌷', '✨'],
  4: ['🌸', '🌷', '✨', '💖', '🌟', '💸'],
  5: ['🌸', '🌷', '✨', '💖', '🌟', '💸', '🎉', '👑', '🚀', '💎'],
};

export function tierForAmount(amountDollars: number): CelebrationTier {
  if (amountDollars < 10) return 1;
  if (amountDollars < 50) return 2;
  if (amountDollars < 200) return 3;
  if (amountDollars < 1000) return 4;
  return 5;
}

const TIER_TO_BANK: Record<CelebrationTier, EncouragementTier> = {
  1: 'tiny',
  2: 'small',
  3: 'medium',
  4: 'big',
  5: 'whale',
};

/**
 * Highest milestone percent (from MILESTONES) crossed in moving from
 * totalBefore → totalAfter against goalDollars. Returns `null` when no
 * milestone was crossed (including the case where goal is 0). When
 * multiple are crossed in one save (rare but possible for huge sales),
 * returns the highest — the fanfare should match the biggest moment.
 */
export function milestoneCrossed(
  totalBefore: number,
  totalAfter: number,
  goalDollars: number,
): number | null {
  if (goalDollars <= 0) return null;
  const pctBefore = (totalBefore / goalDollars) * 100;
  const pctAfter = (totalAfter / goalDollars) * 100;
  let highest: number | null = null;
  for (const m of MILESTONES) {
    if (pctBefore < m && pctAfter >= m) {
      if (highest === null || m > highest) highest = m;
    }
  }
  return highest;
}

function playForTier(tier: CelebrationTier): void {
  switch (tier) {
    case 1: playCashRegisterTiny(); break;
    case 2: playCashRegister(); break;
    case 3: playCashRegisterMedium(); break;
    case 4: playCashRegisterBig(); break;
    case 5: playCashRegisterMega(); break;
  }
}

export function celebrateIncome(opts: {
  amountDollars: number;
  totalBefore: number;
  totalAfter: number;
  goalDollars: number;
}): void {
  const { amountDollars, totalBefore, totalAfter, goalDollars } = opts;
  const tier = tierForAmount(amountDollars);

  playForTier(tier);
  showEncouragement(pickEncouragement(TIER_TO_BANK[tier]));
  showFloatingMoney({
    amountDollars,
    tier,
    emojis: EMOJIS_BY_TIER[tier],
  });

  const milestone = milestoneCrossed(totalBefore, totalAfter, goalDollars);
  if (milestone !== null) {
    // Layer the milestone fanfare ~500ms after the tier sound starts —
    // playMilestoneFanfare already inserts the offset internally.
    playMilestoneFanfare(milestone);
    // Milestone toast comes in ~600ms behind the regular tier toast so
    // they don't visually stack on top of each other in the same beat.
    window.setTimeout(() => {
      showEncouragement(`${milestoneLabel(milestone)} ${pickMilestoneEncouragement()}`);
    }, 600);
  }
}

function milestoneLabel(percent: number): string {
  if (percent >= 200) return '🚀 DOUBLE goal!!';
  if (percent >= 150) return '💎 150% there!';
  if (percent >= 100) return '🎉 GOAL HIT!';
  if (percent >= 75) return '🌟 75% there!';
  if (percent >= 50) return '💖 Halfway!';
  return '🌸 25% in!';
}
