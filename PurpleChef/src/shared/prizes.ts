/**
 * @file prizes.ts — the trophy cabinet: cute prizes earned by winning.
 *
 * evaluatePrizes is pure: given the just-finished result plus the player's
 * lifetime record, it returns the trophies newly earned this match.
 */
import type { MatchResult, SaveData } from './types';

export interface TrophyDef {
  id: string;
  name: string;
  emoji: string;
  blurb: string;
  /** Order on the shelf. */
  rank: number;
  earned: (r: MatchResult, save: SaveData) => boolean;
}

export const TROPHIES: TrophyDef[] = [
  {
    id: 'first-dish',
    name: 'Order Up!',
    emoji: '🍽️',
    blurb: 'Serve your very first dish.',
    rank: 1,
    earned: (r) => r.served > 0
  },
  {
    id: 'first-win',
    name: 'Rookie Rosette',
    emoji: '🏵️',
    blurb: 'Beat the rival chef for the first time.',
    rank: 2,
    earned: (r) => r.won
  },
  {
    id: 'bronze-whisk',
    name: 'Bronze Whisk',
    emoji: '🥉',
    blurb: 'Win a match on Novice.',
    rank: 3,
    earned: (r) => r.won && r.difficulty === 'novice'
  },
  {
    id: 'silver-spatula',
    name: 'Silver Spatula',
    emoji: '🥈',
    blurb: 'Win a match on Chef.',
    rank: 4,
    earned: (r) => r.won && r.difficulty === 'chef'
  },
  {
    id: 'golden-toque',
    name: 'Golden Toque',
    emoji: '🥇',
    blurb: 'Win a match on Master.',
    rank: 5,
    earned: (r) => r.won && r.difficulty === 'master'
  },
  {
    id: 'three-star',
    name: 'Michelin Mood',
    emoji: '⭐',
    blurb: 'Earn all three stars in a single match.',
    rank: 6,
    earned: (r) => r.stars === 3
  },
  {
    id: 'combo-king',
    name: 'Combo Crown',
    emoji: '👑',
    blurb: 'Reach the maximum 4× tip combo.',
    rank: 7,
    earned: (r) => r.maxCombo >= 4
  },
  {
    id: 'lightning-ladle',
    name: 'Lightning Ladle',
    emoji: '⚡',
    blurb: 'Serve a dish with 90% of the patience bar still green.',
    rank: 8,
    earned: (r) => r.bestServeFrac >= 0.9
  },
  {
    id: 'perfect-service',
    name: 'Spotless Service',
    emoji: '✨',
    blurb: 'Finish a match with five or more dishes served and none missed.',
    rank: 9,
    earned: (r) => r.missed === 0 && r.served >= 5
  },
  {
    id: 'hat-trick',
    name: 'Hat Trick',
    emoji: '🎩',
    blurb: 'Win three matches in a row.',
    rank: 10,
    earned: (r, save) => r.won && save.totals.winStreak >= 3
  },
  {
    id: 'centurion',
    name: 'Centurion of Cuisine',
    emoji: '💯',
    blurb: 'Serve 100 dishes, lifetime.',
    rank: 11,
    earned: (_r, save) => save.totals.dishesServed >= 100
  },
  {
    id: 'grand-slam',
    name: 'Grand Slam Garnish',
    emoji: '🏆',
    blurb: 'Win every kitchen on Master difficulty.',
    rank: 12,
    earned: (r, save) => {
      if (!r.won || r.difficulty !== 'master') return false;
      const wonLevels = new Set(
        save.history.filter((h) => h.won && h.difficulty === 'master').map((h) => h.levelId)
      );
      wonLevels.add(r.levelId);
      return wonLevels.size >= 3;
    }
  }
];

/**
 * Which trophies does this result newly earn?
 * `save` must already include the result in history/totals (call after fold).
 */
export function evaluatePrizes(result: MatchResult, save: SaveData): TrophyDef[] {
  return TROPHIES.filter((t) => !save.trophies[t.id] && t.earned(result, save)).sort(
    (a, b) => a.rank - b.rank
  );
}

/** Fold a finished match into the lifetime record (pure; returns a new SaveData). */
export function foldResult(save: SaveData, result: MatchResult): SaveData {
  const next: SaveData = {
    history: [...save.history, result],
    trophies: { ...save.trophies },
    totals: {
      dishesServed: save.totals.dishesServed + result.served,
      matchesPlayed: save.totals.matchesPlayed + 1,
      wins: save.totals.wins + (result.won ? 1 : 0),
      winStreak: result.won ? save.totals.winStreak + 1 : 0
    }
  };
  for (const t of evaluatePrizes(result, next)) {
    next.trophies[t.id] = result.at;
  }
  return next;
}

export const EMPTY_SAVE: SaveData = {
  history: [],
  trophies: {},
  totals: { dishesServed: 0, matchesPlayed: 0, wins: 0, winStreak: 0 }
};
