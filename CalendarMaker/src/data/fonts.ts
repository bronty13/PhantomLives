// Font registry helpers. The same base64 TTF bytes power both the on-screen
// @font-face preview and jsPDF embedding, guaranteeing the PDF matches the design.

import type { jsPDF } from 'jspdf';
import type { FontKey } from '../model/types';
import { FONT_FILES } from './fonts-data';
import { FONT_REGISTRY, type EmbeddedFontMeta } from './fonts-registry';

export { FONT_REGISTRY };
export type { EmbeddedFontMeta };

const BY_KEY = new Map<string, EmbeddedFontMeta>(FONT_REGISTRY.map((f) => [f.key, f]));

export const DEFAULT_FONT_KEY: FontKey = FONT_REGISTRY[0]?.key ?? 'inter';

function meta(key: FontKey): EmbeddedFontMeta {
  return BY_KEY.get(key) ?? FONT_REGISTRY[0];
}

/** The unique CSS family name for a font key (e.g. 'CM Inter'). */
export function cssFamily(key: FontKey): string {
  return meta(key).cssFamily;
}

export function fontLabel(key: FontKey): string {
  return meta(key).label;
}

/** A CSS font-family value with a sensible system fallback by category. */
export function cssFontFamily(key: FontKey): string {
  const m = meta(key);
  const fallback =
    m.category === 'serif'
      ? 'Georgia, serif'
      : m.category === 'script' || m.category === 'handwriting' || m.category === 'display'
        ? 'cursive'
        : m.category === 'mono'
          ? 'monospace'
          : 'system-ui, sans-serif';
  return `'${m.cssFamily}', ${fallback}`;
}

/** All @font-face rules for the embedded fonts — inject once into a <style>. */
export function allFontFaceCss(): string {
  const rules: string[] = [];
  for (const m of FONT_REGISTRY) {
    const files = FONT_FILES[m.key] ?? {};
    for (const style of m.styles) {
      const b64 = files[style];
      if (!b64) continue;
      const weight = style.includes('bold') ? 700 : 400;
      const italic = style.includes('italic') ? 'italic' : 'normal';
      rules.push(
        `@font-face{font-family:'${m.cssFamily}';` +
          `src:url(data:font/ttf;base64,${b64}) format('truetype');` +
          `font-weight:${weight};font-style:${italic};font-display:swap;}`,
      );
    }
  }
  return rules.join('\n');
}

/**
 * Register every embedded font into a jsPDF doc. Each (family, style) becomes
 * callable via doc.setFont(cssFamily, 'normal'|'bold'). Families missing a bold
 * face get the normal bytes aliased to 'bold' so setFont never throws.
 */
export function registerFontsInDoc(doc: jsPDF): void {
  for (const m of FONT_REGISTRY) {
    const files = FONT_FILES[m.key] ?? {};
    const normal = files['normal'];
    const bold = files['bold'] ?? normal;
    if (normal) {
      doc.addFileToVFS(`${m.key}-normal.ttf`, normal);
      doc.addFont(`${m.key}-normal.ttf`, m.cssFamily, 'normal');
    }
    if (bold) {
      doc.addFileToVFS(`${m.key}-bold.ttf`, bold);
      doc.addFont(`${m.key}-bold.ttf`, m.cssFamily, 'bold');
    }
  }
}

/** Set the active jsPDF font for a key + weight. */
export function setPdfFont(doc: jsPDF, key: FontKey, bold = false): void {
  doc.setFont(cssFamily(key), bold ? 'bold' : 'normal');
}
