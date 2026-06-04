/**
 * @file treemap.ts — squarified treemap layout, computed in the main process.
 *
 * Builds a depth- and budget-bounded hierarchy from the SoA `Tree` (largest
 * children first), runs d3's squarified treemap over a pixel box, and returns
 * a flat `RectNode[]` the renderer paints on a single canvas. Keeping d3 in
 * main lets us reuse the in-memory tree without shipping it to the renderer.
 */
import { hierarchy, treemap, treemapSquarify } from 'd3-hierarchy';
import type { RectNode } from '../../shared/types';
import type { Tree } from './tree';
import { buildHierarchyData, type DataNode } from './hierarchyData';

/**
 * @param tree    the scanned tree
 * @param focusId node to render as the treemap root
 * @param width   pixel width of the canvas
 * @param height  pixel height of the canvas
 * @param maxDepth how many levels below the focus to descend (default 3)
 * @param budget  soft cap on total rects (default 2000); biggest-first
 */
export function computeTreemap(
  tree: Tree,
  focusId: number,
  width: number,
  height: number,
  maxDepth = 3,
  budget = 2000
): RectNode[] {
  if (width <= 0 || height <= 0) return [];
  const data = buildHierarchyData(tree, focusId, maxDepth, budget);
  if (!data) return [];

  const root = hierarchy<DataNode>(data)
    .sum((d) => (d.children && d.children.length ? 0 : d.size))
    .sort((a, b) => (b.value ?? 0) - (a.value ?? 0));

  const laidOut = treemap<DataNode>()
    .tile(treemapSquarify)
    .size([width, height])
    .paddingInner(1)
    .round(true)(root);

  const rects: RectNode[] = [];
  for (const node of laidOut.descendants()) {
    const x0 = node.x0 ?? 0;
    const y0 = node.y0 ?? 0;
    const x1 = node.x1 ?? 0;
    const y1 = node.y1 ?? 0;
    rects.push({
      id: node.data.id,
      name: node.data.name,
      path: node.data.path,
      size: node.value ?? node.data.size,
      x: x0,
      y: y0,
      w: Math.max(0, x1 - x0),
      h: Math.max(0, y1 - y0),
      depth: node.depth,
      isDir: node.data.isDir
    });
  }
  return rects;
}
