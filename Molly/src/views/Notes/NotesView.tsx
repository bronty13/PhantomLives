import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  type Note, type NoteFolder, type NoteSummary, type NoteTag,
  copyNote, createNote, createNoteFolder, deleteNote, deleteNoteFolder,
  getNote, listNoteFolders, listNoteTags, listNotes, moveNote, moveNoteFolder,
  renameNoteFolder, setNoteTags, updateNote,
} from '../../data/notes';
import { FolderPickerModal } from './FolderPickerModal';
import { FolderTree, type FolderAction } from './FolderTree';
import { NoteEditor } from './NoteEditor';
import { NotesList, type NoteAction } from './NotesList';
import { SearchPanel } from './SearchPanel';
import { TagChips } from './TagChips';

export function NotesView() {
  const [folders, setFolders] = useState<NoteFolder[]>([]);
  const [selectedFolderId, setSelectedFolderId] = useState<number | null>(null);
  const [notes, setNotes] = useState<NoteSummary[]>([]);
  const [tags, setTags] = useState<NoteTag[]>([]);
  const [tagFilter, setTagFilter] = useState<number[]>([]);
  const [selectedNoteId, setSelectedNoteId] = useState<number | null>(null);
  const [loadedNote, setLoadedNote] = useState<Note | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [highlightTarget, setHighlightTarget] = useState<string | null>(null);
  // Counter bumped on every Find-result open so the same hit re-fires
  // the highlight effect (keying off snippet alone would skip repeats).
  const [highlightTick, setHighlightTick] = useState(0);

  // Active picker modal: 'folder' = move-folder picker, 'note' = move-note
  // picker. Null = closed.
  const [picker, setPicker] = useState<
    | { kind: 'move-folder'; folderId: number; currentParent: number | null }
    | { kind: 'move-note'; noteId: number; currentFolder: number | null }
    | null
  >(null);

  // Autosave debounce (800ms after stop typing).
  const saveTimer = useRef<number | null>(null);
  const pendingTitle = useRef<string | null>(null);
  const pendingHtml = useRef<string | null>(null);
  const pendingText = useRef<string | null>(null);

  const reloadFolders = useCallback(async () => {
    try { setFolders(await listNoteFolders()); }
    catch (e) { setError(String((e as { message?: string })?.message ?? e)); }
  }, []);

  const reloadNotes = useCallback(async () => {
    try { setNotes(await listNotes(selectedFolderId)); }
    catch (e) { setError(String((e as { message?: string })?.message ?? e)); }
  }, [selectedFolderId]);

  const reloadTags = useCallback(async () => {
    try { setTags(await listNoteTags()); }
    catch (e) { setError(String((e as { message?: string })?.message ?? e)); }
  }, []);

  const reloadSelectedNote = useCallback(async () => {
    if (selectedNoteId == null) { setLoadedNote(null); return; }
    try { setLoadedNote(await getNote(selectedNoteId)); }
    catch (e) { setError(String((e as { message?: string })?.message ?? e)); setLoadedNote(null); }
  }, [selectedNoteId]);

  useEffect(() => { reloadFolders(); }, [reloadFolders]);
  useEffect(() => { reloadNotes(); }, [reloadNotes]);
  useEffect(() => { reloadTags(); }, [reloadTags]);
  useEffect(() => { reloadSelectedNote(); }, [reloadSelectedNote]);

  // Filter notes by selected tag chips. AND semantics: a note must
  // carry ALL active filter tags to remain visible. Empty filter = all.
  const visibleNotes = useMemo(() => {
    if (tagFilter.length === 0) return notes;
    return notes.filter((n) => tagFilter.every((tid) => n.tagIds.includes(tid)));
  }, [notes, tagFilter]);

  // Flush any pending edits when the user switches notes (don't lose
  // last few keystrokes to the debounce window).
  const flushPending = useCallback(async () => {
    if (saveTimer.current != null) {
      window.clearTimeout(saveTimer.current);
      saveTimer.current = null;
    }
    const id = loadedNote?.id;
    if (id == null) return;
    const title = pendingTitle.current ?? loadedNote!.title;
    const html = pendingHtml.current ?? loadedNote!.contentHtml;
    const text = pendingText.current ?? loadedNote!.contentText;
    if (
      title === loadedNote!.title &&
      html === loadedNote!.contentHtml &&
      text === loadedNote!.contentText
    ) {
      pendingTitle.current = null; pendingHtml.current = null; pendingText.current = null;
      return;
    }
    try {
      await updateNote(id, title, html, text);
      pendingTitle.current = null; pendingHtml.current = null; pendingText.current = null;
      await reloadNotes();
    } catch (e) {
      setError(String((e as { message?: string })?.message ?? e));
    }
  }, [loadedNote, reloadNotes]);

  // When the selected note changes, flush before swapping.
  const switchNote = useCallback(async (newId: number) => {
    await flushPending();
    setSelectedNoteId(newId);
  }, [flushPending]);

  const scheduleSave = useCallback(() => {
    if (saveTimer.current != null) window.clearTimeout(saveTimer.current);
    saveTimer.current = window.setTimeout(() => { flushPending(); }, 800);
  }, [flushPending]);

  // Folder pane handlers
  async function onFolderAction(folderId: number | null, action: FolderAction) {
    setError(null);
    try {
      if (action === 'new-folder') {
        const name = window.prompt('New folder name:', 'Untitled folder');
        if (!name) return;
        const id = await createNoteFolder(folderId, name);
        await reloadFolders();
        setSelectedFolderId(id);
      } else if (action === 'new-note') {
        const id = await createNote(folderId, 'Untitled');
        await reloadFolders();
        setSelectedFolderId(folderId);
        await reloadNotes();
        await switchNote(id);
      } else if (action === 'rename' && folderId != null) {
        const current = folders.find((f) => f.id === folderId)?.name ?? '';
        const name = window.prompt('Rename folder:', current);
        if (!name) return;
        await renameNoteFolder(folderId, name);
        await reloadFolders();
      } else if (action === 'move' && folderId != null) {
        const current = folders.find((f) => f.id === folderId)?.parentId ?? null;
        setPicker({ kind: 'move-folder', folderId, currentParent: current });
      } else if (action === 'delete' && folderId != null) {
        if (!window.confirm('Delete this folder + everything inside it? This cannot be undone.')) return;
        await deleteNoteFolder(folderId);
        if (selectedFolderId === folderId) setSelectedFolderId(null);
        await reloadFolders();
        await reloadNotes();
      }
    } catch (e) {
      setError(String((e as { message?: string })?.message ?? e));
    }
  }

  // Note row handlers
  async function onNoteAction(noteId: number, action: NoteAction) {
    setError(null);
    try {
      if (action === 'copy') {
        const newId = await copyNote(noteId);
        await reloadNotes();
        await switchNote(newId);
      } else if (action === 'move') {
        const note = notes.find((n) => n.id === noteId);
        setPicker({ kind: 'move-note', noteId, currentFolder: note?.folderId ?? null });
      } else if (action === 'delete') {
        if (!window.confirm('Delete this note? This cannot be undone.')) return;
        await deleteNote(noteId);
        if (selectedNoteId === noteId) {
          setSelectedNoteId(null);
          setLoadedNote(null);
        }
        await reloadNotes();
      }
    } catch (e) {
      setError(String((e as { message?: string })?.message ?? e));
    }
  }

  // Open a Search or Find hit from the panel. For Find hits the
  // snippet drives the editor's scroll-and-highlight; for Search the
  // user just lands on the note plainly.
  async function openHit(target: { noteId: number; lineNo?: number; snippet?: string }) {
    await flushPending();
    setSelectedNoteId(target.noteId);
    if (target.snippet) {
      setHighlightTarget(target.snippet);
      setHighlightTick((t) => t + 1);
    } else {
      setHighlightTarget(null);
    }
  }

  async function onChangeNoteTags(next: number[]) {
    if (!loadedNote) return;
    setError(null);
    try {
      await setNoteTags(loadedNote.id, next);
      setLoadedNote({ ...loadedNote, tagIds: next });
      await reloadNotes();
    } catch (e) {
      setError(String((e as { message?: string })?.message ?? e));
    }
  }

  const editorBody = useMemo(() => {
    if (!loadedNote) {
      return (
        <div className="flex-1 flex items-center justify-center opacity-60 italic">
          {selectedFolderId == null && notes.length === 0
            ? 'Welcome to Notes 🌷 — create your first folder or note from the tree on the left.'
            : 'Pick a note from the middle pane, or click ＋ Note above to start a new one.'}
        </div>
      );
    }
    return (
      <div className="flex-1 overflow-y-auto p-6">
        <input
          type="text"
          value={pendingTitle.current ?? loadedNote.title}
          onChange={(e) => {
            pendingTitle.current = e.target.value;
            // Force a re-render of the input by mutating loadedNote shallow
            setLoadedNote({ ...loadedNote, title: e.target.value });
            scheduleSave();
          }}
          onBlur={() => flushPending()}
          className="w-full bg-transparent border-none focus:outline-none display-font text-3xl font-semibold mb-3 persona-accent"
          placeholder="Untitled"
        />
        <div className="text-xs opacity-50 mb-3 font-mono">
          created {fmtDateTime(loadedNote.createdAt)} · edited {fmtDateTime(loadedNote.lastEditedAt)}
        </div>
        <div className="mb-4">
          <TagChips allTags={tags} selected={loadedNote.tagIds} onChange={onChangeNoteTags} />
        </div>
        <NoteEditor
          noteKey={`${loadedNote.id}-${highlightTick}`}
          initialHtml={loadedNote.contentHtml}
          fontFamily={loadedNote.fontFamily}
          paperColor={loadedNote.paperColor}
          highlightSnippet={highlightTarget}
          onChange={(html, text) => {
            pendingHtml.current = html;
            pendingText.current = text;
            scheduleSave();
          }}
        />
      </div>
    );
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loadedNote, selectedFolderId, notes.length, scheduleSave, flushPending]);

  return (
    <div className="flex h-full">
      {/* Pane 1: folder tree */}
      <aside className="w-64 border-r border-black/10 bg-white/40 overflow-y-auto p-3">
        <div className="flex items-center justify-between mb-3 px-1">
          <div className="display-font text-xl font-semibold persona-accent">📝 Notes</div>
          <button
            type="button"
            onClick={() => onFolderAction(selectedFolderId, 'new-folder')}
            className="pretty-button text-xs"
            title="Create a new folder under the selected one (or at root)"
          >
            ＋ Folder
          </button>
        </div>
        <FolderTree
          folders={folders}
          selectedFolderId={selectedFolderId}
          onSelect={(id) => { flushPending(); setSelectedFolderId(id); }}
          onAction={onFolderAction}
        />
        <div className="mt-3 px-1 text-[10px] opacity-50 leading-snug">
          Click <span className="font-semibold">⋯</span> on any folder for rename, move, delete.
          Double-click a folder name to rename quickly.
        </div>
      </aside>

      {/* Pane 2: notes list */}
      <section className="w-72 border-r border-black/10 bg-white/20 overflow-y-auto p-3">
        <div className="flex items-center justify-between mb-3 px-1">
          <div className="text-sm font-semibold opacity-75">
            {selectedFolderId == null
              ? 'All notes (root)'
              : folders.find((f) => f.id === selectedFolderId)?.name ?? 'Folder'}
          </div>
          <button
            type="button"
            onClick={() => onFolderAction(selectedFolderId, 'new-note')}
            className="pretty-button text-xs"
          >
            ＋ Note
          </button>
        </div>
        <SearchPanel onOpenHit={openHit} />
        {error && (
          <div className="text-xs text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2 mb-3">{error}</div>
        )}
        {tags.length > 0 && (
          <TagFilterBar
            tags={tags}
            active={tagFilter}
            onChange={setTagFilter}
            totalCount={notes.length}
            visibleCount={visibleNotes.length}
          />
        )}
        <NotesList
          notes={visibleNotes}
          allTags={tags}
          selectedNoteId={selectedNoteId}
          onSelect={switchNote}
          onAction={onNoteAction}
          emptyHint={tagFilter.length > 0 ? 'No notes match this tag filter.' : undefined}
        />
      </section>

      {/* Pane 3: editor */}
      <main className="flex-1 flex flex-col overflow-hidden">
        {editorBody}
      </main>

      {picker?.kind === 'move-folder' && (
        <FolderPickerModal
          title="Move folder to…"
          folders={folders}
          excludeId={picker.folderId}
          currentParentId={picker.currentParent}
          onCancel={() => setPicker(null)}
          onPick={async (target) => {
            const sourceId = picker.folderId;
            setPicker(null);
            try {
              await moveNoteFolder(sourceId, target);
              await reloadFolders();
            } catch (e) {
              setError(String((e as { message?: string })?.message ?? e));
            }
          }}
        />
      )}
      {picker?.kind === 'move-note' && (
        <FolderPickerModal
          title="Move note to…"
          folders={folders}
          currentParentId={picker.currentFolder}
          onCancel={() => setPicker(null)}
          onPick={async (target) => {
            const noteId = picker.noteId;
            setPicker(null);
            try {
              await moveNote(noteId, target);
              await reloadNotes();
            } catch (e) {
              setError(String((e as { message?: string })?.message ?? e));
            }
          }}
        />
      )}
    </div>
  );
}

