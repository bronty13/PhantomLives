// Pure drag-reorder splice math, extracted from KinkChipPicker so it can
// be unit-tested without a DOM. The semantics match MasterClipper's
// CategoryChipPicker.swift "drop before target" behavior:
//   - dragging an earlier item onto a later one moves it just BEFORE the target
//   - dragging a later item onto an earlier one also moves it just BEFORE the target
// When src is before dst, the splice removes the source first which shifts
// dst down by one; the insert index compensates.

export function reorderBeforeTarget<T>(
  items: T[],
  identifies: (item: T) => string | number,
  srcId: string | number,
  targetId: string | number,
): T[] {
  if (srcId === targetId) return items;
  const srcIdx = items.findIndex((it) => identifies(it) === srcId);
  const dstIdx = items.findIndex((it) => identifies(it) === targetId);
  if (srcIdx < 0 || dstIdx < 0) return items;
  const next = items.slice();
  const [moved] = next.splice(srcIdx, 1);
  const insertAt = srcIdx < dstIdx ? dstIdx - 1 : dstIdx;
  next.splice(insertAt, 0, moved);
  return next;
}
