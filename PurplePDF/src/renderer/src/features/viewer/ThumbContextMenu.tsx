import { useEffect, useRef, useState } from 'react';

export type ThumbAction =
  | 'delete'
  | 'rotate-cw'
  | 'rotate-ccw'
  | 'duplicate'
  | 'insert-blank'
  | 'extract';

interface Props {
  /** 1-based page number that was right-clicked. */
  pageNumber: number;
  /** Viewport-relative coordinates where the menu should appear. */
  x: number;
  y: number;
  onAction: (action: ThumbAction, pageNumber: number) => void;
  onClose: () => void;
}

/** Floating context menu used by the Thumbnails sidebar. */
export default function ThumbContextMenu({
  pageNumber,
  x,
  y,
  onAction,
  onClose
}: Props): JSX.Element {
  const ref = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ left: number; top: number }>({ left: x, top: y });

  // Clamp to viewport once mounted.
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    let left = x;
    let top = y;
    const margin = 8;
    if (left + r.width + margin > window.innerWidth) left = window.innerWidth - r.width - margin;
    if (top + r.height + margin > window.innerHeight) top = window.innerHeight - r.height - margin;
    setPos({ left: Math.max(margin, left), top: Math.max(margin, top) });
  }, [x, y]);

  useEffect(() => {
    const handler = (e: MouseEvent): void => {
      if (ref.current && !ref.current.contains(e.target as Node)) onClose();
    };
    const esc = (e: KeyboardEvent): void => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('mousedown', handler);
    document.addEventListener('keydown', esc);
    return () => {
      document.removeEventListener('mousedown', handler);
      document.removeEventListener('keydown', esc);
    };
  }, [onClose]);

  const fire = (a: ThumbAction): void => {
    onAction(a, pageNumber);
    onClose();
  };

  return (
    <div
      ref={ref}
      className="thumb-menu"
      role="menu"
      style={{ left: pos.left, top: pos.top }}
    >
      <div className="thumb-menu-header">Page {pageNumber}</div>
      <button type="button" role="menuitem" onClick={() => fire('rotate-cw')}>
        Rotate Right ⟳
      </button>
      <button type="button" role="menuitem" onClick={() => fire('rotate-ccw')}>
        Rotate Left ⟲
      </button>
      <div className="thumb-menu-sep" />
      <button type="button" role="menuitem" onClick={() => fire('duplicate')}>
        Duplicate Page
      </button>
      <button type="button" role="menuitem" onClick={() => fire('insert-blank')}>
        Insert Blank After
      </button>
      <button type="button" role="menuitem" onClick={() => fire('extract')}>
        Save Page As…
      </button>
      <div className="thumb-menu-sep" />
      <button
        type="button"
        role="menuitem"
        className="thumb-menu-danger"
        onClick={() => fire('delete')}
      >
        Delete Page
      </button>
    </div>
  );
}
