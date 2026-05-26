// Imperative DOM "+$X" flourish for income celebrations. Mirrors the
// pattern in `lib/encouragementToast.ts` — no React state, no portal,
// just `document.body.appendChild`. Tier 5 also pulses a soft full-
// viewport overlay; emojis are spawned per tier and drift up with a
// random horizontal nudge so they don't look stamped.

export type CelebrationTier = 1 | 2 | 3 | 4 | 5;

export function showFloatingMoney(opts: {
  amountDollars: number;
  tier: CelebrationTier;
  emojis?: readonly string[];
}): void {
  if (typeof document === 'undefined') return;
  const { amountDollars, tier, emojis = [] } = opts;
  const baseLeft = Math.round(window.innerWidth / 2 + (Math.random() * 200 - 100));
  const baseTop = Math.round(window.innerHeight * 0.45);

  spawnPill(amountDollars, tier, baseLeft, baseTop);
  for (let i = 0; i < emojis.length; i++) {
    spawnEmoji(emojis[i], baseLeft, baseTop, i, emojis.length);
  }
  if (tier === 5) {
    spawnScreenFlash();
  }
}

function spawnPill(amountDollars: number, tier: CelebrationTier, left: number, top: number) {
  const fontSize = tier <= 2 ? '1.6rem' : tier === 3 ? '2.2rem' : tier === 4 ? '2.8rem' : '3.6rem';
  const padding = tier <= 2 ? '0.4rem 0.9rem' : '0.6rem 1.2rem';
  const driftMs = tier === 5 ? 2200 : 1500;
  const driftPx = tier === 5 ? 140 : 80;
  const formatted = `+$${amountDollars.toFixed(amountDollars >= 1000 ? 0 : 2)}`;

  const el = document.createElement('div');
  el.textContent = formatted;
  el.setAttribute('aria-hidden', 'true');
  Object.assign(el.style, {
    position: 'fixed',
    left: `${left}px`,
    top: `${top}px`,
    transform: 'translate(-50%, -50%) scale(0.6)',
    zIndex: '9998',
    padding,
    borderRadius: '999px',
    background: 'linear-gradient(135deg, rgb(var(--persona-accent)), rgb(var(--persona-primary)))',
    color: 'white',
    fontFamily: "'Caveat', 'Paper Daisy', cursive",
    fontSize,
    fontWeight: '700',
    letterSpacing: '0.5px',
    boxShadow: '0 12px 28px -8px rgb(var(--persona-accent) / 0.6)',
    border: '1px solid rgb(255 255 255 / 0.5)',
    opacity: '0',
    pointerEvents: 'none',
    whiteSpace: 'nowrap',
    userSelect: 'none',
    transition: `opacity 200ms ease, transform ${driftMs}ms cubic-bezier(0.16, 1.0, 0.3, 1)`,
  } satisfies Partial<CSSStyleDeclaration>);
  document.body.appendChild(el);

  requestAnimationFrame(() => {
    el.style.opacity = '1';
    el.style.transform = `translate(-50%, -50%) translateY(-${driftPx}px) scale(1)`;
    window.setTimeout(() => {
      el.style.transition = `opacity 360ms ease, transform 360ms ease`;
      el.style.opacity = '0';
    }, driftMs - 360);
  });
  window.setTimeout(() => el.remove(), driftMs + 80);
}

function spawnEmoji(emoji: string, baseLeft: number, baseTop: number, idx: number, total: number) {
  const angleFromCenter = (idx / total) * Math.PI * 2;
  const radius = 60 + Math.random() * 40;
  const startLeft = Math.round(baseLeft + Math.cos(angleFromCenter) * radius);
  const startTop = Math.round(baseTop + Math.sin(angleFromCenter) * radius);
  const driftMs = 1800 + Math.random() * 600;
  const horizDrift = Math.round((Math.random() * 120) - 60);
  const vertDrift = -(140 + Math.round(Math.random() * 80));

  const el = document.createElement('div');
  el.textContent = emoji;
  el.setAttribute('aria-hidden', 'true');
  Object.assign(el.style, {
    position: 'fixed',
    left: `${startLeft}px`,
    top: `${startTop}px`,
    transform: 'translate(-50%, -50%) scale(0.5) rotate(0deg)',
    zIndex: '9997',
    fontSize: '2rem',
    opacity: '0',
    pointerEvents: 'none',
    userSelect: 'none',
    transition: `opacity 200ms ease, transform ${driftMs}ms cubic-bezier(0.16, 1.0, 0.3, 1)`,
  } satisfies Partial<CSSStyleDeclaration>);
  document.body.appendChild(el);

  const rotation = Math.round((Math.random() * 60) - 30);
  requestAnimationFrame(() => {
    el.style.opacity = '1';
    el.style.transform = `translate(-50%, -50%) translate(${horizDrift}px, ${vertDrift}px) scale(1.3) rotate(${rotation}deg)`;
    window.setTimeout(() => {
      el.style.transition = `opacity 400ms ease`;
      el.style.opacity = '0';
    }, driftMs - 400);
  });
  window.setTimeout(() => el.remove(), driftMs + 80);
}

function spawnScreenFlash() {
  const el = document.createElement('div');
  el.setAttribute('aria-hidden', 'true');
  Object.assign(el.style, {
    position: 'fixed',
    inset: '0',
    zIndex: '9996',
    background:
      'radial-gradient(circle at center, rgb(var(--persona-primary) / 0.55), rgb(var(--persona-primary) / 0))',
    opacity: '0',
    pointerEvents: 'none',
    transition: 'opacity 80ms ease',
  } satisfies Partial<CSSStyleDeclaration>);
  document.body.appendChild(el);
  requestAnimationFrame(() => {
    el.style.opacity = '1';
    window.setTimeout(() => {
      el.style.transition = 'opacity 480ms ease';
      el.style.opacity = '0';
    }, 90);
  });
  window.setTimeout(() => el.remove(), 700);
}
