import { useState } from 'react';
import { Modal } from '../components/Modal';
import type { DocNode } from '../../shared/model';

export type InsertKind =
  | 'image'
  | 'goodyButton'
  | 'tributeButton'
  | 'flirtButton'
  | 'wishlistLink'
  | 'section'
  | 'video'
  | 'imageMap';

interface Field {
  key: string;
  label: string;
  placeholder?: string;
  kind?: 'text' | 'number' | 'color';
}

const SPECS: Record<InsertKind, { title: string; fields: Field[]; build: (v: Record<string, string>) => DocNode }> = {
  image: {
    title: 'Insert image',
    fields: [
      { key: 'src', label: 'Image URL', placeholder: 'https://host/photo.jpg' },
      { key: 'alt', label: 'Alt text' },
      { key: 'width', label: 'Width (px)', kind: 'number' },
      { key: 'href', label: 'Link URL (optional)' },
      { key: 'align', label: 'Align (left/center/right)' },
    ],
    build: (v) => ({
      type: 'image',
      attrs: {
        src: v.src,
        alt: v.alt || null,
        width: num(v.width),
        href: v.href || null,
        align: v.align || null,
      },
    }),
  },
  goodyButton: payment('Insert Goody / Pay-to-View button', 'goodyButton'),
  tributeButton: payment('Insert Tribute / Payment button', 'tributeButton'),
  flirtButton: payment('Insert Flirt (call) button', 'flirtButton'),
  wishlistLink: {
    title: 'Insert wishlist link',
    fields: [
      { key: 'url', label: 'Wishlist URL', placeholder: 'https://www.amazon.com/...' },
      { key: 'label', label: 'Link text' },
      { key: 'imageUrl', label: 'Button image URL (optional)' },
    ],
    build: (v) => ({
      type: 'wishlistLink',
      attrs: { url: v.url, label: v.label || 'My Wishlist', imageUrl: v.imageUrl || null },
    }),
  },
  section: {
    title: 'Insert section / box',
    fields: [
      { key: 'width', label: 'Width (px)', kind: 'number', placeholder: '800' },
      { key: 'bgColor', label: 'Background color', kind: 'color' },
      { key: 'align', label: 'Align (left/center/right)' },
      { key: 'padding', label: 'Padding (px)', kind: 'number' },
    ],
    build: (v) => ({
      type: 'section',
      attrs: { width: num(v.width), bgColor: v.bgColor || null, align: v.align || null, padding: num(v.padding) },
      content: [{ type: 'paragraph' }],
    }),
  },
  video: {
    title: 'Insert video (self-hosted — no iframe embeds)',
    fields: [
      { key: 'src', label: 'Video URL (.mp4)', placeholder: 'https://host/clip.mp4' },
      { key: 'width', label: 'Width (px)', kind: 'number' },
    ],
    build: (v) => ({ type: 'video', attrs: { src: v.src, width: num(v.width), controls: true } }),
  },
  imageMap: {
    title: 'Insert image map (one clickable area)',
    fields: [
      { key: 'src', label: 'Image URL' },
      { key: 'width', label: 'Width (px)', kind: 'number' },
      { key: 'height', label: 'Height (px)', kind: 'number' },
      { key: 'coords', label: 'Area coords (x1,y1,x2,y2)', placeholder: '0,0,100,100' },
      { key: 'href', label: 'Area link URL' },
    ],
    build: (v) => ({
      type: 'imageMap',
      attrs: {
        src: v.src,
        width: num(v.width),
        height: num(v.height),
        mapName: 'nfmap' + Math.floor(Math.random() * 1e6),
        areas: v.coords && v.href ? [{ shape: 'rect', coords: v.coords, href: v.href, alt: null }] : [],
      },
    }),
  },
};

function payment(title: string, type: string) {
  return {
    title,
    fields: [
      { key: 'url', label: 'Button link (paste from NiteFlirt)', placeholder: 'https://www.niteflirt.com/...' },
      { key: 'imageUrl', label: 'Button image URL' },
      { key: 'label', label: 'Label / alt text' },
      { key: 'width', label: 'Width (px)', kind: 'number' as const },
    ],
    build: (v: Record<string, string>): DocNode => ({
      type,
      attrs: { url: v.url, imageUrl: v.imageUrl, label: v.label || '', width: num(v.width) },
    }),
  };
}

function num(s: string | undefined): number | null {
  if (!s) return null;
  const n = parseInt(s, 10);
  return Number.isFinite(n) ? n : null;
}

export function InsertDialog({
  kind,
  onInsert,
  onClose,
}: {
  kind: InsertKind;
  onInsert: (node: DocNode) => void;
  onClose: () => void;
}) {
  const spec = SPECS[kind];
  const [vals, setVals] = useState<Record<string, string>>({});
  return (
    <Modal
      title={spec.title}
      onClose={onClose}
      footer={
        <>
          <button className="ghost" onClick={onClose}>
            Cancel
          </button>
          <button className="primary" onClick={() => onInsert(spec.build(vals))}>
            Insert
          </button>
        </>
      }
    >
      <div className="form">
        {spec.fields.map((f) => (
          <label key={f.key} className="field">
            <span>{f.label}</span>
            <input
              type={f.kind === 'color' ? 'color' : f.kind === 'number' ? 'number' : 'text'}
              placeholder={f.placeholder}
              value={vals[f.key] ?? (f.kind === 'color' ? '#ffffff' : '')}
              onChange={(e) => setVals((s) => ({ ...s, [f.key]: e.target.value }))}
            />
          </label>
        ))}
      </div>
    </Modal>
  );
}
