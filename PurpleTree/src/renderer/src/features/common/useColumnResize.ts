import { useRef, useState } from 'react';

/**
 * Returns a width (px) and a mousedown handler for a drag-to-resize column header.
 * Attach onMouseDown to a .col-resize-handle element at the right edge of the header cell.
 */
export function useColumnResize(defaultWidth: number, min = 80): {
  width: number;
  onMouseDown: (e: React.MouseEvent) => void;
} {
  const [width, setWidth] = useState(defaultWidth);
  const start = useRef({ x: 0, w: 0 });

  const onMouseDown = (e: React.MouseEvent): void => {
    e.preventDefault();
    e.stopPropagation();
    start.current = { x: e.clientX, w: width };

    const onMove = (ev: MouseEvent): void => {
      setWidth(Math.max(min, start.current.w + ev.clientX - start.current.x));
    };
    const onUp = (): void => {
      window.removeEventListener('mousemove', onMove);
      window.removeEventListener('mouseup', onUp);
    };
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
  };

  return { width, onMouseDown };
}
