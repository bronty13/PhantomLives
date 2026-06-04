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

/**
 * Bilateral mind-map layout: the root sits at the centre and its top-level
 * branches fan out to BOTH sides (MindNode style). Branches are split
 * left/right to balance leaf counts; each side is a tidy tree growing away
 * from the centre. Extra disconnected components are laid out to the right and
 * stacked below. Pure and deterministic.
 */
export function layoutBilateral(graph: MindGraph, options: LayoutOptions = {}): Position[] {
  const opt = { ...DEFAULTS, ...options };
  const { roots, children } = buildForest(graph);
  const pos = new Map<string, { x: number; y: number }>();

  const leafCount = (id: string): number => {
    const kids = children.get(id) ?? [];
    return kids.length === 0 ? 1 : kids.reduce((s, k) => s + leafCount(k), 0);
  };

  // Lay out a subtree growing in `sign` direction (+1 right, -1 left), filling
  // vertical leaf slots from the shared `leaf` counter.
  const layoutSubtree = (id: string, depth: number, sign: number, leaf: { v: number }) => {
    const kids = children.get(id) ?? [];
    const x = sign * depth * opt.hSpacing;
    if (kids.length === 0) {
      pos.set(id, { x, y: leaf.v * opt.vSpacing });
      leaf.v += 1;
      return;
    }
    for (const k of kids) layoutSubtree(k, depth + 1, sign, leaf);
    const first = pos.get(kids[0])!.y;
    const last = pos.get(kids[kids.length - 1])!.y;
    pos.set(id, { x, y: (first + last) / 2 });
  };

  const yOf = (ids: string[]) => ids.map((id) => pos.get(id)!.y);
  let stackOffset = 0; // leaf-slots already consumed by earlier components

  roots.forEach((root, ri) => {
    const kids = children.get(root) ?? [];

    if (ri === 0) {
      // Split branches left/right, balancing total leaves on each side.
      const left: string[] = [];
      const right: string[] = [];
      let lLeaves = 0;
      let rLeaves = 0;
      for (const k of kids) {
        const lc = leafCount(k);
        if (rLeaves <= lLeaves) {
          right.push(k);
          rLeaves += lc;
        } else {
          left.push(k);
          lLeaves += lc;
        }
      }
      const rLeaf = { v: 0 };
      const lLeaf = { v: 0 };
      for (const k of right) layoutSubtree(k, 1, +1, rLeaf);
      for (const k of left) layoutSubtree(k, 1, -1, lLeaf);
      const ys = yOf(kids);
      pos.set(root, { x: 0, y: ys.length ? (Math.min(...ys) + Math.max(...ys)) / 2 : 0 });
      const allY = [...pos.values()].map((p) => p.y);
      stackOffset = (allY.length ? Math.max(...allY) : 0) / opt.vSpacing + 2;
    } else {
      // Extra component: right-growing tree stacked below the main one.
      const leaf = { v: stackOffset };
      if (kids.length === 0) {
        pos.set(root, { x: 0, y: leaf.v * opt.vSpacing });
        leaf.v += 1;
      } else {
        for (const k of kids) layoutSubtree(k, 1, +1, leaf);
        const ys = yOf(kids);
        pos.set(root, { x: 0, y: (Math.min(...ys) + Math.max(...ys)) / 2 });
      }
      stackOffset = leaf.v + 2;
    }
  });

  return graph.nodes.map((n) => {
    const p = pos.get(n.id) ?? { x: 0, y: 0 };
    return { id: n.id, x: p.x, y: p.y };
  });
}
