// Tracks attempts used per deployed quiz. localStorage can be unavailable under
// file:// (some mobile browsers), so everything is defensive with an in-memory fallback.

const memory = new Map<string, number>();

function key(quizId: string): string {
  return `quizzer-player:${quizId}:attempts`;
}

export function getAttemptsUsed(quizId: string): number {
  try {
    const raw = localStorage.getItem(key(quizId));
    if (raw != null) return parseInt(raw, 10) || 0;
  } catch {
    /* fall through to memory */
  }
  return memory.get(quizId) ?? 0;
}

export function recordAttempt(quizId: string): number {
  const used = getAttemptsUsed(quizId) + 1;
  memory.set(quizId, used);
  try {
    localStorage.setItem(key(quizId), String(used));
  } catch {
    /* in-memory only */
  }
  return used;
}
