/**
 * @file types.ts — core domain types for the Purple Chef simulation.
 *
 * Everything in src/shared is pure TypeScript with no Electron/DOM imports so
 * the whole game brain is unit-testable under vitest on plain Node.
 */

export type IngredientKind = 'lettuce' | 'tomato' | 'onion' | 'meat' | 'bun' | 'cheese';

/** Prep lifecycle. `raw` → (board) → `chopped` → (stove) → `cooked`. */
export type PrepState = 'raw' | 'chopped' | 'cooked';

/** A prepared ingredient as it exists on a plate / board / in a pot. */
export interface Component {
  kind: IngredientKind;
  state: PrepState;
}

export type Item =
  | { type: 'ing'; kind: IngredientKind; state: PrepState }
  | { type: 'plate'; contents: Component[] };

export type TileKind =
  | 'floor'
  | 'counter'
  | 'crate' // infinite ingredient source
  | 'board' // chopping board
  | 'stove' // built-in pot/pan
  | 'plates' // infinite clean-plate stack
  | 'serve' // serving window
  | 'trash';

export type PotPhase = 'idle' | 'cooking' | 'done' | 'burnt';

export interface Pot {
  contents: Component[];
  /** 0..1 cooking progress (runs while phase === 'cooking'). */
  progress: number;
  /** 0..1 time-to-fire after done (runs while phase === 'done'). */
  burn: number;
  phase: PotPhase;
}

export interface Tile {
  kind: TileKind;
  /** Which ingredient this crate dispenses. */
  crate?: IngredientKind;
  /** Item resting on a counter or board. */
  item?: Item | null;
  /** 0..1 chop progress for the item on a board. */
  chop?: number;
  /** The stove's built-in pot. */
  pot?: Pot;
}

export interface ChefState {
  /** Center position in tile units (tile centers are at integer + 0.5). */
  x: number;
  y: number;
  /** Unit facing vector (axis-aligned). */
  fx: number;
  fy: number;
  carrying: Item | null;
  /** Animation phase accumulator (advances while moving). */
  walkPhase: number;
  /** True last tick the chef was actively chopping (for animation/SFX). */
  chopping: boolean;
}

export interface ScheduledOrder {
  atMs: number;
  recipeId: string;
  patienceMs: number;
}

export interface ActiveOrder {
  id: number;
  recipeId: string;
  spawnedAtMs: number;
  patienceMs: number;
}

export type SimEventType =
  | 'pickup'
  | 'place'
  | 'chopTick'
  | 'chopDone'
  | 'potAdd'
  | 'cookDone'
  | 'burnt'
  | 'potCleared'
  | 'plateAdd'
  | 'soupPoured'
  | 'serveOk'
  | 'serveBad'
  | 'orderNew'
  | 'orderExpired'
  | 'trash';

export interface SimEvent {
  type: SimEventType;
  /** Tile coords of where it happened (for particles). */
  x: number;
  y: number;
  /** serveOk: points awarded; orderExpired: penalty. */
  points?: number;
  recipeId?: string;
}

export interface KitchenState {
  w: number;
  h: number;
  grid: Tile[][]; // [y][x]
  chef: ChefState;
  schedule: ScheduledOrder[];
  nextScheduleIdx: number;
  nextOrderId: number;
  orders: ActiveOrder[];
  timeMs: number;
  score: number;
  combo: number; // current tip multiplier, 1..comboMax
  maxCombo: number;
  served: number;
  missed: number;
  /** Drained by the renderer every frame. */
  events: SimEvent[];
}

export interface SimInput {
  /** Movement intent, each in [-1, 1]. */
  mx: number;
  my: number;
  /** Edge-triggered: true exactly on the tick the button was pressed. */
  interact: boolean;
}

export interface SimConfig {
  chefSpeed: number; // tiles per second
  chopMs: number;
  cookMs: number;
  burnMs: number; // time from done -> burnt
  tipMax: number;
  missPenalty: number;
  comboMax: number;
  plateCapacity: number;
}

export type DifficultyId = 'novice' | 'chef' | 'master';

export interface MatchResult {
  at: string; // ISO date
  levelId: string;
  difficulty: DifficultyId;
  playerScore: number;
  aiScore: number;
  won: boolean;
  tied: boolean;
  stars: 0 | 1 | 2 | 3;
  served: number;
  missed: number;
  maxCombo: number;
  /** Highest patience fraction remaining on any served order (0..1). */
  bestServeFrac: number;
}

export interface BackupInfo {
  name: string;
  path: string;
  sizeBytes: number;
  createdMs: number;
}

export interface Preferences {
  version: number;
  soundEnabled: boolean;
  musicEnabled: boolean;
  chefName: string;
  // ----- Backup standard -----
  autoBackupEnabled: boolean;
  backupPath: string;
  backupRetentionDays: number;
  lastBackupMs: number;
  // ----- UX state -----
  windowWidth: number;
  windowHeight: number;
}

export interface SaveData {
  history: MatchResult[];
  trophies: Record<string, string>; // trophy id -> ISO date earned
  totals: { dishesServed: number; matchesPlayed: number; wins: number; winStreak: number };
}
