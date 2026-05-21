import { useState } from 'react';
import { open as openOpenDialog, save as openSaveDialog } from '@tauri-apps/plugin-dialog';
import {
  addEntry,
  addEntryWithAttachment,
  deleteEntry,
  downloadAttachment,
  listEntries,
  updateEntry,
  type HistoryEntry,
} from '../../data/customerHistory';
import { deleteSale, listSales, type Sale } from '../../data/customerSales';
import type { TaxonomyItem } from '../../data/taxonomy';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';
import { ConfirmButton } from '../../components/ConfirmButton';
import { CustomerSaleEditor } from './CustomerSaleEditor';

interface Props {
  customerUid: string;
  products: TaxonomyItem[];
  onSalesChanged?: () => Promise<void> | void;
}

// SQLite's `datetime('now')` returns "YYYY-MM-DD HH:MM:SS" in UTC with no
// timezone marker. Appending 'Z' tells the Date parser it's UTC so
// toLocaleString shows the right wall-clock time.
function parseSqliteUtc(s: string): Date {
  return new Date(s.replace(' ', 'T') + 'Z');
}

function formatTs(iso: string): string {
  return parseSqliteUtc(iso).toLocaleString(undefined, {
    month: 'short', day: 'numeric', year: 'numeric',
    hour: 'numeric', minute: '2-digit',
  });
}

