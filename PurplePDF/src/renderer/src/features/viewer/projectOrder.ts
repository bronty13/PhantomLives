import type { PageOp } from '../annotate/flatten';

/** Rich per-slot info describing a single page in the projected ordering. */
export interface ProjectedSlot {
  /** 0-based original page index, or null for an inserted blank page. */
  source: number | null;
  /** Additional rotation (degrees, clockwise) to apply on top of the
   *  page's native rotation. Multiple of 90. */
  rotation: number;
  /** If set, crop box (in PDF point units, origin bottom-left) overriding
   *  the original page's crop. */
  crop?: { x: number; y: number; width: number; height: number };
}

/**
 * Simulate the sequence of pageOps and return one ProjectedSlot per page in
 * the final ordering. Duplicates and moves preserve source identity so the
 * viewer/thumbnails can render a real preview; only true `insert-blank` ops
 * produce a `source: null` slot.
 */
export function projectPageOrderDetailed(
  pageOps: PageOp[],
  originalCount: number
): ProjectedSlot[] {
  const order: ProjectedSlot[] = [];
  for (let i = 0; i < originalCount; i++) order.push({ source: i, rotation: 0 });

  const findOriginalIdx = (origIdx: number): number =>
    order.findIndex((s) => s.source === origIdx);

  for (const op of pageOps) {
    if (op.kind === 'rotate') {
      // Apply to ALL slots derived from this original (covers duplicates).
      for (const s of order) {
        if (s.source === op.page) {
          s.rotation = ((s.rotation + (op.degrees ?? 90)) % 360 + 360) % 360;
        }
      }
    } else if (op.kind === 'crop' && op.crop) {
      for (const s of order) {
        if (s.source === op.page) {
          s.crop = { ...op.crop };
        }
      }
    } else if (op.kind === 'delete') {
      const idx = findOriginalIdx(op.page);
      if (idx < 0) continue;
      order.splice(idx, 1);
    } else if (op.kind === 'insert-blank') {
      const idx = findOriginalIdx(op.page);
      if (idx < 0) continue;
      order.splice(idx + 1, 0, { source: null, rotation: 0 });
    } else if (op.kind === 'duplicate') {
      const idx = findOriginalIdx(op.page);
      if (idx < 0) continue;
      const src = order[idx];
      order.splice(idx + 1, 0, {
        source: src.source,
        rotation: src.rotation,
        crop: src.crop ? { ...src.crop } : undefined
      });
    } else if (op.kind === 'move') {
      const idx = findOriginalIdx(op.page);
      const target = op.to ?? idx;
      if (idx < 0) continue;
      if (target === idx || target === idx + 1) continue;
      const [val] = order.splice(idx, 1);
      const adj = target > idx ? target - 1 : target;
      order.splice(adj, 0, val);
    }
  }
  return order;
}

/**
 * Legacy view of the projection: returns an array of original 0-based page
 * indices, with -1 for blank slots. Duplicates and moves keep their source
 * identity so thumbnails for duplicate pages render correctly.
 */
export function projectPageOrder(pageOps: PageOp[], originalCount: number): number[] {
  return projectPageOrderDetailed(pageOps, originalCount).map((s) =>
    s.source == null ? -1 : s.source
  );
}
