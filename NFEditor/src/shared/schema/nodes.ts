// Custom Tiptap nodes for NiteFlirt's block vocabulary. As with marks, renderHTML
// here is only the editor's internal DOM (+ partner to parseHTML for import); the
// exported HTML is produced by src/shared/serialize. The schema IS the structural
// allowlist: there is no iframe/script node, so those can't exist in a document.

import { Node, mergeAttributes } from '@tiptap/core';
import { classifyNfButton, isNiteFlirtUrl } from '../import/buttonPatterns';

function parsePx(v: string | null | undefined): number | null {
  if (!v) return null;
  const m = String(v).match(/(-?\d*\.?\d+)/);
  return m ? Math.round(parseFloat(m[1])) : null;
}

// ---- Image (block atom; optional external link via `href`) -----------------

export const Image = Node.create({
  name: 'image',
  group: 'block',
  atom: true,
  draggable: true,
  addAttributes() {
    return {
      src: { default: '' },
      alt: { default: null },
      width: { default: null },
      height: { default: null },
      title: { default: null },
      align: { default: null, renderHTML: () => ({}) },
      href: { default: null, renderHTML: () => ({}) },
    };
  },
  parseHTML() {
    return [
      {
        tag: 'img[src]',
        getAttrs: (el) => {
          if (!(el instanceof HTMLElement)) return {};
          const parent = el.parentElement;
          const href =
            parent && parent.tagName === 'A' && !isNiteFlirtUrl(parent.getAttribute('href') || '')
              ? parent.getAttribute('href')
              : null;
          return { href };
        },
      },
    ];
  },
  renderHTML({ node }) {
    const a = node.attrs;
    const img = ['img', mergeAttributes({ src: a.src, alt: a.alt, width: a.width, height: a.height, title: a.title })];
    return a.href ? ['a', { href: a.href }, img] : (img as never);
  },
});

// ---- Payment buttons (block atoms) -----------------------------------------

function buttonNode(name: string, type: 'goodyButton' | 'tributeButton' | 'flirtButton') {
  return Node.create({
    name,
    group: 'block',
    atom: true,
    draggable: true,
    addAttributes() {
      return {
        url: { default: '' },
        imageUrl: { default: '' },
        label: { default: '' },
        width: { default: null },
        height: { default: null },
      };
    },
    parseHTML() {
      return [
        {
          tag: 'a',
          priority: 100,
          getAttrs: (el) => {
            if (!(el instanceof HTMLElement)) return false;
            const img = el.querySelector('img');
            const href = el.getAttribute('href') || '';
            if (!img) return false;
            if (classifyNfButton(href) !== type) return false;
            return {
              url: href,
              imageUrl: img.getAttribute('src') || '',
              label: img.getAttribute('alt') || '',
              width: img.getAttribute('width'),
              height: img.getAttribute('height'),
            };
          },
        },
      ];
    },
    renderHTML({ node }) {
      const a = node.attrs;
      return [
        'a',
        { href: a.url, 'data-nf-button': type },
        ['img', mergeAttributes({ src: a.imageUrl, alt: a.label, width: a.width, height: a.height })],
      ];
    },
  });
}

export const GoodyButton = buttonNode('goodyButton', 'goodyButton');
export const TributeButton = buttonNode('tributeButton', 'tributeButton');
export const FlirtButton = buttonNode('flirtButton', 'flirtButton');

// ---- Wishlist link (authoring node; text or image link) --------------------

export const WishlistLink = Node.create({
  name: 'wishlistLink',
  group: 'block',
  atom: true,
  draggable: true,
  addAttributes() {
    return {
      url: { default: '' },
      label: { default: 'My Wishlist' },
      imageUrl: { default: null },
    };
  },
  renderHTML({ node }) {
    const a = node.attrs;
    return a.imageUrl
      ? ['a', { href: a.url }, ['img', { src: a.imageUrl, alt: a.label }]]
      : ['a', { href: a.url }, a.label];
  },
});

// ---- Section / Container (block; <div> or <table> at serialize time) --------

