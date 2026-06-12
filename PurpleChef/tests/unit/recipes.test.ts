import { describe, expect, it } from 'vitest';
import {
  INGREDIENTS,
  RECIPES,
  componentsKey,
  missingForRecipe,
  plateMatchesRecipe,
  plateSubsetOfRecipe
} from '../../src/shared/recipes';
import { LEVELS, buildKitchen, getLevel, levelCrateKinds } from '../../src/shared/levels';

describe('recipes', () => {
  it('componentsKey is order-independent', () => {
    expect(
      componentsKey([
        { kind: 'lettuce', state: 'chopped' },
        { kind: 'tomato', state: 'chopped' }
      ])
    ).toBe(
      componentsKey([
        { kind: 'tomato', state: 'chopped' },
        { kind: 'lettuce', state: 'chopped' }
      ])
    );
  });

  it('plateMatchesRecipe demands the exact multiset', () => {
    expect(plateMatchesRecipe([{ kind: 'lettuce', state: 'chopped' }], 'leafy-salad')).toBe(true);
    expect(plateMatchesRecipe([{ kind: 'lettuce', state: 'raw' }], 'leafy-salad')).toBe(false);
    expect(
      plateMatchesRecipe(
        [
          { kind: 'tomato', state: 'cooked' },
          { kind: 'tomato', state: 'cooked' }
        ],
        'tomato-soup'
      )
    ).toBe(false);
  });

  it('missingForRecipe counts down correctly', () => {
    const missing = missingForRecipe([{ kind: 'bun', state: 'raw' }], 'cheeseburger');
    expect(missing).toHaveLength(2);
    expect(missing.some((m) => m.kind === 'meat' && m.state === 'cooked')).toBe(true);
    expect(missing.some((m) => m.kind === 'cheese' && m.state === 'chopped')).toBe(true);
  });

  it('plateSubsetOfRecipe rejects junk', () => {
    expect(plateSubsetOfRecipe([{ kind: 'onion', state: 'cooked' }], 'tomato-soup')).toBe(false);
    expect(plateSubsetOfRecipe([{ kind: 'tomato', state: 'cooked' }], 'tomato-soup')).toBe(true);
  });

  it('every level recipe is satisfiable from that level’s crates', () => {
    for (const level of LEVELS) {
      const crates = levelCrateKinds(buildKitchen(getLevel(level.id)));
      for (const rid of level.recipeIds) {
        for (const comp of RECIPES[rid].needs) {
          expect(crates.has(comp.kind), `${level.id}/${rid} needs ${comp.kind}`).toBe(true);
        }
      }
    }
  });

  it('cookable components in recipes are reachable through chop→cook', () => {
    for (const r of Object.values(RECIPES)) {
      for (const c of r.needs) {
        const info = INGREDIENTS[c.kind];
        if (c.state === 'cooked') expect(info.cookable).toBe(true);
        if (c.state === 'chopped') expect(info.choppable).toBe(true);
        if (c.state === 'raw') expect(info.rawOnPlate).toBe(true);
      }
    }
  });
});