// Sales are date-only entries — the time is meaningless noise.
function formatTsDateOnly(iso: string): string {
  return parseSqliteUtc(iso).toLocaleDateString(undefined, {
    month: 'short', day: 'numeric', year: 'numeric',
  });
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

function formatMoney(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`;
}

function basename(path: string): string {
  const parts = path.split(/[/\\]/);
  return parts[parts.length - 1] || path;
}

// One entry on the merged timeline. Sort key is the customer-visible
// timestamp (ts for notes, sale_date for sales).
type TimelineItem =
  | { kind: 'history'; ts: string; entry: HistoryEntry }
  | { kind: 'sale';    ts: string; sale: Sale };

export function CustomerHistoryCard({ customerUid, products, onSalesChanged }: Props) {
  const [entries, setEntries] = useState<HistoryEntry[]>([]);
  const [sales, setSales] = useState<Sale[]>([]);
  const [body, setBody] = useState('');
  const [attachmentPath, setAttachmentPath] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState('');
  // null = no sale form; 'new' = composing a new sale; { editId } = editing an existing one.
  const [saleForm, setSaleForm] = useState<null | { mode: 'new' } | { mode: 'edit'; saleId: number }>(null);
  // Inline edit state for note rows. `editingNoteId` identifies the entry
  // being revised; `editingBody` is the in-flight buffer for that note.
  const [editingNoteId, setEditingNoteId] = useState<number | null>(null);
  const [editingBody, setEditingBody] = useState('');
  // Per-customer timeline filter. `useRegex` switches between case-insensitive
  // substring match and a real RegExp (with an inline error if invalid).
  const [filterText, setFilterText] = useState('');
  const [useRegex, setUseRegex] = useState(false);

  const { loading, refresh } = useAsyncRefresh(async (alive) => {
    const [h, s] = await Promise.all([listEntries(customerUid), listSales(customerUid)]);
    if (!alive()) return;
    setEntries(h);
    setSales(s);
  }, [customerUid]);

  async function pickFile() {
    try {
      const result = await openOpenDialog({ multiple: false });
      if (typeof result === 'string') setAttachmentPath(result);
    } catch (e) {
      setStatus(`Couldn't pick file: ${String(e)}`);
    }
  }

  async function addToHistory() {
    const text = body.trim();
    if (!text && !attachmentPath) return;
    setBusy(true);
    setStatus('');
    try {
      if (attachmentPath) {
        await addEntryWithAttachment(customerUid, text, attachmentPath);
      } else {
        await addEntry(customerUid, text);
      }
      setBody('');
      setAttachmentPath(null);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't add: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  async function downloadEntryAttachment(entry: HistoryEntry) {
    try {
      const targetPath = await openSaveDialog({ defaultPath: entry.attachmentFilename });
      if (!targetPath) return;
      await downloadAttachment(entry.id, targetPath);
      setStatus(`Saved ${entry.attachmentFilename}.`);
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    }
  }

  async function onSaleSaved() {
    setSaleForm(null);
    await refresh();
    if (onSalesChanged) await onSalesChanged();
  }

  async function removeSale(sale: Sale) {
    try {
      await deleteSale(sale.id);
      await refresh();
      if (onSalesChanged) await onSalesChanged();
    } catch (e) {
      setStatus(`Couldn't delete sale: ${String(e)}`);
    }
  }

  function startEditNote(entry: HistoryEntry) {
    setEditingNoteId(entry.id);
    setEditingBody(entry.body);
  }

  async function saveEditNote() {
    if (editingNoteId == null) return;
    setBusy(true);
    setStatus('');
    try {
      await updateEntry(editingNoteId, editingBody);
      setEditingNoteId(null);
      setEditingBody('');
      await refresh();
    } catch (e) {
      setStatus(`Couldn't save note: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  async function removeNote(entry: HistoryEntry) {
    try {
      await deleteEntry(entry.id);
      if (editingNoteId === entry.id) setEditingNoteId(null);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't delete note: ${String(e)}`);
    }
  }

  const canSubmit = (body.trim().length > 0 || !!attachmentPath) && !busy;

  // Merge + sort newest-first.
  const items: TimelineItem[] = [
    ...entries.map((e) => ({ kind: 'history' as const, ts: e.ts, entry: e })),
    ...sales.map((s)   => ({ kind: 'sale'    as const, ts: s.saleDate, sale: s })),
  ].sort((a, b) => b.ts.localeCompare(a.ts));

  // Build a single matcher function once. Filter applies to: note body,
  // note attachment filename, sale notes, and sale product name.
  const q = filterText.trim();
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

  const filteredItems = matcher
    ? items.filter((item) => {
        if (item.kind === 'history') {
          return (
            matcher!(item.entry.body) ||
            matcher!(item.entry.attachmentFilename)
          );
        }
        const product = products.find((p) => p.id === item.sale.productId);
        return matcher!(item.sale.notes) || matcher!(product?.name ?? '');
      })
    : items;

  return (
    <div className="pretty-card space-y-3">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div className="min-w-0">
          <div className="text-xs uppercase tracking-wider opacity-60">History &amp; sales</div>
          <p className="text-xs opacity-60 mt-0.5">
            Newest first. Both notes and sales can be edited or deleted.
          </p>
        </div>
        <button
          type="button"
          className="pretty-button secondary"
          onClick={() => setSaleForm(saleForm?.mode === 'new' ? null : { mode: 'new' })}
          disabled={busy}
        >
          🛒 {saleForm?.mode === 'new' ? 'Cancel' : '+ Add sale'}
        </button>
      </div>

      {saleForm?.mode === 'new' && (
        <CustomerSaleEditor
          customerUid={customerUid}
          products={products}
          onSaved={onSaleSaved}
          onCancel={() => setSaleForm(null)}
        />
      )}

      <div className="space-y-2 p-3 rounded-xl bg-white border border-black/5">
        <textarea
          className="pretty-input w-full"
          rows={3}
          placeholder="Add a note for this customer…"
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
          <button type="button" className="pretty-button" onClick={addToHistory} disabled={!canSubmit}>
            {busy ? 'Adding…' : '➕ Add note'}
          </button>
        </div>
      </div>

      <div className="flex items-center gap-2 flex-wrap">
        <input
          type="text"
          className="pretty-input flex-1"
          placeholder={useRegex ? 'Regex pattern (case-insensitive)…' : 'Filter notes & sales…'}
          value={filterText}
          onChange={(e) => setFilterText(e.target.value)}
        />
        <label className="flex items-center gap-1 text-xs select-none whitespace-nowrap">
          <input
            type="checkbox"
            checked={useRegex}
            onChange={(e) => setUseRegex(e.target.checked)}
          />
          regex
        </label>
        {q && !regexError && (
          <div className="text-xs opacity-60 whitespace-nowrap">
            {filteredItems.length} of {items.length}
          </div>
        )}
        {q && (
          <button type="button" className="pretty-button secondary" onClick={() => setFilterText('')}>
            Clear
          </button>
        )}
      </div>
      {regexError && (
        <div className="text-xs" style={{ color: '#B45309' }}>Invalid regex: {regexError}</div>
      )}

      {loading && <div className="text-sm opacity-60 italic">Loading timeline…</div>}
      {!loading && items.length === 0 && (
        <div className="text-sm opacity-70 italic">
          No history yet — your first note or sale will appear here, newest first.
        </div>
      )}
      {!loading && items.length > 0 && filteredItems.length === 0 && (
        <div className="text-sm opacity-70 italic">No timeline entries match "{q}".</div>
      )}

      <div className="space-y-2">
        {filteredItems.map((item) => {
          if (item.kind === 'history') {
            const e = item.entry;
            const isEditingThisNote = editingNoteId === e.id;
            return (
              <div
                key={`h-${e.id}`}
                className="p-3 rounded-xl border border-black/5"
                style={{ background: 'rgb(var(--persona-tint))' }}
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 flex-1">
                    <div className="text-[11px] opacity-60 mb-1 font-mono">{formatTs(e.ts)}</div>
                    {isEditingThisNote ? (
                      <textarea
                        className="pretty-input w-full"
                        rows={3}
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
                    {isEditingThisNote ? (
                      <>
                        <button
                          type="button"
                          className="pretty-button secondary"
                          onClick={() => { setEditingNoteId(null); setEditingBody(''); }}
                          disabled={busy}
                        >
                          Cancel
                        </button>
                        <button
                          type="button"
                          className="pretty-button"
                          onClick={saveEditNote}
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
                          onClick={() => startEditNote(e)}
                          disabled={busy || editingNoteId !== null}
                        >
                          Edit
                        </button>
                        <ConfirmButton label="Delete" confirmLabel="Confirm?" onConfirm={() => removeNote(e)} />
                      </>
                    )}
                  </div>
                </div>
              </div>
            );
          }
          // Sale row
          const s = item.sale;
          const product = products.find((p) => p.id === s.productId);
          const productName = product?.name ?? `Product #${s.productId}`;
          const unit = product?.unit ?? 'item';
          const unitDisplay = s.quantity === 1 ? unit : `${unit}s`;
          const isEditing = saleForm?.mode === 'edit' && saleForm.saleId === s.id;

          if (isEditing) {
            return (
              <CustomerSaleEditor
                key={`s-${s.id}`}
                customerUid={customerUid}
                products={products}
                initial={s}
                onSaved={onSaleSaved}
                onCancel={() => setSaleForm(null)}
              />
            );
          }

          return (
            <div
              key={`s-${s.id}`}
              className="p-3 rounded-xl border"
              style={{
                background: 'rgb(var(--persona-tint))',
                borderColor: 'rgb(var(--persona-primary) / 0.5)',
              }}
            >
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0 flex-1">
                  <div className="text-[11px] opacity-60 mb-1 font-mono">{formatTsDateOnly(s.saleDate)}</div>
                  <div className="text-sm font-semibold">
                    🛒 {productName} · {s.quantity} {unitDisplay} · {formatMoney(s.totalCents)}
                  </div>
                  {s.totalCents !== Math.round(s.quantity * s.unitPriceCents) && (
                    <div className="text-[11px] opacity-60 mt-0.5">
                      ({formatMoney(s.unitPriceCents)} / {unit} × {s.quantity} = {formatMoney(Math.round(s.quantity * s.unitPriceCents))}, adjusted to {formatMoney(s.totalCents)})
                    </div>
                  )}
                  {s.notes && <div className="text-sm opacity-80 mt-1 whitespace-pre-wrap">{s.notes}</div>}
                </div>
                <div className="flex items-center gap-1 shrink-0">
                  <button
                    type="button"
                    className="pretty-button secondary"
                    onClick={() => setSaleForm({ mode: 'edit', saleId: s.id })}
                    disabled={busy}
                  >
                    Edit
                  </button>
                  <ConfirmButton label="Delete" confirmLabel="Confirm?" onConfirm={() => removeSale(s)} />
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {status && <div className="text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}
