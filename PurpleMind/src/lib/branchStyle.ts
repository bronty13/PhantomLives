import { buildForest, type MindGraph } from './graph';

export type Tier = 'root' | 'topic' | 'item';

export interface NodeStyle {
  depth: number;
  tier: Tier;
  /** Colour of this node's top-level branch (its depth-1 ancestor). */
  branchColor: string;
  /** Effective colour = manual override ?? branch colour (root → ROOT_COLOR). */
  color: string;
  /** Number of direct (forest) children — drives the fold toggle. */
  childCount: number;
}

// MindNode-ish branch palette, assigned to each top-level branch in order.
export const BRANCH_PALETTE = [
  '#e0699b', // pink
  '#f08a5d', // orange
  '#f6b93b', // amber
  '#46b98a', // green
  '#3aa6b9', // teal
  '#4f8df5', // blue
  '#7c4ac4', // indigo
  '#c44a9e', // magenta
];

export const ROOT_COLOR = '#9361db'; // brand purple for the central root

/**
 * Derive per-node mindmap styling from graph structure:
 *   - depth from the component root, mapped to a tier (root/topic/item),
 *   - a branch colour (each top-level branch gets a palette hue; descendants
 *     inherit it), and
 *   - an effective colour where a manual override on a node wins, and an
 *     override on a depth-1 node recolours its whole branch.
 *
 * Pure and deterministic given input order. No React/DB dependencies.
 */
export function computeBranchStyles(
  graph: MindGraph,
  overrides?: Map<string, string | null>,
): Map<string, NodeStyle> {
  const { roots, children, parent } = buildForest(graph);
  const rootSet = new Set(roots);
  const ov = overrides ?? new Map<string, string | null>();

  // Depth via BFS from every root.
  const depth = new Map<string, number>();
  for (const r of roots) {
    depth.set(r, 0);
    const q = [r];
    while (q.length) {
      const cur = q.shift()!;
      for (const k of children.get(cur) ?? []) {
        depth.set(k, (depth.get(cur) ?? 0) + 1);
        q.push(k);
      }
    }
  }

  // The depth-1 ancestor ("branch root") of a node, or undefined for a root.
  const branchAncestor = (id: string): string | undefined => {
    if (rootSet.has(id)) return undefined;
    let cur = id;
    // Guard against pathological cycles with a bounded walk.
    for (let i = 0; i < graph.nodes.length + 1; i++) {
      const p = parent.get(cur) ?? null;
      if (p === null) return undefined;
      if (rootSet.has(p)) return cur;
      cur = p;
    }
    return undefined;
  };

  // Palette index per top-level branch, stable in node/child order.
  const branchIndex = new Map<string, number>();
  let next = 0;
  for (const r of roots) {
    for (const child of children.get(r) ?? []) branchIndex.set(child, next++);
  }

  const branchColorOf = (branchId: string): string => {
    const override = ov.get(branchId);
    if (override) return override;
    const idx = branchIndex.get(branchId) ?? 0;
    return BRANCH_PALETTE[idx % BRANCH_PALETTE.length];
  };

  const styles = new Map<string, NodeStyle>();
  for (const n of graph.nodes) {
    const d = depth.get(n.id) ?? 0;
    const tier: Tier = d === 0 ? 'root' : d === 1 ? 'topic' : 'item';
    const branch = branchAncestor(n.id);
    const branchColor = branch ? branchColorOf(branch) : ROOT_COLOR;
    const own = ov.get(n.id);
    const color = own ? own : tier === 'root' ? ROOT_COLOR : branchColor;
    const childCount = (children.get(n.id) ?? []).length;
    styles.set(n.id, { depth: d, tier, branchColor, color, childCount });
  }
  return styles;
}
