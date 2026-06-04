import { useEffect, useRef, useState } from 'react';

export type ExportFormat = 'png' | 'svg' | 'pdf' | 'json' | 'markdown' | 'mermaid';
export type ImportKind = 'json' | 'markdown';
export type CopyKind = 'outline' | 'mermaid';

interface ExportMenuProps {
  busy: boolean;
  onExport: (format: ExportFormat) => void;
  onImport: (kind: ImportKind) => void;
  onCopy: (kind: CopyKind) => void;
}

const EXPORTS: { format: ExportFormat; label: string }[] = [
  { format: 'png', label: 'Image (PNG)' },
  { format: 'svg', label: 'Vector (SVG)' },
  { format: 'pdf', label: 'Document (PDF)' },
  { format: 'json', label: 'PurpleMind map (JSON)' },
  { format: 'mermaid', label: 'Mindmap diagram (.md / Mermaid)' },
  { format: 'markdown', label: 'Outline (.md)' },
];

const COPIES: { kind: CopyKind; label: string }[] = [
  { kind: 'mermaid', label: 'Mindmap as Mermaid' },
  { kind: 'outline', label: 'Outline as Markdown' },
];

export function ExportMenu({ busy, onExport, onImport, onCopy }: ExportMenuProps) {
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

  const item = (label: string, onClick: () => void) => (
    <button
      key={label}
      type="button"
      className="block w-full rounded-lg px-2.5 py-1.5 text-left text-sm hover:bg-surface-input"
      onClick={() => pick(onClick)}
    >
      {label}
    </button>
  );

  const heading = (text: string) => (
    <div className="px-2 py-1 text-xs font-semibold uppercase tracking-wide text-surface-muted">{text}</div>
  );

  return (
    <div className="relative" ref={ref}>
      <button type="button" className="btn-soft" disabled={busy} onClick={() => setOpen((o) => !o)}>
        {busy ? '⏳ Working…' : '⤓ Export / Import ▾'}
      </button>
      {open && (
        <div className="absolute right-0 z-20 mt-1 max-h-[80vh] w-64 overflow-y-auto card p-1.5 shadow-cute">
          {heading('Export this map')}
          {EXPORTS.map((e) => item(e.label, () => onExport(e.format)))}

          <div className="my-1 border-t border-surface-border" />
          {heading('Copy to clipboard')}
          {COPIES.map((c) => item(c.label, () => onCopy(c.kind)))}

          <div className="my-1 border-t border-surface-border" />
          {heading('Import into a new map')}
          {item('PurpleMind map (JSON)…', () => onImport('json'))}
          {item('Outline (Markdown)…', () => onImport('markdown'))}
        </div>
      )}
    </div>
  );
}
