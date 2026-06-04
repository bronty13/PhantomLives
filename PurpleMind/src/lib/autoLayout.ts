import { buildForest, type MindGraph } from './graph';

export interface Position {
  id: string;
  x: number;
  y: number;
}

export interface LayoutOptions {
  /** Horizontal gap between tree depths (px). */
  hSpacing?: number;
  /** Vertical gap between sibling leaves (px). */
  vSpacing?: number;
  /** Vertical gap between disconnected components (in leaf-slots). */
  treeGap?: number;
}

const DEFAULTS: Required<LayoutOptions> = {
  hSpacing: 240,
  vSpacing: 96,
  treeGap: 1.2,
};

/**
 * Tidy left-to-right tree layout. Each node's x is its depth; leaves take
 * consecutive vertical slots and each parent is centred on its children.
 * Disconnected components are stacked below one another. Pure and
 * deterministic — returns new positions, mutating nothing.
 */
export function layoutTree(graph: MindGraph, options: LayoutOptions = {}): Position[] {
  const opt = { ...DEFAULTS, ...options };
  const { roots, children } = buildForest(graph);

  const depth = new Map<string, number>();
  const slot = new Map<string, number>();
  let nextLeaf = 0;

  const assign = (id: string, d: number) => {
    depth.set(id, d);
    const kids = children.get(id) ?? [];
    if (kids.length === 0) {
      slot.set(id, nextLeaf);
      nextLeaf += 1;
      return;
    }
    for (const k of kids) assign(k, d + 1);
    // Centre this node on the vertical span of its children.
    const first = slot.get(kids[0])!;
    const last = slot.get(kids[kids.length - 1])!;
    slot.set(id, (first + last) / 2);
  };

  for (const root of roots) {
    assign(root, 0);
    nextLeaf += opt.treeGap; // gap before the next component
  }

  return graph.nodes.map((n) => ({
    id: n.id,
    x: (depth.get(n.id) ?? 0) * opt.hSpacing,
    y: (slot.get(n.id) ?? 0) * opt.vSpacing,
  }));
}
