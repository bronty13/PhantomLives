/**
 * @file recipes.ts — dish definitions and ingredient properties.
 */
import type { Component, IngredientKind, PrepState } from './types';

export interface IngredientInfo {
  kind: IngredientKind;
  label: string;
  choppable: boolean;
  /** After chopping, can it go in a stove pot? */
  cookable: boolean;
  /** May be placed on a plate raw (e.g. a bun). */
  rawOnPlate: boolean;
  /** Pot capacity when this is the pot's ingredient category. */
  potCapacity: number;
}

export const INGREDIENTS: Record<IngredientKind, IngredientInfo> = {
  lettuce: { kind: 'lettuce', label: 'Lettuce', choppable: true, cookable: false, rawOnPlate: false, potCapacity: 0 },
  tomato: { kind: 'tomato', label: 'Tomato', choppable: true, cookable: true, rawOnPlate: false, potCapacity: 3 },
  onion: { kind: 'onion', label: 'Onion', choppable: true, cookable: true, rawOnPlate: false, potCapacity: 3 },
  meat: { kind: 'meat', label: 'Beef Patty', choppable: true, cookable: true, rawOnPlate: false, potCapacity: 1 },
  bun: { kind: 'bun', label: 'Bun', choppable: false, cookable: false, rawOnPlate: true, potCapacity: 0 },
  cheese: { kind: 'cheese', label: 'Cheese', choppable: true, cookable: false, rawOnPlate: false, potCapacity: 0 }
};

export interface Recipe {
  id: string;
  name: string;
  /** Exact multiset of components the plate must hold. */
  needs: Component[];
  basePoints: number;
  /** Relative spawn weight per difficulty bias tier. */
  weight: { simple: number; balanced: number; hard: number };
}

const C = (kind: IngredientKind, state: PrepState): Component => ({ kind, state });

export const RECIPES: Record<string, Recipe> = {
  'leafy-salad': {
    id: 'leafy-salad',
    name: 'Leafy Salad',
    needs: [C('lettuce', 'chopped')],
    basePoints: 20,
    weight: { simple: 5, balanced: 3, hard: 2 }
  },
  'garden-salad': {
    id: 'garden-salad',
    name: 'Garden Salad',
    needs: [C('lettuce', 'chopped'), C('tomato', 'chopped')],
    basePoints: 30,
    weight: { simple: 3, balanced: 5, hard: 5 }
  },
  'tomato-salad': {
    id: 'tomato-salad',
    name: 'Tomato Salad',
    needs: [C('tomato', 'chopped'), C('tomato', 'chopped')],
    basePoints: 25,
    weight: { simple: 5, balanced: 4, hard: 2 }
  },
  'tomato-soup': {
    id: 'tomato-soup',
    name: 'Tomato Soup',
    needs: [C('tomato', 'cooked'), C('tomato', 'cooked'), C('tomato', 'cooked')],
    basePoints: 40,
    weight: { simple: 3, balanced: 4, hard: 5 }
  },
  'onion-soup': {
    id: 'onion-soup',
    name: 'Onion Soup',
    needs: [C('onion', 'cooked'), C('onion', 'cooked'), C('onion', 'cooked')],
    basePoints: 40,
    weight: { simple: 2, balanced: 4, hard: 5 }
  },
  burger: {
    id: 'burger',
    name: 'Burger',
    needs: [C('bun', 'raw'), C('meat', 'cooked')],
    basePoints: 40,
    weight: { simple: 5, balanced: 4, hard: 3 }
  },
  cheeseburger: {
    id: 'cheeseburger',
    name: 'Cheeseburger',
    needs: [C('bun', 'raw'), C('meat', 'cooked'), C('cheese', 'chopped')],
    basePoints: 50,
    weight: { simple: 2, balanced: 4, hard: 5 }
  },
  'deluxe-burger': {
    id: 'deluxe-burger',
    name: 'Deluxe Burger',
    needs: [
      C('bun', 'raw'),
      C('meat', 'cooked'),
      C('cheese', 'chopped'),
      C('lettuce', 'chopped'),
      C('tomato', 'chopped')
    ],
    basePoints: 70,
    weight: { simple: 1, balanced: 2, hard: 5 }
  }
};

export function getRecipe(id: string): Recipe {
  const r = RECIPES[id];
  if (!r) throw new Error(`unknown recipe: ${id}`);
  return r;
}

/** Multiset key for a component list (order-independent comparison). */
export function componentsKey(comps: Component[]): string {
  return comps
    .map((c) => `${c.kind}:${c.state}`)
    .sort()
    .join('|');
}

/** Does a plate's contents exactly satisfy a recipe? */
export function plateMatchesRecipe(contents: Component[], recipeId: string): boolean {
  return componentsKey(contents) === componentsKey(getRecipe(recipeId).needs);
}

/** Remaining components a plate still needs for a recipe (empty = complete). */
export function missingForRecipe(contents: Component[], recipeId: string): Component[] {
  const remaining = [...getRecipe(recipeId).needs];
  for (const c of contents) {
    const i = remaining.findIndex((r) => r.kind === c.kind && r.state === c.state);
    if (i >= 0) remaining.splice(i, 1);
  }
  return remaining;
}

/** True if the plate holds only components the recipe wants (no junk). */
export function plateSubsetOfRecipe(contents: Component[], recipeId: string): boolean {
  const remaining = [...getRecipe(recipeId).needs];
  for (const c of contents) {
    const i = remaining.findIndex((r) => r.kind === c.kind && r.state === c.state);
    if (i < 0) return false;
    remaining.splice(i, 1);
  }
  return true;
}
