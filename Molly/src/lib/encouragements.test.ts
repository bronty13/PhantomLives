import { describe, expect, it, beforeEach } from 'vitest';
import {
  BANKS,
  TIERS,
  pickEncouragement,
  pickMilestoneEncouragement,
  _resetRecentForTests,
} from './encouragements';

describe('pickEncouragement', () => {
  beforeEach(() => {
    _resetRecentForTests();
  });

  it('always returns one of the canonical sayings for the requested tier', () => {
    for (const tier of TIERS) {
      _resetRecentForTests();
      for (let i = 0; i < 30; i++) {
        expect(BANKS[tier]).toContain(pickEncouragement(tier));
      }
    }
  });

  it('avoids repeating any of the last ~8 strings (shared across tiers)', () => {
    // Pull from a mix of tiers — the recent-avoidance window is shared
    // by design so back-to-back saves never repeat regardless of size.
    const recent: string[] = [];
    const tiers = TIERS;
    for (let i = 0; i < 40; i++) {
      const tier = tiers[i % tiers.length];
      const next = pickEncouragement(tier);
      const lastEight = recent.slice(-8);
      expect(lastEight).not.toContain(next);
      recent.push(next);
    }
  });

  it('exercises full variety of each tier across many picks', () => {
    for (const tier of TIERS) {
      _resetRecentForTests();
      const seen = new Set<string>();
      // Pick liberally — at least enough to cycle through a 30-line bank
      // many times. Bigger banks need more iterations to fully exercise.
      for (let i = 0; i < BANKS[tier].length * 12; i++) {
        seen.add(pickEncouragement(tier));
      }
      expect(seen.size).toBe(BANKS[tier].length);
    }
  });
});

describe('pickMilestoneEncouragement', () => {
  beforeEach(() => {
    _resetRecentForTests();
  });

  it('returns strings from the milestone bank', () => {
    for (let i = 0; i < 20; i++) {
      expect(BANKS.milestone).toContain(pickMilestoneEncouragement());
    }
  });

  it('shares the recent-avoidance window with tier picks', () => {
    const first = pickMilestoneEncouragement();
    // Within the next 8 picks (from any bank), `first` must not reappear.
    const subsequent: string[] = [];
    for (let i = 0; i < 8; i++) {
      subsequent.push(pickEncouragement('small'));
    }
    expect(subsequent).not.toContain(first);
  });
});