function TagFilterBar({ tags, active, onChange, totalCount, visibleCount }: {
  tags: NoteTag[]; active: number[]; onChange: (next: number[]) => void;
  totalCount: number; visibleCount: number;
}) {
  function toggle(id: number) {
    if (active.includes(id)) onChange(active.filter((x) => x !== id));
    else onChange([...active, id]);
  }
  return (
    <div className="mb-3 px-1">
      <div className="flex items-center justify-between text-[10px] uppercase tracking-wider opacity-50 mb-1.5">
        <span>Filter by tag</span>
        {active.length > 0 && (
          <button type="button" onClick={() => onChange([])} className="opacity-70 hover:opacity-100 underline">
            clear · showing {visibleCount} of {totalCount}
          </button>
        )}
      </div>
      <div className="flex flex-wrap gap-1">
        {tags.map((t) => {
          const on = active.includes(t.id);
          return (
            <button
              key={t.id}
              type="button"
              onClick={() => toggle(t.id)}
              className="text-[11px] font-semibold rounded-full px-2 py-0.5 transition"
              style={{
                background: on ? t.color : 'transparent',
                color: on ? pickReadable(t.color) : 'rgb(var(--persona-text) / 0.6)',
                border: `1px solid ${on ? t.color : 'rgb(0 0 0 / 0.15)'}`,
              }}
            >
              #{t.name}
            </button>
          );
        })}
      </div>
    </div>
  );
}

function pickReadable(hex: string): string {
  const m = hex.match(/^#?([\da-f]{2})([\da-f]{2})([\da-f]{2})$/i);
  if (!m) return 'black';
  const r = parseInt(m[1], 16), g = parseInt(m[2], 16), b = parseInt(m[3], 16);
  const luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return luma > 0.6 ? '#3a1431' : 'white';
}

function fmtDateTime(iso: string): string {
  const d = new Date(iso.replace(' ', 'T') + 'Z');
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString(undefined, { year: 'numeric', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
}
