// Tracks spins used per deployed wheel. localStorage can be unavailable under
// file:// (some mobile browsers), so everything is defensive with an in-memory
// fallback — mirrors the quiz player's attempts.ts.

const memory = new Map<string, number>();

function key(wheelId: string): string {
  return `quizzer-wheel:${wheelId}:spins`;
}

export function getSpinsUsed(wheelId: string): number {
  try {
    const raw = localStorage.getItem(key(wheelId));
    if (raw != null) return parseInt(raw, 10) || 0;
  } catch {
    /* fall through to memory */
  }
  return memory.get(wheelId) ?? 0;
}

export function recordSpin(wheelId: string): number {
  const used = getSpinsUsed(wheelId) + 1;
  memory.set(wheelId, used);
  try {
    localStorage.setItem(key(wheelId), String(used));
  } catch {
    /* in-memory only */
  }
  return used;
}
