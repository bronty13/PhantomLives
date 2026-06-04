import { type EdgeProps } from '@xyflow/react';
import { taperedRibbonPath } from '../lib/ribbon';

export interface BranchEdgeData {
  color: string;
  /** Depth of the child node — drives the taper width. */
  depth: number;
  [key: string]: unknown;
}

function widthsForDepth(depth: number): [number, number] {
  if (depth <= 1) return [12, 5];
  if (depth === 2) return [7, 3.5];
  return [4.5, 2.5];
}

/**
 * Branch connector: a filled, tapered ribbon in the branch colour (thick at
 * the parent, thin at the child). An invisible fat stroke sits underneath for
 * a comfortable click/selection target.
 */
export function BranchEdge({
  sourceX,
  sourceY,
  targetX,
  targetY,
  data,
  selected,
}: EdgeProps) {
  const d = data as BranchEdgeData | undefined;
  const color = d?.color ?? '#9361db';
  const [w0, w1] = widthsForDepth(d?.depth ?? 1);
  const path = taperedRibbonPath({ sx: sourceX, sy: sourceY, tx: targetX, ty: targetY, w0, w1 });
  // Straight-ish hit path for easy selection/deletion.
  const hit = `M ${sourceX} ${sourceY} C ${sourceX + 60} ${sourceY}, ${targetX - 60} ${targetY}, ${targetX} ${targetY}`;
  return (
    <>
      <path d={hit} fill="none" stroke="transparent" strokeWidth={16} style={{ pointerEvents: 'stroke' }} />
      <path
        d={path}
        fill={color}
        fillOpacity={selected ? 1 : 0.92}
        stroke="none"
        style={{ pointerEvents: 'none' }}
      />
    </>
  );
}
