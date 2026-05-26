import { pickEncouragement } from './encouragements';

// Re-export for callers that want to pick once and reuse the string
// (e.g. for analytics or testing). The default `showEncouragement()`
// signature accepts an explicit string so tier-aware callers can
// pass in whichever bank they picked from.
export { pickEncouragement };

// Pretty floating toast shown at the top of the viewport when Sallie
// logs income. Imperative DOM (no React state) so it can be fired from
// any call site without restructuring App.tsx. Multiple consecutive
// triggers stack a fresh toast each time (the previous one finishes
// its own fade-out independently).

const ENTER_MS = 260;
const HOLD_MS = 2400;
const EXIT_MS = 360;

export function showEncouragement(text?: string): void {
  if (typeof document === 'undefined') return;
  // Backwards-compat: if no text is supplied, fall back to the
  // small/everyday bank — that's the closest match to the original
  // v1.18.5 vibe before tiering was introduced.
  const finalText = text ?? pickEncouragement('small');
  if (!finalText) return;

  const el = document.createElement('div');
  el.textContent = finalText;
  el.setAttribute('role', 'status');
  el.setAttribute('aria-live', 'polite');

  Object.assign(el.style, {
    position: 'fixed',
    top: '5rem',
    left: '50%',
    transform: 'translateX(-50%) translateY(-24px) scale(0.92)',
    zIndex: '9999',
    padding: '0.9rem 1.6rem',
    borderRadius: '999px',
    background:
      'linear-gradient(135deg, rgb(var(--persona-secondary)), rgb(var(--persona-tint)))',
    color: 'rgb(var(--persona-accent))',
    fontFamily: "'Caveat', 'Paper Daisy', cursive",
    fontSize: '1.9rem',
    fontWeight: '600',
    letterSpacing: '0.3px',
    boxShadow: '0 10px 30px -8px rgb(var(--persona-accent) / 0.55)',
    border: '1px solid rgb(var(--persona-primary) / 0.5)',
    opacity: '0',
    transition: `opacity ${ENTER_MS}ms ease, transform ${ENTER_MS}ms cubic-bezier(0.16, 1.1, 0.3, 1)`,
    pointerEvents: 'none',
    whiteSpace: 'nowrap',
    userSelect: 'none',
  } satisfies Partial<CSSStyleDeclaration>);

  document.body.appendChild(el);

  // Force a layout flush before the entrance animation so the browser
  // actually animates from the initial transform/opacity instead of
  // collapsing the change into the same frame as insertion.
  requestAnimationFrame(() => {
    el.style.opacity = '1';
    el.style.transform = 'translateX(-50%) translateY(0) scale(1)';
  });

  window.setTimeout(() => {
    el.style.transition = `opacity ${EXIT_MS}ms ease, transform ${EXIT_MS}ms ease`;
    el.style.opacity = '0';
    el.style.transform = 'translateX(-50%) translateY(-24px) scale(0.96)';
    window.setTimeout(() => el.remove(), EXIT_MS + 40);
  }, HOLD_MS);
}
