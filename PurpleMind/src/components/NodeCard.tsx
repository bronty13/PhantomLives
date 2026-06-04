import { Handle, Position, type NodeProps } from '@xyflow/react';
import { useEffect, useRef, useState } from 'react';
import type { Tier } from '../lib/branchStyle';
import { mix } from '../lib/color';

export interface MindNodeData {
  label: string;
  /** Effective colour (branch colour or manual override). */
  color: string;
  tier: Tier;
  /** Optional emoji icon shown before the label. */
  icon?: string | null;
  /** null = no checkbox · 0 = unchecked · 1 = checked. */
  checked?: number | null;
  /** Whether this node has a note attached (shows a 📝 indicator). */
  hasNote?: boolean;
  /** Number of (direct) children — drives the fold toggle. */
  childCount?: number;
  /** Whether this node's subtree is collapsed. */
  collapsed?: boolean;
  /** Bumped by the editor to programmatically enter edit mode (keyboard). */
  editEpoch?: number;
  onCommitLabel: (id: string, label: string) => void;
  onToggleCollapse?: (id: string) => void;
  onToggleCheck?: (id: string) => void;
  onOpenNote?: (id: string) => void;
  [key: string]: unknown;
}

/**
 * A tiered mind-map node:
 *   - root  → large neutral bordered card,
 *   - topic → filled pastel box in the branch colour,
 *   - item  → text sitting on a branch-colour underline.
 * Plus optional emoji icon, checkbox, note indicator, and a fold toggle for
 * nodes with children. Double-click (or the keyboard edit signal) edits the
 * label inline.
 */
export function NodeCard({ id, data, selected }: NodeProps) {
  const d = data as MindNodeData;
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(d.label);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const lastEpoch = useRef<number | undefined>(d.editEpoch);

  useEffect(() => {
    if (!editing) setDraft(d.label);
  }, [d.label, editing]);

  // Keyboard "edit" signal from the editor.
  useEffect(() => {
    if (d.editEpoch !== undefined && d.editEpoch !== lastEpoch.current) {
      lastEpoch.current = d.editEpoch;
      setEditing(true);
    }
  }, [d.editEpoch]);

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

  const color = d.color;
  const checkable = d.checked === 0 || d.checked === 1;
  const done = d.checked === 1;

  // Per-tier container styling.
  let containerStyle: React.CSSProperties = {};
  let containerClass =
    'relative min-w-[90px] max-w-[300px] transition-shadow';
  let textClass = 'whitespace-pre-wrap break-words';

  if (d.tier === 'root') {
    containerClass += ' rounded-2xl border-[3px] bg-surface-card px-5 py-3 shadow-cute font-bold text-base text-surface-text';
    containerStyle = { borderColor: color };
  } else if (d.tier === 'topic') {
    const fill = mix(color, '#ffffff', 0.82);
    containerClass += ' rounded-2xl px-4 py-2.5 font-semibold shadow-cute';
    containerStyle = { background: fill, border: `1.5px solid ${mix(color, '#ffffff', 0.45)}`, color: '#2a2140' };
  } else {
    // item — text on a coloured underline, no box fill. A min width keeps a
    // short or empty item from collapsing into a bare sliver/box when selected.
    containerClass += ' min-w-[72px] px-2 py-1.5 font-medium text-surface-text';
    containerStyle = { borderBottom: `3px solid ${color}`, borderRadius: 2 };
  }
  if (selected) containerClass += ' ring-2 ring-offset-1 ring-offset-transparent';

  return (
    <div
      className={containerClass}
      style={{ ...containerStyle, ...(selected ? { boxShadow: `0 0 0 2px ${color}` } : {}) }}
      onDoubleClick={() => setEditing(true)}
    >
      {/* Handles on both sides so branches can flow left or right (bilateral
          layout). Edges pick the side via geometry; ids: t=target, s=source,
          l=left, r=right. */}
      <Handle type="target" position={Position.Left} id="tl" />
      <Handle type="source" position={Position.Left} id="sl" />
      <Handle type="target" position={Position.Right} id="tr" />

      <div className="flex items-center gap-1.5">
        {checkable && (
          <button
            type="button"
            className="grid h-4 w-4 shrink-0 place-items-center rounded border text-[10px] leading-none"
            style={{ borderColor: color, background: done ? color : 'transparent', color: '#fff' }}
            title={done ? 'Mark not done' : 'Mark done'}
            onClick={(e) => {
              e.stopPropagation();
              d.onToggleCheck?.(id);
            }}
          >
            {done ? '✓' : ''}
          </button>
        )}
        {d.icon && <span className="shrink-0 text-base leading-none">{d.icon}</span>}

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
          <div className={`${textClass} ${done ? 'line-through opacity-60' : ''}`}>
            {d.label || <span className="italic opacity-40">New idea…</span>}
          </div>
        )}

        {d.hasNote && (
          <button
            type="button"
            className="shrink-0 text-xs opacity-70 hover:opacity-100"
            title="View note"
            onClick={(e) => {
              e.stopPropagation();
              d.onOpenNote?.(id);
            }}
          >
            📝
          </button>
        )}
      </div>

      <Handle type="source" position={Position.Right} id="sr" />

      {(d.childCount ?? 0) > 0 && (
        <button
          type="button"
          className="absolute top-1/2 grid h-5 w-5 -translate-y-1/2 place-items-center rounded-full border text-[11px] font-bold leading-none"
          style={{ right: -26, borderColor: color, background: 'rgb(var(--surface-card))', color }}
          title={d.collapsed ? 'Expand' : 'Collapse'}
          onClick={(e) => {
            e.stopPropagation();
            d.onToggleCollapse?.(id);
          }}
        >
          {d.collapsed ? (d.childCount ?? '') : '−'}
        </button>
      )}
    </div>
  );
}
