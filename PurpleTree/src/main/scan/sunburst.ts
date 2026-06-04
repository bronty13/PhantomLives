/**
 * @file sunburst.ts — radial (DaisyDisk-style) layout, computed in main.
 *
 * Runs d3's partition over the same bounded hierarchy the treemap uses, mapping
 * the x axis to angle [0, 2π] and the y axis to ring depth. Returns flat
 * `ArcNode[]` (angles in radians, radii normalized 0..1) that the renderer
 * paints as canvas arcs.
 */
import { hierarchy, partition } from 'd3-hierarchy';
import type { ArcNode } from '../../shared/types';
import type { Tree } from './tree';
import { buildHierarchyData, type DataNode } from './hierarchyData';

/**
 * @param tree     the scanned tree
 * @param focusId  node at the center of the sunburst
 * @param maxDepth how many rings below the focus to draw (default 5)
 * @param budget   soft cap on total arcs (default 3000); biggest-first
 */
export function computeSunburst(
  tree: Tree,
  focusId: number,
  maxDepth = 5,
  budget = 3000
): ArcNode[] {
  const data = buildHierarchyData(tree, focusId, maxDepth, budget);
  if (!data) return [];

  const root = hierarchy<DataNode>(data)
    .sum((d) => (d.children && d.children.length ? 0 : d.size))
    .sort((a, b) => (b.value ?? 0) - (a.value ?? 0));

  const rings = root.height + 1; // includes the focus node's center disc
  const laid = partition<DataNode>().size([2 * Math.PI, rings])(root);

  const arcs: ArcNode[] = [];
  for (const node of laid.descendants()) {
    const a0 = node.x0 ?? 0;
    const a1 = node.x1 ?? 0;
    const y0 = node.y0 ?? 0;
    const y1 = node.y1 ?? 0;
    arcs.push({
      id: node.data.id,
      name: node.data.name,
      path: node.data.path,
      size: node.value ?? node.data.size,
      depth: node.depth,
      isDir: node.data.isDir,
      a0,
      a1,
      r0: y0 / rings,
      r1: y1 / rings
    });
  }
  return arcs;
}
