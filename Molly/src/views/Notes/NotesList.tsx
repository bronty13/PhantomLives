import { useState } from 'react';
import type { NoteSummary } from '../../data/notes';

interface Props {
  notes: NoteSummary[];
  selectedNoteId: number | null;
  onSelect: (noteId: number) => void;
  onAction: (noteId: number, action: NoteAction) => void;
  emptyHint?: string;
}

export type NoteAction = 'copy' | 'move' | 'delete';

export function NotesList({ notes, selectedNoteId, onSelect, onAction, emptyHint }: Props) {
  if (notes.length === 0) {
    return (
      <div className="text-xs italic opacity-60 px-3 py-6 text-center">
        {emptyHint ?? 'No notes here yet. Click ＋ Note above to create one.'}
      </div>
    );
  }
  return (
    <div className="space-y-1">
      {notes.map((n) => (
        <NoteRow
          key={n.id}
          note={n}
          selected={selectedNoteId === n.id}
          onSelect={() => onSelect(n.id)}
          onAction={(a) => onAction(n.id, a)}
        />
      ))}
    </div>
  );
}

function NoteRow({ note, selected, onSelect, onAction }: {
  note: NoteSummary; selected: boolean; onSelect: () => void; onAction: (a: NoteAction) => void;
}) {
  const [menuOpen, setMenuOpen] = useState(false);
  return (
    <div
      className="group rounded-2xl px-3 py-2 cursor-pointer relative transition border"
      style={{
        background: selected ? 'rgb(var(--persona-primary) / 0.5)' : (note.paperColor ?? 'white'),
        borderColor: selected ? 'rgb(var(--persona-accent))' : 'rgb(0 0 0 / 0.08)',
        boxShadow: selected ? '0 4px 12px -4px rgb(var(--persona-accent) / 0.45)' : 'none',
      }}
      onClick={onSelect}
    >
      <div className="flex items-baseline gap-2">
        <span className="font-semibold text-sm flex-1 truncate">{note.title}</span>
        {note.attachmentCount > 0 && (
          <span className="text-[10px] opacity-60" title={`${note.attachmentCount} attachment${note.attachmentCount === 1 ? '' : 's'}`}>
            📎{note.attachmentCount}
          </span>
        )}
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); setMenuOpen((v) => !v); }}
          className="opacity-0 group-hover:opacity-70 hover:opacity-100 px-1 text-xs"
          title="Note actions"
        >
          ⋯
        </button>
      </div>
      <div className="text-[11px] opacity-55 mt-0.5 font-mono">
        edited {fmtDate(note.lastEditedAt)}
      </div>
      {menuOpen && (
        <div
          className="absolute right-1 top-full mt-1 z-10 rounded-xl shadow-lg border border-black/10 bg-white text-left text-xs overflow-hidden"
          style={{ minWidth: 140 }}
          onClick={(e) => e.stopPropagation()}
        >
          <Item onClick={() => { setMenuOpen(false); onAction('copy'); }}>📋 Copy note</Item>
          <Item onClick={() => { setMenuOpen(false); onAction('move'); }}>↗ Move to…</Item>
          <div className="border-t border-black/5" />
          <Item danger onClick={() => { setMenuOpen(false); onAction('delete'); }}>🗑 Delete</Item>
        </div>
      )}
    </div>
  );
}

function Item({ children, onClick, danger = false }: {
  children: React.ReactNode; onClick: () => void; danger?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="w-full text-left px-3 py-1.5 hover:bg-black/5"
      style={{ color: danger ? '#b91c1c' : 'inherit' }}
    >
      {children}
    </button>
  );
}

function fmtDate(iso: string): string {
  // SQLite datetime('now') format: "YYYY-MM-DD HH:MM:SS" in UTC
  const d = new Date(iso.replace(' ', 'T') + 'Z');
  if (Number.isNaN(d.getTime())) return iso;
  const today = new Date();
  const sameDay = d.toDateString() === today.toDateString();
  if (sameDay) return d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}
