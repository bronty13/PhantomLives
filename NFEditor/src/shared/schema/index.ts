// Assemble the full editor schema: StarterKit (trimmed to NiteFlirt's vocabulary)
// + global block attributes (align/color) + Link + our custom marks and nodes.
// buildExtensions() is the single source the editor instantiates from.

import { Extension } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import Link from '@tiptap/extension-link';
import { CUSTOM_MARKS } from './marks';
import { CUSTOM_NODES } from './nodes';
import type { DocNode } from '../model';

// Add `align` to paragraphs/headings and `color` to headings. These render as
// inline style in the editor DOM; the exporter reads the attrs directly.
const BlockAttrs = Extension.create({
  name: 'nfBlockAttrs',
  addGlobalAttributes() {
    return [
      {
        types: ['paragraph', 'heading'],
        attributes: {
          align: {
            default: null,
            parseHTML: (el) => el.getAttribute('align') || (el as HTMLElement).style?.textAlign || null,
            renderHTML: (attrs) => (attrs.align ? { style: `text-align:${attrs.align}` } : {}),
          },
        },
      },
      {
        types: ['heading'],
        attributes: {
          color: {
            default: null,
            parseHTML: (el) => el.getAttribute('color') || (el as HTMLElement).style?.color || null,
            renderHTML: (attrs) => (attrs.color ? { style: `color:${attrs.color}` } : {}),
          },
        },
      },
    ];
  },
});

export function buildExtensions() {
  return [
    StarterKit.configure({
      heading: { levels: [1, 2, 3, 4, 5, 6] },
      // Not in NiteFlirt's authoring vocabulary (or unhandled by the serializer).
      blockquote: false,
      code: false,
      codeBlock: false,
      // We provide our own underline + strike stays from StarterKit.
    }),
    BlockAttrs,
    Link.configure({ openOnClick: false, autolink: false }),
    ...CUSTOM_MARKS,
    ...CUSTOM_NODES,
  ];
}

/** An empty document. */
export function emptyDoc(): DocNode {
  return { type: 'doc', content: [{ type: 'paragraph' }] };
}
