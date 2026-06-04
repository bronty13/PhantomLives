import { buildForest, type MindGraph } from './graph';

/**
 * Given the set of collapsed node ids, return the set of nodes that should be
 * HIDDEN — i.e. every descendant (in the spanning forest) of any collapsed
 * node. The collapsed nodes themselves stay visible (you can still see + expand
 * them); only their subtrees fold away. Pure and deterministic.
 */
export function hiddenNodeIds(graph: MindGraph, collapsed: Set<string>): Set<string> {
  if (collapsed.size === 0) return new Set();
  const { children } = buildForest(graph);
  const hidden = new Set<string>();

  const hideSubtree = (id: string) => {
    for (const child of children.get(id) ?? []) {
      if (hidden.has(child)) continue;
      hidden.add(child);
      hideSubtree(child);
    }
  };
  for (const id of collapsed) hideSubtree(id);
  return hidden;
}