export const Section = Node.create({
  name: 'section',
  group: 'block',
  content: 'block+',
  defining: true,
  addAttributes() {
    return {
      width: { default: null, renderHTML: () => ({}) },
      bgColor: { default: null, renderHTML: () => ({}) },
      align: { default: null, renderHTML: () => ({}) },
      padding: { default: null, renderHTML: () => ({}) },
    };
  },
  parseHTML() {
    return [
      {
        tag: 'div',
        getAttrs: (el) => {
          if (!(el instanceof HTMLElement)) return {};
          const s = el.style;
          return {
            width: parsePx(s.width),
            bgColor: s.backgroundColor || null,
            align: s.textAlign || null,
            padding: parsePx(s.padding),
          };
        },
      },
      {
        tag: 'table',
        getAttrs: (el) => {
          if (!(el instanceof HTMLElement)) return {};
          return {
            width: parsePx(el.getAttribute('width')),
            bgColor: el.getAttribute('bgcolor'),
            align: el.getAttribute('align'),
            padding: parsePx(el.getAttribute('cellpadding')),
          };
        },
        contentElement: (el) => (el as HTMLElement).querySelector('td') || (el as HTMLElement),
      },
    ];
  },
  renderHTML({ node }) {
    const a = node.attrs;
    const styles: string[] = [];
    if (a.width) styles.push(`width:${a.width}px`);
    if (a.bgColor) styles.push(`background-color:${a.bgColor}`);
    if (a.align) styles.push(`text-align:${a.align}`);
    if (a.padding != null) styles.push(`padding:${a.padding}px`);
    return ['div', mergeAttributes({ class: 'nf-section', style: styles.join(';') || undefined }), 0];
  },
});

// ---- Video (block atom; self-hosted only, never iframe) --------------------

export const Video = Node.create({
  name: 'video',
  group: 'block',
  atom: true,
  draggable: true,
  addAttributes() {
    return {
      src: { default: '' },
      poster: { default: null },
      width: { default: null },
      height: { default: null },
      controls: { default: true },
      autoplay: { default: false },
      loop: { default: false },
      muted: { default: false },
    };
  },
  parseHTML() {
    return [{ tag: 'video' }];
  },
  renderHTML({ node }) {
    const a = node.attrs;
    return [
      'video',
      mergeAttributes({
        src: a.src,
        poster: a.poster,
        width: a.width,
        height: a.height,
        controls: a.controls ? 'controls' : undefined,
      }),
    ];
  },
});

// ---- Image map (block atom; <img usemap> + <map>/<area>) --------------------

export const ImageMap = Node.create({
  name: 'imageMap',
  group: 'block',
  atom: true,
  draggable: true,
  addAttributes() {
    return {
      src: { default: '' },
      width: { default: null },
      height: { default: null },
      mapName: { default: 'nfmap' },
      areas: { default: [] as Array<Record<string, string | null>> },
    };
  },
  parseHTML() {
    return [
      {
        tag: 'img[usemap]',
        priority: 110,
        getAttrs: (el) => {
          if (!(el instanceof HTMLElement)) return {};
          const name = (el.getAttribute('usemap') || '').replace('#', '');
          const map = el.ownerDocument?.querySelector(`map[name="${CSS.escape(name)}"]`);
          const areas = map
            ? Array.from(map.querySelectorAll('area')).map((ar) => ({
                shape: ar.getAttribute('shape'),
                coords: ar.getAttribute('coords'),
                href: ar.getAttribute('href'),
                alt: ar.getAttribute('alt'),
              }))
            : [];
          return {
            src: el.getAttribute('src'),
            width: el.getAttribute('width'),
            height: el.getAttribute('height'),
            mapName: name || 'nfmap',
            areas,
          };
        },
      },
    ];
  },
  renderHTML({ node }) {
    const a = node.attrs;
    return ['img', mergeAttributes({ src: a.src, width: a.width, height: a.height, 'data-nf-imagemap': a.mapName })];
  },
});

// ---- Marquee ----------------------------------------------------------------

export const Marquee = Node.create({
  name: 'marquee',
  group: 'block',
  content: 'inline*',
  addAttributes() {
    return {
      direction: { default: null },
      behavior: { default: null },
      scrollamount: { default: null },
    };
  },
  parseHTML() {
    return [{ tag: 'marquee' }];
  },
  renderHTML({ HTMLAttributes }) {
    return ['marquee', mergeAttributes(HTMLAttributes), 0];
  },
});

// ---- Details / Summary ------------------------------------------------------

export const Details = Node.create({
  name: 'details',
  group: 'block',
  content: 'summary block+',
  defining: true,
  addAttributes() {
    return { open: { default: false, renderHTML: (attrs) => (attrs.open ? { open: 'open' } : {}) } };
  },
  parseHTML() {
    return [{ tag: 'details' }];
  },
  renderHTML({ HTMLAttributes }) {
    return ['details', mergeAttributes(HTMLAttributes), 0];
  },
});

export const Summary = Node.create({
  name: 'summary',
  content: 'inline*',
  defining: true,
  parseHTML() {
    return [{ tag: 'summary' }];
  },
  renderHTML() {
    return ['summary', 0];
  },
});

export const CUSTOM_NODES = [
  Image,
  GoodyButton,
  TributeButton,
  FlirtButton,
  WishlistLink,
  Section,
  Video,
  ImageMap,
  Marquee,
  Details,
  Summary,
];
