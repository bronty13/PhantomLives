import { useEffect, useRef, useState } from 'react';
import type { PDFDocumentProxy } from './pdfjs';

interface Props {
  leftDoc: PDFDocumentProxy;
  leftName: string;
  rightDoc: PDFDocumentProxy;
  rightName: string;
  onClose: () => void;
}

/**
 * Side-by-side comparison viewer. Renders a single shared page index across
 * both documents on two HTMLCanvasElement panels. Use Prev/Next or the
 * keyboard arrow keys to step. There's no diff highlighting (v1).
 */
export default function CompareModal({
  leftDoc,
  leftName,
  rightDoc,
  rightName,
  onClose
}: Props): JSX.Element {
  const [page, setPage] = useState(1);
  const maxPages = Math.max(leftDoc.numPages, rightDoc.numPages);

  useEffect(() => {
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === 'Escape') onClose();
      else if (e.key === 'ArrowRight' || e.key === 'PageDown')
        setPage((p) => Math.min(maxPages, p + 1));
      else if (e.key === 'ArrowLeft' || e.key === 'PageUp')
        setPage((p) => Math.max(1, p - 1));
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [maxPages, onClose]);

  return (
    <div className="compare-overlay" role="dialog" aria-modal="true">
      <div className="compare-bar">
        <button onClick={onClose} aria-label="Close comparison">✕ Close</button>
        <div className="compare-pager">
          <button onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page <= 1}>
            ◀
          </button>
          <span>
            Page {page} / {maxPages}
          </span>
          <button onClick={() => setPage((p) => Math.min(maxPages, p + 1))} disabled={page >= maxPages}>
            ▶
          </button>
        </div>
      </div>
      <div className="compare-panels">
        <ComparePanel doc={leftDoc} name={leftName} page={page} />
        <ComparePanel doc={rightDoc} name={rightName} page={page} />
      </div>
    </div>
  );
}

function ComparePanel({
  doc,
  name,
  page
}: {
  doc: PDFDocumentProxy;
  name: string;
  page: number;
}): JSX.Element {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [missing, setMissing] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setMissing(false);
    if (page > doc.numPages) {
      setMissing(true);
      return;
    }
    void (async () => {
      const p = await doc.getPage(page);
      const viewport = p.getViewport({ scale: 1.2 });
      const canvas = canvasRef.current;
      if (!canvas) return;
      canvas.width = viewport.width;
      canvas.height = viewport.height;
      const ctx = canvas.getContext('2d');
      if (!ctx) return;
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      await p.render({ canvasContext: ctx, viewport }).promise;
      if (cancelled) return;
    })();
    return () => {
      cancelled = true;
    };
  }, [doc, page]);

  return (
    <div className="compare-panel">
      <div className="compare-panel-header" title={name}>{name}</div>
      <div className="compare-panel-body">
        {missing ? (
          <div className="compare-missing">(no page {page} in this document)</div>
        ) : (
          <canvas ref={canvasRef} />
        )}
      </div>
    </div>
  );
}
