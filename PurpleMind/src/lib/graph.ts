// Plain, framework-free graph types shared by the pure helpers (auto-layout,
// markdown outline, serialize). Kept independent of React Flow and the DB row
// shapes so these modules stay unit-testable in a node environment.

export interface GNode {
  id: string;
  label: string;
  x: number;
  y: number;
  color?: string | null;
}

export interface GEdge {
  id: string;
  source: string;
  target: string;
}

export interface MindGraph {
  nodes: GNode[];
  edges: GEdge[];
}

/**
 * Build a parent→children forest from an undirected view of the graph,
 * rooted at nodes with no incoming edge (or, failing that, the first node of
 * each remaining component). Used by both auto-layout and the markdown
 * outline so they agree on tree shape. Deterministic given input order.
 */
export function buildForest(graph: MindGraph): {
  roots: string[];
  children: Map<string, string[]>;
  parent: Map<string, string | null>;
} {
  const byId = new Map(graph.nodes.map((n) => [n.id, n]));
  const adj = new Map<string, string[]>();
  for (const n of graph.nodes) adj.set(n.id, []);
  for (const e of graph.edges) {
    if (!byId.has(e.source) || !byId.has(e.target)) continue;
    adj.get(e.source)!.push(e.target);
    adj.get(e.target)!.push(e.source);
  }

  const incoming = new Set(graph.edges.map((e) => e.target));
  const children = new Map<string, string[]>();
  const parent = new Map<string, string | null>();
  for (const n of graph.nodes) children.set(n.id, []);

  const visited = new Set<string>();
  const roots: string[] = [];

  const bfsFrom = (root: string) => {
    roots.push(root);
    parent.set(root, null);
    visited.add(root);
    const queue = [root];
    while (queue.length) {
      const cur = queue.shift()!;
      for (const next of adj.get(cur) ?? []) {
        if (visited.has(next)) continue;
        visited.add(next);
        parent.set(next, cur);
        children.get(cur)!.push(next);
        queue.push(next);
      }
    }
  };

  // Prefer real roots (no incoming edge), in node order.
  for (const n of graph.nodes) {
    if (!visited.has(n.id) && !incoming.has(n.id)) bfsFrom(n.id);
  }
  // Remaining components (e.g. pure cycles) get their first node as root.
  for (const n of graph.nodes) {
    if (!visited.has(n.id)) bfsFrom(n.id);
  }

  return { roots, children, parent };
}
