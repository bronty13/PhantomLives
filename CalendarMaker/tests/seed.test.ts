import { describe, it, expect } from 'vitest';
import { SEED_THEMES } from '../src/model/seedThemes';
import { FONT_REGISTRY } from '../src/data/fonts-registry';
import { HOLIDAYS } from '../src/data/holidays';
import { SAYINGS } from '../src/data/sayings';
import { BIBLE_BOOKS, getRandomVerse, getVerse } from '../src/data/bible';
import { ITEM_TYPES } from '../src/model/types';

describe('seed data', () => {
  const fontKeys = new Set(FONT_REGISTRY.map((f) => f.key));

  it('ships exactly 10 built-in themes, all well-formed', () => {
    expect(SEED_THEMES).toHaveLength(10);
    const ids = new Set(SEED_THEMES.map((t) => t.id));
    expect(ids.size).toBe(10);
    for (const t of SEED_THEMES) {
      expect(t.builtin).toBe(true);
      for (const type of ITEM_TYPES) {
        const style = t.itemStyles[type];
        expect(style, `${t.id} missing ${type}`).toBeTruthy();
        expect(fontKeys.has(style.font), `${t.id}.${type} bad font ${style.font}`).toBe(true);
        expect(/^#[0-9a-f]{6}$/i.test(style.color)).toBe(true);
      }
      expect(fontKeys.has(t.calendar.titleFont)).toBe(true);
      expect(fontKeys.has(t.calendar.fillerFont)).toBe(true);
    }
  });

  it('has a valid holiday catalog with unique ids', () => {
    const ids = new Set(HOLIDAYS.map((h) => h.id));
    expect(ids.size).toBe(HOLIDAYS.length);
    for (const h of HOLIDAYS) {
      expect(['federal', 'observance', 'christian']).toContain(h.category);
      expect(['fixed', 'nthWeekday', 'easterOffset']).toContain(h.rule.kind);
    }
    // covers all three categories
    expect(HOLIDAYS.some((h) => h.category === 'federal')).toBe(true);
    expect(HOLIDAYS.some((h) => h.category === 'observance')).toBe(true);
    expect(HOLIDAYS.some((h) => h.category === 'christian')).toBe(true);
  });

  it('has sayings', () => {
    expect(SAYINGS.length).toBeGreaterThan(0);
    expect(SAYINGS.every((s) => s.kind === 'saying' && s.text.length > 0)).toBe(true);
  });

  it('includes the Morning Affirmations (deduplicated, no IDs collide)', () => {
    const affirmations = SAYINGS.filter((s) => s.reference === 'Morning Affirmation');
    expect(affirmations.length).toBeGreaterThanOrEqual(20);
    // The base + gendered-unique lines, no duplicate text.
    const texts = affirmations.map((a) => a.text);
    expect(new Set(texts).size).toBe(texts.length);
    // A signature line from the base set is present.
    expect(texts.some((t) => t.startsWith('Jesus is first in my life'))).toBe(true);
    // No duplicate ids across the whole seed.
    const ids = SAYINGS.map((s) => s.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('has the full Bible and can fetch verses', () => {
    expect(BIBLE_BOOKS).toHaveLength(66);
    const john316 = getVerse('John', 3, 16);
    expect(john316).toBeTruthy();
    expect(john316!.reference).toBe('John 3:16');
    const rnd = getRandomVerse(() => 0.5);
    expect(rnd.text.length).toBeGreaterThan(0);
    expect(rnd.reference).toMatch(/\w+ \d+:\d+/);
  });
});
