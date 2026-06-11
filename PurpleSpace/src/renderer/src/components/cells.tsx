/**
 * @file cells.tsx — property cell editors, shared by the database table and
 * the row-page property strip.
 */
import React, { useEffect, useRef, useState } from 'react';
import type { CellValue, PropDef, SelectOption } from '../../../shared/dbmodel';
import { freshId, nextTagColor } from '../../../shared/dbmodel';
import { tagColor } from '../lib/tags';
import { useIsDark } from '../lib/useIsDark';
import { Popover } from './Popover';

export function TagPill({ option, dark }: { option: SelectOption; dark: boolean }): React.JSX.Element {
  return (
    <span className="tag" style={tagColor(option.color, dark)}>
      {option.name}
    </span>
  );
}

interface CellProps {
  prop: PropDef;
  value: CellValue;
  onChange: (value: CellValue) => void;
  /** Add a new select option to the property; returns the created option. */
  onAddOption?: (name: string) => SelectOption;
}

/** Click-to-edit cell. Renders display state; manages its own edit state. */
export function Cell({ prop, value, onChange, onAddOption }: CellProps): React.JSX.Element {
  const dark = useIsDark();
  const [editing, setEditing] = useState(false);
  const [popAt, setPopAt] = useState<{ x: number; y: number } | null>(null);
  const cellRef = useRef<HTMLDivElement>(null);

  const openPicker = (): void => {
    const r = cellRef.current?.getBoundingClientRect();
    if (r) setPopAt({ x: r.left, y: r.bottom + 2 });
  };

  switch (prop.type) {
    case 'checkbox':
      return (
        <div className="db-cell" style={{ textAlign: 'center' }}>
          <input
            type="checkbox"
            className="db-checkbox"
            checked={value === true}
            onChange={(e) => onChange(e.target.checked)}
          />
        </div>
      );

    case 'select':
    case 'multiSelect': {
      const ids = prop.type === 'select' ? (value ? [String(value)] : []) : Array.isArray(value) ? value : [];
      const opts = prop.options ?? [];
      return (
        <div ref={cellRef} className="db-cell" onClick={openPicker}>
          {ids
            .map((id) => opts.find((o) => o.id === id))
            .filter((o): o is SelectOption => !!o)
            .map((o) => (
              <TagPill key={o.id} option={o} dark={dark} />
            ))}
          {popAt && (
            <SelectPicker
              at={popAt}
              prop={prop}
              selected={ids}
              onClose={() => setPopAt(null)}
              onAddOption={onAddOption}
              onToggle={(optId) => {
                if (prop.type === 'select') {
                  onChange(ids.includes(optId) ? null : optId);
                  setPopAt(null);
                } else {
                  const next = ids.includes(optId) ? ids.filter((i) => i !== optId) : [...ids, optId];
                  onChange(next);
                }
              }}
            />
          )}
        </div>
      );
    }

    case 'url': {
      if (editing) {
        return (
          <div className="db-cell editing">
            <CommitInput
              type="url"
              initial={value == null ? '' : String(value)}
              onCommit={(v) => {
                onChange(v.trim() === '' ? null : v.trim());
                setEditing(false);
              }}
            />
          </div>
        );
      }
      return (
        <div className="db-cell url-cell" onClick={() => setEditing(true)}>
          {value ? (
            <a
              href={String(value)}
              onClick={(e) => {
                e.preventDefault();
                e.stopPropagation();
                void window.purpleSpace.openExternal(String(value));
              }}
            >
              {String(value)}
            </a>
          ) : null}
        </div>
      );
    }

    case 'date': {
      if (editing) {
        return (
          <div className="db-cell editing">
            <CommitInput
              type="date"
              initial={value == null ? '' : String(value)}
              onCommit={(v) => {
                onChange(v === '' ? null : v);
                setEditing(false);
              }}
            />
          </div>
        );
      }
      return (
        <div className="db-cell" onClick={() => setEditing(true)}>
          {value ? formatDate(String(value)) : ''}
        </div>
      );
    }

    case 'number': {
      if (editing) {
        return (
          <div className="db-cell editing">
            <CommitInput
              type="number"
              initial={value == null ? '' : String(value)}
              onCommit={(v) => {
                onChange(v.trim() === '' ? null : Number(v));
                setEditing(false);
              }}
            />
          </div>
        );
      }
      return (
        <div className="db-cell" style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }} onClick={() => setEditing(true)}>
          {value == null ? '' : String(value)}
        </div>
      );
    }

    default: {
      // text
      if (editing) {
        return (
          <div className="db-cell editing">
            <CommitInput
              type="text"
              initial={value == null ? '' : String(value)}
              onCommit={(v) => {
                onChange(v === '' ? null : v);
                setEditing(false);
              }}
            />
          </div>
        );
      }
      return (
        <div className="db-cell" onClick={() => setEditing(true)}>
          {value == null ? '' : String(value)}
        </div>
      );
    }
  }
}

