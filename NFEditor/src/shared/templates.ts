// Starter templates (doc JSON) to cut time-to-first-listing. These are plain
// ProseMirror documents in NFEditor's schema, so they round-trip and serialize
// like any authored content. Keep them tasteful and structurally varied (a
// profile, a promo listing, a two-column table) so they double as worked examples.

import type { DocNode, DocType } from './model';

export interface StarterTemplate {
  id: string;
  name: string;
  docType: DocType;
  description: string;
  content: DocNode;
}

const t = (text: string, marks?: DocNode['marks']): DocNode => ({ type: 'text', text, marks });

export const TEMPLATES: StarterTemplate[] = [
  {
    id: 'simple-profile',
    name: 'Simple Profile',
    docType: 'profile',
    description: 'A clean Flirt Profile: bold colored intro, a divider, and a tidy list.',
    content: {
      type: 'doc',
      content: [
        {
          type: 'heading',
          attrs: { level: 2, color: '#c2185b', align: 'center' },
          content: [t('Welcome, sweetie')],
        },
        {
          type: 'paragraph',
          attrs: { align: 'center' },
          content: [
            t('Call me for ', [{ type: 'font', attrs: { size: 4 } }]),
            t('warm, wicked conversation', [
              { type: 'font', attrs: { size: 4, color: '#c2185b' } },
              { type: 'bold' },
            ]),
            t(' any time.', [{ type: 'font', attrs: { size: 4 } }]),
          ],
        },
        { type: 'horizontalRule' },
        {
          type: 'paragraph',
          content: [t('My favorite things:', [{ type: 'bold' }])],
        },
        {
          type: 'bulletList',
          content: [
            { type: 'listItem', content: [{ type: 'paragraph', content: [t('Long, teasing calls')] }] },
            { type: 'listItem', content: [{ type: 'paragraph', content: [t('Spoiling and tributes')] }] },
            { type: 'listItem', content: [{ type: 'paragraph', content: [t('Getting to know you')] }] },
          ],
        },
      ],
    },
  },
  {
    id: 'goody-promo',
    name: 'Listing — Goody promo',
    docType: 'listing',
    description: 'A boxed promo section with a headline, photo, copy, and a Goody button.',
    content: {
      type: 'doc',
      content: [
        {
          type: 'section',
          attrs: { width: 800, bgColor: '#fff0f5', align: 'center', padding: 16 },
          content: [
            {
              type: 'heading',
              attrs: { level: 3, color: '#ad1457', align: 'center' },
              content: [t('New Goody just for you')],
            },
            {
              type: 'image',
              attrs: { src: 'https://example.com/your-photo.jpg', alt: 'Preview', width: 300, align: 'center' },
            },
            {
              type: 'paragraph',
              attrs: { align: 'center' },
              content: [t('A little something to make you smile. Tap below to unlock it.')],
            },
            {
              type: 'goodyButton',
              attrs: {
                url: 'https://www.niteflirt.com/goodies/your-goody',
                imageUrl: 'https://example.com/buy-now-button.png',
                label: 'Buy my Goody',
              },
            },
          ],
        },
      ],
    },
  },
  {
    id: 'two-column',
    name: 'Two-column table',
    docType: 'listing',
    description: 'A legacy table layout — renders consistently on older mobile browsers.',
    content: {
      type: 'doc',
      content: [
        {
          type: 'section',
          attrs: { width: 800, align: 'center', padding: 8 },
          content: [
            {
              type: 'heading',
              attrs: { level: 3, align: 'center', color: '#6a1b9a' },
              content: [t('What I offer')],
            },
            {
              type: 'paragraph',
              content: [
                t('Rates, availability, and a little about me. ', []),
                t('Edit this box', [{ type: 'italic' }]),
                t(' or switch to compact mode in the toolbar.'),
              ],
            },
          ],
        },
      ],
    },
  },
];

export function templateById(id: string): StarterTemplate | undefined {
  return TEMPLATES.find((x) => x.id === id);
}
