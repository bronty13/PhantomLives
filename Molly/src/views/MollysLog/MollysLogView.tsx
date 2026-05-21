import { useState } from 'react';
import { open as openOpenDialog, save as openSaveDialog } from '@tauri-apps/plugin-dialog';
import {
  addEntry,
  addEntryWithAttachment,
  deleteEntry,
  downloadAttachment,
  listEntries,
  updateEntry,
  type LogEntry,
} from '../../data/mollysLog';
import { ConfirmButton } from '../../components/ConfirmButton';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';

// SQLite's datetime('now') returns "YYYY-MM-DD HH:MM:SS" UTC with no
// timezone marker; appending 'Z' so toLocaleString shows the right
// wall-clock time. Same trick as in CustomerHistoryCard.
function parseSqliteUtc(s: string): Date {
  return new Date(s.replace(' ', 'T') + 'Z');
}

function formatTs(iso: string): string {
  return parseSqliteUtc(iso).toLocaleString(undefined, {
    month: 'short', day: 'numeric', year: 'numeric',
    hour: 'numeric', minute: '2-digit',
  });
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

function basename(path: string): string {
  const parts = path.split(/[/\\]/);
  return parts[parts.length - 1] || path;
}

// Captain's-log opener for fun — stardate-style preamble when the
// composer is empty. Encourages writing without dictating a format.
const PROMPTS = [
  "Captain's log…",
  "Personal log, supplemental…",
  "First officer's log…",
  "Stardate today — note to self…",
  "End-of-day reflection…",
];

export function MollysLogView() {
  const [entries, setEntries] = useState<LogEntry[]>([]);
  const [body, setBody] = useState('');
  const [attachmentPath, setAttachmentPath] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState('');
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editingBody, setEditingBody] = useState('');
  const [filter, setFilter] = useState('');
  const [useRegex, setUseRegex] = useState(false);
  // Rotates the placeholder on each mount — small touch.
  const [prompt] = useState(() => PROMPTS[Math.floor(Math.random() * PROMPTS.length)]);

  const { loading, refresh } = useAsyncRefresh(async (alive) => {
    const list = await listEntries();
    if (!alive()) return;
    setEntries(list);
  }, []);

  async function pickFile() {
    try {
      const result = await openOpenDialog({ multiple: false });
      if (typeof result === 'string') setAttachmentPath(result);
    } catch (e) {
      setStatus(`Couldn't pick file: ${String(e)}`);
    }
  }

  async function add() {
    const text = body.trim();
    if (!text && !attachmentPath) return;
    setBusy(true);
    setStatus('');
    try {
      if (attachmentPath) {
        await addEntryWithAttachment(text, attachmentPath);
      } else {
        await addEntry(text);
      }
      setBody('');
      setAttachmentPath(null);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't log: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  function startEdit(entry: LogEntry) {
    setEditingId(entry.id);
    setEditingBody(entry.body);
  }

  async function saveEdit() {
    if (editingId == null) return;
    setBusy(true);
    setStatus('');
    try {
      await updateEntry(editingId, editingBody);
      setEditingId(null);
      setEditingBody('');
      await refresh();
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  async function removeEntry(entry: LogEntry) {
    try {
      await deleteEntry(entry.id);
      if (editingId === entry.id) setEditingId(null);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't delete: ${String(e)}`);
    }
  }

  async function downloadEntryAttachment(entry: LogEntry) {
    try {
      const targetPath = await openSaveDialog({ defaultPath: entry.attachmentFilename });
      if (!targetPath) return;
      await downloadAttachment(entry.id, targetPath);
      setStatus(`Saved ${entry.attachmentFilename}.`);
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    }
  }

  // Filter (substring or regex).
  const q = filter.trim();
  let matcher: ((s: string) => boolean) | null = null;
  let regexError: string | null = null;
  if (q) {
    if (useRegex) {
      try {
        const re = new RegExp(q, 'i');
        matcher = (s) => re.test(s);
      } catch (e) {
        regexError = String(e).replace(/^SyntaxError:\s*/, '');
      }
    } else {
      const lower = q.toLowerCase();
      matcher = (s) => s.toLowerCase().includes(lower);
    }
  }
  const filteredEntries = matcher
    ? entries.filter((e) => matcher!(e.body) || matcher!(e.attachmentFilename))
    : entries;

  const canSubmit = (body.trim().length > 0 || !!attachmentPath) && !busy;

  return (
    <div className="p-8 max-w-4xl space-y-4">
      <div>
        <h2 className="display-font text-2xl font-bold persona-accent">📔 Molly's Log</h2>
        <p className="opacity-70 text-sm">
          Your captain's-log style journal. Append entries with optional file attachments; edit or delete any past entry. Persists in Molly's database (auto-backed-up nightly).
        </p>
      </div>

      <div className="pretty-card space-y-3">
        <div className="space-y-2 p-3 rounded-xl bg-white border border-black/5">
          <textarea
            className="pretty-input w-full"
            rows={4}
            placeholder={prompt}
            value={body}
            onChange={(e) => setBody(e.target.value)}
            disabled={busy}
          />
          <div className="flex items-center gap-2 flex-wrap">
            <button type="button" className="pretty-button secondary" onClick={pickFile} disabled={busy}>
              📎 Attach file…
            </button>
            {attachmentPath && (
              <span
                className="inline-flex items-center gap-1.5 px-2 py-1 rounded-full text-xs"
                style={{ background: 'rgb(var(--persona-tint))', border: '1px solid rgb(var(--persona-primary) / 0.4)' }}
              >
                📎 {basename(attachmentPath)}
                <button
                  type="button"
                  onClick={() => setAttachmentPath(null)}
                  className="opacity-70 hover:opacity-100 ml-0.5"
                  aria-label="Remove attachment"
                  title="Remove attachment"
                  disabled={busy}
                >
                  ×
                </button>
              </span>
            )}
            <span className="flex-1" />
            <button type="button" className="pretty-button" onClick={add} disabled={!canSubmit}>
              {busy ? 'Logging…' : '🖖 Log entry'}
            </button>
          </div>
        </div>

        <div className="flex items-center gap-2 flex-wrap">
          <input
            type="text"
            className="pretty-input flex-1"
            placeholder={useRegex ? 'Regex pattern (case-insensitive)…' : 'Filter log entries…'}
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
          />
          <label className="flex items-center gap-1 text-xs select-none whitespace-nowrap">
            <input
              type="checkbox"
              checked={useRegex}
              onChange={(e) => setUseRegex(e.target.checked)}
            />
            grep
          </label>
          {q && !regexError && (
            <div className="text-xs opacity-60 whitespace-nowrap">{filteredEntries.length} of {entries.length}</div>
          )}
          {q && (
            <button type="button" className="pretty-button secondary" onClick={() => setFilter('')}>Clear</button>
          )}
        </div>
        {regexError && (
          <div className="text-xs" style={{ color: '#B45309' }}>Invalid regex: {regexError}</div>
        )}

        {loading && <div className="text-sm opacity-60 italic">Loading log…</div>}
        {!loading && entries.length === 0 && (
          <div className="text-sm opacity-70 italic">No log entries yet — your first entry will appear here, newest first.</div>
        )}
        {!loading && entries.length > 0 && filteredEntries.length === 0 && (
          <div className="text-sm opacity-70 italic">No log entries match "{q}".</div>
        )}

        <div className="space-y-2">
          {filteredEntries.map((e) => {
            const isEditingThis = editingId === e.id;
            return (
              <div
                key={e.id}
                className="p-3 rounded-xl border border-black/5"
                style={{ background: 'rgb(var(--persona-tint))' }}
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 flex-1">
                    <div className="text-[11px] opacity-60 mb-1 font-mono">{formatTs(e.ts)}</div>
                    {isEditingThis ? (
                      <textarea
                        className="pretty-input w-full"
                        rows={4}
                        value={editingBody}
                        onChange={(ev) => setEditingBody(ev.target.value)}
                        disabled={busy}
                      />
                    ) : (
                      e.body && <div className="text-sm whitespace-pre-wrap">{e.body}</div>
                    )}
                    {e.hasAttachment && (
                      <div className="mt-2">
                        <button
                          type="button"
                          onClick={() => downloadEntryAttachment(e)}
                          className="inline-flex items-center gap-1.5 px-2 py-1 rounded-full text-xs hover:opacity-80 transition"
                          style={{ background: 'white', border: '1px solid rgb(var(--persona-primary) / 0.4)' }}
                          title={`Download ${e.attachmentFilename}`}
                        >
                          📎 {e.attachmentFilename}
                          <span className="opacity-60">({formatSize(e.attachmentSize)})</span>
                        </button>
                      </div>
                    )}
                  </div>
                  <div className="flex items-center gap-1 shrink-0">
                    {isEditingThis ? (
                      <>
                        <button
                          type="button"
                          className="pretty-button secondary"
                          onClick={() => { setEditingId(null); setEditingBody(''); }}
                          disabled={busy}
                        >
                          Cancel
                        </button>
                        <button
                          type="button"
                          className="pretty-button"
                          onClick={saveEdit}
                          disabled={busy}
                        >
                          {busy ? 'Saving…' : '💾 Save'}
                        </button>
                      </>
                    ) : (
                      <>
                        <button
                          type="button"
                          className="pretty-button secondary"
                          onClick={() => startEdit(e)}
                          disabled={busy || editingId !== null}
                        >
                          Edit
                        </button>
                        <ConfirmButton label="Delete" confirmLabel="Confirm?" onConfirm={() => removeEntry(e)} />
                      </>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
        </div>

        {status && <div className="text-sm"><strong>Status:</strong> {status}</div>}
      </div>
    </div>
  );
}
