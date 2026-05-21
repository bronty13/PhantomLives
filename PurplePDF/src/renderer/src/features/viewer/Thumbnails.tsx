import { useEffect, useState } from 'react';
import type { PDFDocumentProxy } from './pdfjs';
import ThumbContextMenu, { type ThumbAction } from './ThumbContextMenu';

interface Props {
  doc: PDFDocumentProxy;
  numPages: number;
  currentPage: number;
  /** Projected order of original 0-based page indices; -1 = inserted blank/duplicate placeholder. */
  projectedOrder?: number[];
  /** 0-based projected position of the currently-displayed slot. Preferred
   * over currentPage for active-thumb highlighting because it disambiguates
   * duplicates of the same source page. */
  currentIndex?: number;
  onSelect: (page: number) => void;
  onPageAction?: (action: ThumbAction, pageNumber: number) => void;
  /** Called when the user drags page `from` (1-based original) to a new position.
   * `to` is 0-based insertion index in the current ordering (0..N). */
  onReorder?: (from: number, to: number) => void;
}

type DropMark = { page: number; pos: 'before' | 'after' } | null;

export default function Thumbnails({
  doc,
  numPages,
  currentPage,
  projectedOrder,
  currentIndex,
  onSelect,
  onPageAction,
  onReorder
}: Props): JSX.Element {
  const [menu, setMenu] = useState<{ page: number; x: number; y: number } | null>(null);
  const [dragging, setDragging] = useState<number | null>(null);
  const [dropMark, setDropMark] = useState<DropMark>(null);

  // entries: { origPage: number (1-based) or 0 for placeholder; label: projected position 1..N }
  const entries =
    projectedOrder && projectedOrder.length > 0
      ? projectedOrder.map((o, i) => ({ origPage: o + 1, label: i + 1 }))
      : Array.from({ length: numPages }, (_, i) => ({ origPage: i + 1, label: i + 1 }));

  const finishDrop = (toLabel: number, pos: 'before' | 'after'): void => {
    const from = dragging;
    setDragging(null);
    setDropMark(null);
    if (from == null || !onReorder) return;
    // Convert (toLabel, pos) — both 1-based projected positions — to absolute
    // insertion index in the current ordering (0..N).
    const to = pos === 'before' ? toLabel - 1 : toLabel;
    if (to === from - 1 || to === from) return;
    onReorder(from, to);
  };

  return (
    <>
      <ul className="thumbs" role="listbox" aria-label="Page thumbnails">
        {entries.map((e, i) => (
          <li key={`${e.label}-${e.origPage}-${i}`}>
            <Thumb
              doc={doc}
              pageNumber={e.origPage}
              displayLabel={e.label}
              placeholder={e.origPage <= 0}
              active={
                currentIndex != null ? i === currentIndex : e.origPage === currentPage
              }
              isDragging={dragging === e.label}
              dropMark={dropMark && dropMark.page === e.label ? dropMark.pos : null}
              draggable={!!onReorder && e.origPage > 0}
              onSelect={() => onSelect(e.label)}
              onContextMenu={
                onPageAction && e.origPage > 0
                  ? (clientX, clientY) =>
                      setMenu({ page: e.origPage, x: clientX, y: clientY })
                  : undefined
              }
              onDragStart={() => setDragging(e.label)}
              onDragEnd={() => {
                setDragging(null);
                setDropMark(null);
              }}
              onDragOver={(pos) => {
                if (dragging == null) return;
                if (dropMark?.page !== e.label || dropMark.pos !== pos) {
                  setDropMark({ page: e.label, pos });
                }
              }}
              onDrop={(pos) => finishDrop(e.label, pos)}
            />
          </li>
        ))}
      </ul>
      {menu && onPageAction && (
        <ThumbContextMenu
          pageNumber={menu.page}
          x={menu.x}
          y={menu.y}
          onAction={(action, pageNumber) => onPageAction(action, pageNumber)}
          onClose={() => setMenu(null)}
        />
      )}
    </>
  );
}

function Thumb({
  doc,
  pageNumber,
  displayLabel,
  placeholder,
  active,
  isDragging,
  dropMark,
  draggable,
  onSelect,
  onContextMenu,
  onDragStart,
  onDragEnd,
  onDragOver,
  onDrop
}: {
  doc: PDFDocumentProxy;
  pageNumber: number;
  displayLabel: number;
  placeholder: boolean;
  active: boolean;
  isDragging: boolean;
  dropMark: 'before' | 'after' | null;
  draggable: boolean;
  onSelect: () => void;
  onContextMenu?: (clientX: number, clientY: number) => void;
  onDragStart: () => void;
  onDragEnd: () => void;
  onDragOver: (pos: 'before' | 'after') => void;
  onDrop: (pos: 'before' | 'after') => void;
}): JSX.Element {
  const [src, setSrc] = useState<string | null>(null);

  useEffect(() => {
    if (placeholder) return;
    let cancelled = false;
    let url: string | null = null;
    (async () => {
      const page = await doc.getPage(pageNumber);
      const viewport = page.getViewport({ scale: 0.2 });
      const canvas = document.createElement('canvas');
      canvas.width = viewport.width;
      canvas.height = viewport.height;
      const ctx = canvas.getContext('2d');
      if (!ctx) return;
      await page.render({ canvasContext: ctx, viewport }).promise;
      if (cancelled) return;
      url = canvas.toDataURL('image/png');
      setSrc(url);
    })();
    return () => {
      cancelled = true;
    };
  }, [doc, pageNumber, placeholder]);

  const posFromEvent = (clientY: number, rect: DOMRect): 'before' | 'after' =>
    clientY - rect.top < rect.height / 2 ? 'before' : 'after';

  return (
    <div
      className={`thumb-wrap${dropMark ? ` drop-${dropMark}` : ''}${isDragging ? ' is-dragging' : ''}`}
      onDragOver={(e) => {
        if (!draggable) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = 'move';
        const rect = (e.currentTarget as HTMLDivElement).getBoundingClientRect();
        onDragOver(posFromEvent(e.clientY, rect));
      }}
      onDrop={(e) => {
        if (!draggable) return;
        e.preventDefault();
        const rect = (e.currentTarget as HTMLDivElement).getBoundingClientRect();
        onDrop(posFromEvent(e.clientY, rect));
      }}
    >
      <button
        type="button"
        className={`thumb${active ? ' active' : ''}${placeholder ? ' thumb-placeholder-btn' : ''}`}
        draggable={draggable}
        onDragStart={(e) => {
          if (!draggable) return;
          e.dataTransfer.effectAllowed = 'move';
          e.dataTransfer.setData('text/plain', String(displayLabel));
          onDragStart();
        }}
        onDragEnd={onDragEnd}
        onClick={onSelect}
        onContextMenu={(e) => {
          if (!onContextMenu) return;
          e.preventDefault();
          onContextMenu(e.clientX, e.clientY);
        }}
        aria-current={active ? 'page' : undefined}
        aria-label={placeholder ? `Blank/duplicate page at ${displayLabel}` : `Go to page ${pageNumber}`}
      >
        {placeholder ? (
          <div className="thumb-placeholder" />
        ) : src ? (
          <img src={src} alt="" />
        ) : (
          <div className="thumb-placeholder" />
        )}
        <span className="thumb-label">{displayLabel}</span>
      </button>
    </div>
  );
}
