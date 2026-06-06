// Tracks spins used per deployed wheel. localStorage can be unavailable under
// file:// (some mobile browsers), so everything is defensive with an in-memory
// fallback — mirrors the quiz player's attempts.ts.

const memory = new Map<string, number>();

// Scope by wheel id AND the deploy token (generatedAt) so a re-deployed wheel starts
// fresh, while a single deployed file still counts spins across refreshes.
function key(wheelId: string, token: string): string {
  return `quizzer-wheel:${wheelId}:${token}:spins`;
}

export function getSpinsUsed(wheelId: string, token: string): number {
  const k = key(wheelId, token);
  try {
    const raw = localStorage.getItem(k);
    if (raw != null) return parseInt(raw, 10) || 0;
  } catch {
    /* fall through to memory */
  }
  return memory.get(k) ?? 0;
}

export function recordSpin(wheelId: string, token: string): number {
  const k = key(wheelId, token);
  const used = getSpinsUsed(wheelId, token) + 1;
  memory.set(k, used);
  try {
    localStorage.setItem(k, String(used));
  } catch {
    /* in-memory only */
  }
  return used;
}
