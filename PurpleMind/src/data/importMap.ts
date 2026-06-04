import { createMap } from './maps';
import { createNode } from './nodes';
import { createEdge } from './edges';
import { layoutTree } from '../lib/autoLayout';
import type { MindGraph } from '../lib/graph';

export interface ImportNode {
  /** Source id (temp id from markdown, or original id from JSON). */
  ref: string;
  label: string;
  x?: number;
  y?: number;
  color?: string | null;
}

export interface ImportEdge {
  source: string;
  target: string;
}

/**
 * Create a brand-new map from an imported graph, assigning fresh ids to every
 * node and remapping edges. When `autoArrange` is true (Markdown import, or
 * JSON without positions) the nodes are tidied with the auto-layout engine.
 * Returns the new map id.
 */
export async function importGraph(
  title: string,
  nodes: ImportNode[],
  edges: ImportEdge[],
  autoArrange: boolean,
): Promise<string> {
  const map = await createMap(title);

  // Optionally compute tidy positions up front.
  let positionByRef = new Map<string, { x: number; y: number }>();
  if (autoArrange) {
    const graph: MindGraph = {
      nodes: nodes.map((n) => ({ id: n.ref, label: n.label, x: 0, y: 0 })),
      edges: edges.map((e, i) => ({ id: `e${i}`, source: e.source, target: e.target })),
    };
    positionByRef = new Map(layoutTree(graph).map((p) => [p.id, { x: p.x, y: p.y }]));
  }

  const idByRef = new Map<string, string>();
  for (const n of nodes) {
    const pos = positionByRef.get(n.ref) ?? { x: n.x ?? 0, y: n.y ?? 0 };
    const row = await createNode(map.id, n.label, pos.x, pos.y, n.color ?? null);
    idByRef.set(n.ref, row.id);
  }
  for (const e of edges) {
    const source = idByRef.get(e.source);
    const target = idByRef.get(e.target);
    if (source && target) await createEdge(map.id, source, target);
  }

  return map.id;
}
