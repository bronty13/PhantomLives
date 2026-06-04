/**
 * @file hierarchyData.ts — build a depth- and budget-bounded plain-object
 * hierarchy from the SoA `Tree`, largest children first. Shared by the treemap
 * and sunburst layouts so both visualize the same bounded subtree.
 */
import type { SortSpec } from '../../shared/types';
import type { Tree } from './tree';

export interface DataNode {
  id: number;
  name: string;
  path: string;
  size: number;
  isDir: boolean;
  depth: number;
  children?: DataNode[];
}

const SIZE_DESC: SortSpec = { key: 'size', dir: 'desc' };

/**
 * @param tree     the scanned tree
 * @param focusId  node to render as the root
 * @param maxDepth how many levels below the focus to descend
 * @param budget   soft cap on total nodes (biggest-first)
 */
export function buildHierarchyData(
  tree: Tree,
  focusId: number,
  maxDepth: number,
  budget: number
): DataNode | null {
  if (focusId < 0 || focusId >= tree.nodeCount) return null;
  let count = 0;
  const build = (id: number, depth: number): DataNode => {
    const r = tree.row(id);
    const node: DataNode = { id, name: r.name, path: r.path, size: r.aggSize, isDir: r.isDir, depth };
    count++;
    if (r.isDir && depth < maxDepth && r.childCount > 0 && count < budget) {
      const kids = tree.getChildren(id, SIZE_DESC, r.childCount, 0).filter((c) => c.aggSize > 0);
      const children: DataNode[] = [];
      for (const kid of kids) {
        if (count >= budget) break;
        children.push(build(kid.id, depth + 1));
      }
      if (children.length > 0) node.children = children;
    }
    return node;
  };
  return build(focusId, 0);
}
