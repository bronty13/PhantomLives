import { useEffect, useRef, useState } from 'react';

export type ExportFormat = 'png' | 'svg' | 'pdf' | 'json' | 'markdown';
export type ImportKind = 'json' | 'markdown';

interface ExportMenuProps {
  busy: boolean;
  onExport: (format: ExportFormat) => void;
  onImport: (kind: ImportKind) => void;
}

const EXPORTS: { format: ExportFormat; label: string }[] = [
  { format: 'png', label: 'Image (PNG)' },
  { format: 'svg', label: 'Vector (SVG)' },
  { format: 'pdf', label: 'Document (PDF)' },
  { format: 'json', label: 'PurpleMind map (JSON)' },
  { format: 'markdown', label: 'Outline (Markdown)' },
];

export function ExportMenu({ busy, onExport, onImport }: ExportMenuProps) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', onDown);
    return () => document.removeEventListener('mousedown', onDown);
  }, [open]);

  const pick = (fn: () => void) => {
    setOpen(false);
    fn();
  };

  return (
    <div className="relative" ref={ref}>
      <button
        type="button"
        className="btn-soft"
        disabled={busy}
        onClick={() => setOpen((o) => !o)}
      >
        {busy ? '⏳ Working…' : '⤓ Export / Import ▾'}
      </button>
      {open && (
        <div className="absolute right-0 z-20 mt-1 w-60 card p-1.5 shadow-cute">
          <div className="px-2 py-1 text-xs font-semibold uppercase tracking-wide text-surface-muted">
            Export this map
          </div>
          {EXPORTS.map((e) => (
            <button
              key={e.format}
              type="button"
              className="block w-full rounded-lg px-2.5 py-1.5 text-left text-sm hover:bg-surface-input"
              onClick={() => pick(() => onExport(e.format))}
            >
              {e.label}
            </button>
          ))}
          <div className="my-1 border-t border-surface-border" />
          <div className="px-2 py-1 text-xs font-semibold uppercase tracking-wide text-surface-muted">
            Import into a new map
          </div>
          <button
            type="button"
            className="block w-full rounded-lg px-2.5 py-1.5 text-left text-sm hover:bg-surface-input"
            onClick={() => pick(() => onImport('json'))}
          >
            PurpleMind map (JSON)…
          </button>
          <button
            type="button"
            className="block w-full rounded-lg px-2.5 py-1.5 text-left text-sm hover:bg-surface-input"
            onClick={() => pick(() => onImport('markdown'))}
          >
            Outline (Markdown)…
          </button>
        </div>
      )}
    </div>
  );
}
