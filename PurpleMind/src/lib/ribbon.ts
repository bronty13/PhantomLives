// Build a filled, tapered "ribbon" SVG path between two points along a cubic
// bezier — thick (w0) at the source end, thin (w1) at the target end — for the
// organic MindNode-style branch connectors. Pure geometry, unit-testable.

export interface RibbonInput {
  sx: number;
  sy: number;
  tx: number;
  ty: number;
  /** Full width at the source (parent) end, in px. */
  w0: number;
  /** Full width at the target (child) end, in px. */
  w1: number;
  /** Bezier samples (higher = smoother). */
  samples?: number;
}

interface P {
  x: number;
  y: number;
}

const r = (n: number) => Math.round(n * 100) / 100;

export function taperedRibbonPath(i: RibbonInput): string {
  const samples = Math.max(6, i.samples ?? 24);
  // Horizontal-biased control points that follow the flow direction, so a
  // left-flowing connector (target left of source) bows leftward rather than
  // bulging the wrong way.
  const k = (i.tx - i.sx) * 0.5;
  const sgn = k >= 0 ? 1 : -1;
  const mag = Math.max(40, Math.abs(k));
  const c1x = i.sx + sgn * mag;
  const c1y = i.sy;
  const c2x = i.tx - sgn * mag;
  const c2y = i.ty;

  const at = (t: number): P => {
    const u = 1 - t;
    return {
      x: u * u * u * i.sx + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t * i.tx,
      y: u * u * u * i.sy + 3 * u * u * t * c1y + 3 * u * t * t * c2y + t * t * t * i.ty,
    };
  };
  const deriv = (t: number): P => {
    const u = 1 - t;
    return {
      x: 3 * u * u * (c1x - i.sx) + 6 * u * t * (c2x - c1x) + 3 * t * t * (i.tx - c2x),
      y: 3 * u * u * (c1y - i.sy) + 6 * u * t * (c2y - c1y) + 3 * t * t * (i.ty - c2y),
    };
  };

  const top: P[] = [];
  const bot: P[] = [];
  for (let s = 0; s <= samples; s++) {
    const t = s / samples;
    const p = at(t);
    const d = deriv(t);
    const len = Math.hypot(d.x, d.y) || 1;
    const nx = -d.y / len;
    const ny = d.x / len;
    const halfW = (i.w0 + (i.w1 - i.w0) * t) / 2;
    top.push({ x: p.x + nx * halfW, y: p.y + ny * halfW });
    bot.push({ x: p.x - nx * halfW, y: p.y - ny * halfW });
  }

  const cmds: string[] = [`M ${r(top[0].x)} ${r(top[0].y)}`];
  for (let k = 1; k < top.length; k++) cmds.push(`L ${r(top[k].x)} ${r(top[k].y)}`);
  for (let k = bot.length - 1; k >= 0; k--) cmds.push(`L ${r(bot[k].x)} ${r(bot[k].y)}`);
  cmds.push('Z');
  return cmds.join(' ');
}
