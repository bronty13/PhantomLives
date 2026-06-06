// Turn a Branding into CSS — the variables + @font-face used by the player and the
// creator's live preview, so both render identically.

import type { CSSProperties } from 'react';
import type { Branding } from './model';
import { resolveFont } from './fonts';

export interface BrandingCss {
  vars: Record<string, string>;
  fontFamily: string;
  faceCss: string;
}

export function brandingCss(branding: Branding): BrandingCss {
  const font = resolveFont(branding.font);
  const c = branding.colors;
  return {
    vars: {
      '--brand-primary': c.primary,
      '--brand-secondary': c.secondary,
      '--brand-accent': c.accent,
      '--brand-bg': c.bg,
      '--brand-text': c.text,
      '--brand-font': font.fontFamily,
    },
    fontFamily: font.fontFamily,
    faceCss: font.faceCss,
  };
}

/** Inline `style` string for a wrapping element (CSS custom properties). */
export function brandingStyleAttr(branding: Branding): CSSProperties {
  const { vars } = brandingCss(branding);
  return vars as unknown as CSSProperties;
}