function CommitInput({
  type,
  initial,
  onCommit
}: {
  type: string;
  initial: string;
  onCommit: (v: string) => void;
}): React.JSX.Element {
  const [draft, setDraft] = useState(initial);
  const ref = useRef<HTMLInputElement>(null);
  useEffect(() => {
    ref.current?.focus();
    if (type === 'text' || type === 'url') ref.current?.select();
  }, [type]);
  return (
    <input
      ref={ref}
      type={type}
      value={draft}
      onChange={(e) => setDraft(e.target.value)}
      onBlur={() => onCommit(draft)}
      onKeyDown={(e) => {
        if (e.key === 'Enter') (e.target as HTMLInputElement).blur();
        if (e.key === 'Escape') {
          setDraft(initial);
          // commit the original (no-op change) to exit editing
          onCommit(initial);
        }
      }}
    />
  );
}

interface SelectPickerProps {
  at: { x: number; y: number };
  prop: PropDef;
  selected: string[];
  onToggle: (optionId: string) => void;
  onAddOption?: (name: string) => SelectOption;
  onClose: () => void;
}

function SelectPicker({ at, prop, selected, onToggle, onAddOption, onClose }: SelectPickerProps): React.JSX.Element {
  const dark = useIsDark();
  const [term, setTerm] = useState('');
  const opts = prop.options ?? [];
  const visible = opts.filter((o) => o.name.toLowerCase().includes(term.toLowerCase()));
  const canCreate =
    onAddOption && term.trim() !== '' && !opts.some((o) => o.name.toLowerCase() === term.trim().toLowerCase());

  return (
    <Popover at={at} onClose={onClose} className="menu">
      <input
        autoFocus
        type="text"
        placeholder="Find or create an option…"
        value={term}
        onChange={(e) => setTerm(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter' && canCreate) {
            const opt = onAddOption!(term.trim());
            onToggle(opt.id);
            setTerm('');
          }
          if (e.key === 'Escape') onClose();
        }}
        style={{
          width: '100%',
          border: 'none',
          outline: 'none',
          background: 'var(--paper-dim)',
          borderRadius: 6,
          padding: '6px 9px',
          marginBottom: 5,
          fontSize: 13
        }}
      />
      <div style={{ maxHeight: 220, overflowY: 'auto' }}>
        {visible.map((o) => (
          <button key={o.id} className="opt-row" style={{ width: '100%', textAlign: 'left' }} onClick={() => onToggle(o.id)}>
            <span style={{ width: 14, color: 'var(--accent)' }}>{selected.includes(o.id) ? '✓' : ''}</span>
            <TagPill option={o} dark={dark} />
          </button>
        ))}
        {canCreate && (
          <button
            className="opt-row"
            style={{ width: '100%', textAlign: 'left' }}
            onClick={() => {
              const opt = onAddOption!(term.trim());
              onToggle(opt.id);
              setTerm('');
            }}
          >
            <span style={{ color: 'var(--ink-2)' }}>Create</span>
            <TagPill option={{ id: 'new', name: term.trim(), color: nextTagColor(opts) }} dark={dark} />
          </button>
        )}
        {visible.length === 0 && !canCreate && <div className="menu-note">No options yet — type to create one.</div>}
      </div>
    </Popover>
  );
}

export function makeOption(options: SelectOption[], name: string): SelectOption {
  return { id: freshId('opt'), name, color: nextTagColor(options) };
}

function formatDate(iso: string): string {
  const d = new Date(`${iso}T00:00:00`);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
}
