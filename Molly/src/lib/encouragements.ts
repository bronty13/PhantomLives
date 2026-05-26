// Tier-keyed bank of encouraging one-liners shown to Sallie when she
// logs income. Picked by `pickEncouragement(tier)`, which tracks the
// most recent N indices in module-scope state to avoid repeats within
// a session. Recent-avoidance is shared across tiers so back-to-back
// saves never repeat the same line even when they're in different
// banks.
//
// Tiers:
//   - tiny      (< $10)        soft, low-key
//   - small     ($10–$49)      everyday "yay you"
//   - medium    ($50–$199)     enthusiastic
//   - big       ($200–$999)    big-girl-bag energy
//   - whale     ($1000+)       full queen / fireworks
//   - milestone (goal % cross) celebration of crossing 25/50/75/100/150/200%
//
// Expense logging does NOT trigger any of these — only money-IN
// moments deserve a celebration.

export type EncouragementTier = 'tiny' | 'small' | 'medium' | 'big' | 'whale';

interface BanksShape {
  tiny: readonly string[];
  small: readonly string[];
  medium: readonly string[];
  big: readonly string[];
  whale: readonly string[];
  milestone: readonly string[];
}

export const BANKS: BanksShape = {
  tiny: [
    'Every dollar counts! 🌸',
    'Tiny win, still a win! 💗',
    'Add it up! ✨',
    'Cute little ding! 🎀',
    'Pennies become dollars! 🪙',
    'Small bag, real bag! 👛',
    'A little sparkle! ✨',
    'It all adds up! 💕',
    'Soft win! 🌷',
    'Pretty drip! 💧',
  ],
  small: [
    'Way to go, girl! 💕',
    "You're crushing it! ✨",
    'Look at you go! 🌟',
    'Cha-ching, queen! 👑',
    'Money moves only! 💸',
    'Yes!! Get that bag! 💰',
    'Boss energy! 💖',
    'Another win on the board! 🏆',
    'Proud of you! 🌷',
    "That's our girl! 🎉",
    'Slaying it today! 💅',
    'Bag secured! 👛',
    'On fire today! 🔥',
    'You hustle, you eat! 🍰',
    "You're a STAR! ⭐",
    'Magic hands! ✨',
    'Look at this glow up! 🌸',
    'Income queen! 👑',
    'Sparkle, sparkle, paid! ✨',
    "That's how we do it! 💕",
    'Cute and rich! 🌟',
    'Banking on you! 🌸',
    'Coin collector! 🪙',
    'Worth every penny! 💖',
    'Heart-eyes on those numbers! 😍',
    'Soft girl, hard work! 🌷',
    'Showing the world! 💕',
    'Sallie season! 🎀',
    'Money in motion! 💖',
    'Big girl bag! 👜',
  ],
  medium: [
    'Now THAT is a sale! 🌟',
    'Killer custom! 🔥',
    'Big energy unlocked! ⚡',
    'Sallie out here EATING! 🍰',
    'Diva paycheck! 💖',
    'Hot girl money! 🔥',
    'Premium pricing pays! 💎',
    'Look at this glow! ✨',
    'Receipts looking PRETTY! 🧾',
    'Goddess of the day! 🌷',
    'Cute and PAID! 👛',
    "She's BOOKED! 📒",
    'Bouquet of cash incoming! 💐',
    'Top tier work! 🏆',
  ],
  big: [
    'BIG BAG ALERT! 👜',
    'STOP IT — that is HUGE! 🌟',
    'Sallie hit a HOME RUN! 🏆',
    'Whale alert! 🐋💕',
    'Multi-figure cutie! ✨',
    'Power-move pricing! 💎',
    'Queen of the customs! 👑',
    'Big bag, big smile! 💖',
    'Pretty AND profitable! 🌹',
    'Sallie literally cannot be stopped! 🚀',
    "She's BANKING today! 🏦",
    'Hot girl summer hot girl money! 🔥',
  ],
  whale: [
    'HOLY MOLY!! 🚀🚀🚀',
    'QUEEN MOVES!! 👑👑👑',
    'JACKPOT, SALLIE!! 🎰💖',
    'BIG WHALE INCOMING!! 🐋✨',
    'MAJOR MOVES!! 🌟💸🌟',
    'ICONIC PRICING!! 💎💎💎',
    'YOU JUST CHANGED LIVES!! 💖',
    'FRONT PAGE NEWS!! 📰⭐',
    'WHALE ALERT WHALE ALERT!! 🚨🐋',
    'THIS IS HOW LEGENDS ARE MADE!! 🏆',
    'YOU. ARE. A. BUSINESS. 💼👑',
  ],
  milestone: [
    "Quarter of the way! 🌸",
    'Halfway there! 💖',
    'Three quarters down! 🌟',
    'GOAL HIT!! 🎉🎉🎉',
    'Over the moon!! 🚀',
    'DOUBLE goal! Stop it!! 💖💖',
    'You. Are. AMAZING. ✨',
    'Look at THIS milestone! 🏆',
    'Big day, big numbers! 💸',
    'Goal demolished!! 💥',
  ],
};

/** Order-preserving tier list — used by tests + tier-iteration code. */
export const TIERS: readonly EncouragementTier[] = ['tiny', 'small', 'medium', 'big', 'whale'];

// Avoid the last N picks. Shared across tiers so back-to-back saves
// in any combination of banks never repeat the visible string.
const RECENT_AVOIDANCE = 8;
let recentStrings: string[] = [];

/**
 * Return a random encouragement from the given tier's bank, biased
 * away from any string shown in the last ~8 picks (across all tiers
 * and including the milestone bank) so Sallie never sees the same
 * line twice in a row.
 */
export function pickEncouragement(tier: EncouragementTier): string {
  return pickFromBank(BANKS[tier]);
}

/** Same picker for the milestone bank — separated for type-level clarity. */
export function pickMilestoneEncouragement(): string {
  return pickFromBank(BANKS.milestone);
}

function pickFromBank(bank: readonly string[]): string {
  if (bank.length === 0) return '';
  const avoid = Math.min(RECENT_AVOIDANCE, bank.length - 1);
  const pool: string[] = bank.filter((s) => !recentStrings.includes(s));
  const chosen =
    pool.length > 0
      ? pool[Math.floor(Math.random() * pool.length)]
      : bank[Math.floor(Math.random() * bank.length)];
  recentStrings.push(chosen);
  while (recentStrings.length > avoid) recentStrings.shift();
  return chosen;
}

/** Test helper — resets the recent-picks history. Not exported for app use. */
export function _resetRecentForTests(): void {
  recentStrings = [];
}
