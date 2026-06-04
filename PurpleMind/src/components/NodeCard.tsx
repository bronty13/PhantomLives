import { Handle, Position, type NodeProps } from '@xyflow/react';
import { useEffect, useRef, useState } from 'react';

export interface MindNodeData {
  label: string;
  color: string | null;
  onCommitLabel: (id: string, label: string) => void;
  [key: string]: unknown;
}

/**
 * A soft rounded mind-map node. Double-click (or the Enter shortcut from the
 * editor) drops into inline editing; blur / Enter commits, Escape cancels.
 * Left handle is the connection target, right handle the source.
 */
export function NodeCard({ id, data, selected }: NodeProps) {
  const d = data as MindNodeData;
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(d.label);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (!editing) setDraft(d.label);
  }, [d.label, editing]);

  useEffect(() => {
    if (editing && inputRef.current) {
      inputRef.current.focus();
      inputRef.current.select();
    }
  }, [editing]);

  const commit = () => {
    setEditing(false);
    const next = draft.trim();
    if (next !== d.label) d.onCommitLabel(id, next);
  };

  const accent = d.color ?? 'rgb(var(--brand-500))';

  return (
    <div
      className={`min-w-[120px] max-w-[280px] rounded-2xl border bg-surface-card px-3.5 py-2.5
        text-sm font-semibold text-surface-text shadow-cute transition-shadow
        ${selected ? 'ring-2 ring-brand-400' : ''}`}
      style={{ borderColor: accent, borderLeftWidth: 5 }}
      onDoubleClick={() => setEditing(true)}
    >
      <Handle type="target" position={Position.Left} />
      {editing ? (
        <textarea
          ref={inputRef}
          className="w-full resize-none bg-transparent outline-none"
          rows={Math.max(1, draft.split('\n').length)}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onBlur={commit}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault();
              commit();
            } else if (e.key === 'Escape') {
              setDraft(d.label);
              setEditing(false);
            }
            e.stopPropagation();
          }}
        />
      ) : (
        <div className="whitespace-pre-wrap break-words">
          {d.label || <span className="text-surface-muted">Untitled</span>}
        </div>
      )}
      <Handle type="source" position={Position.Right} />
    </div>
  );
}
