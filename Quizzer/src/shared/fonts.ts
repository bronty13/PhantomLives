// Font handling.
//
// Built-in fonts use curated cross-platform font stacks (offline, zero-weight).
// Uploaded TTFs are embedded as base64 @font-face for pixel-identical rendering on
// any device. NOTE (v0.1.0): built-ins fall back to the device's nearest system
// font rather than shipping ~10 base64 webfaces in every quiz; a uploaded TTF is
// the path to guaranteed-consistent branding. See README "Fonts".

import type { BuiltinFontName, FontChoice } from './model';
import { resolveAsset } from './assets';

interface BuiltinFontDef {
  stack: string;
  category: 'sans' | 'serif' | 'mono';
}

export const BUILTIN_FONTS: Record<BuiltinFontName, BuiltinFontDef> = {
  Inter: { stack: "'Inter', system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif", category: 'sans' },
  Lora: { stack: "'Lora', Georgia, 'Times New Roman', serif", category: 'serif' },
  Roboto: { stack: "'Roboto', system-ui, 'Segoe UI', Arial, sans-serif", category: 'sans' },
  Merriweather: { stack: "'Merriweather', Georgia, 'Times New Roman', serif", category: 'serif' },
  Montserrat: { stack: "'Montserrat', 'Segoe UI', system-ui, sans-serif", category: 'sans' },
  'Open Sans': { stack: "'Open Sans', system-ui, 'Segoe UI', Arial, sans-serif", category: 'sans' },
  'Playfair Display': { stack: "'Playfair Display', Georgia, 'Times New Roman', serif", category: 'serif' },
  'Source Serif 4': { stack: "'Source Serif 4', Georgia, serif", category: 'serif' },
  Nunito: { stack: "'Nunito', system-ui, 'Segoe UI', sans-serif", category: 'sans' },
  'JetBrains Mono': { stack: "'JetBrains Mono', ui-monospace, 'SF Mono', Menlo, monospace", category: 'mono' },
};

export interface ResolvedFont {
  /** Value for CSS `font-family`. */
  fontFamily: string;
  /** A `@font-face` rule to inject, or '' when a system stack is used. */
  faceCss: string;
}

export function resolveFont(font: FontChoice): ResolvedFont {
  if (font.kind === 'builtin') {
    return { fontFamily: BUILTIN_FONTS[font.family].stack, faceCss: '' };
  }
  const src = resolveAsset(font.ttf);
  const family = font.family.replace(/['"\\]/g, '');
  const faceCss = src
    ? `@font-face{font-family:'${family}';src:url('${src}') format('truetype');font-display:swap;}`
    : '';
  return { fontFamily: `'${family}', system-ui, sans-serif`, faceCss };
}
