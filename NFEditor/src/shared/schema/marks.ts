// Custom Tiptap marks for NiteFlirt's inline vocabulary.
//
// Font (face/size/color) is ONE mark with three attributes, not three separate
// marks. ProseMirror's DOM parser applies only the first matching `tag` rule per
// element, so three `font[...]` mark rules on a single `<font size color face>`
// would drop two of them. One mark with attribute-level parseHTML captures all
// three from the same element. renderHTML here drives only the editor DOM (+
// partners parseHTML for import); EXPORT comes from src/shared/serialize.

import { Mark, mergeAttributes } from '@tiptap/core';
import { clampSize, cssFontSizeToNFSize } from '../fontSize';

export const Underline = Mark.create({
  name: 'underline',
  parseHTML() {
    return [{ tag: 'u' }, { style: 'text-decoration=underline' }];
  },
  renderHTML({ HTMLAttributes }) {
    return ['u', mergeAttributes(HTMLAttributes), 0];
  },
});

export const Font = Mark.create({
  name: 'font',
  addAttributes() {
    return {
      face: {
        default: null,
        parseHTML: (el) => el.getAttribute('face') || (el as HTMLElement).style?.fontFamily || null,
        renderHTML: (attrs) => (attrs.face ? { face: String(attrs.face) } : {}),
      },
      size: {
        default: null,
        parseHTML: (el) => {
          const s = el.getAttribute('size');
          if (s != null) return clampSize(parseInt(s, 10));
          const css = (el as HTMLElement).style?.fontSize;
          return css ? cssFontSizeToNFSize(css) : null;
        },
        renderHTML: (attrs) => (attrs.size ? { size: String(attrs.size) } : {}),
      },
      color: {
        default: null,
        parseHTML: (el) => el.getAttribute('color') || (el as HTMLElement).style?.color || null,
        renderHTML: (attrs) => (attrs.color ? { color: String(attrs.color) } : {}),
      },
    };
  },
  parseHTML() {
    return [
      { tag: 'font' },
      {
        tag: 'span[style]',
        getAttrs: (el) => {
          if (!(el instanceof HTMLElement)) return false;
          const s = el.style;
          // Only claim spans that actually carry font styling.
          return s && (s.fontFamily || s.fontSize || s.color) ? {} : false;
        },
      },
    ];
  },
  renderHTML({ HTMLAttributes }) {
    return ['font', mergeAttributes(HTMLAttributes), 0];
  },
});

// Simple presentational marks (allowlisted tags, no attributes).
const simpleMark = (name: string, tag: string) =>
  Mark.create({
    name,
    parseHTML() {
      return [{ tag }];
    },
    renderHTML({ HTMLAttributes }) {
      return [tag, mergeAttributes(HTMLAttributes), 0];
    },
  });

export const Superscript = simpleMark('superscript', 'sup');
export const Subscript = simpleMark('subscript', 'sub');
export const Small = simpleMark('small', 'small');
export const Big = simpleMark('big', 'big');
export const Highlight = simpleMark('highlight', 'mark');

export const CUSTOM_MARKS = [Underline, Font, Superscript, Subscript, Small, Big, Highlight];
