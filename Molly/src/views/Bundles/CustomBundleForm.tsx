import { useCallback, useEffect, useState } from 'react';
import { db } from '../../data/db';
import {
  type Bundle,
  deleteBundleDraft,
  deleteBundleFile,
  getBundle,
  reorderBundleFiles,
  saveBundleFile,
  updateBundleFields,
} from '../../data/bundles';
import { listPersonas, type Persona } from '../../data/personas';
import { DeliveryField } from './components/DeliveryField';
import { GoLiveDatePicker } from './components/GoLiveDatePicker';
import { OrderedFileList } from './components/OrderedFileList';
import { SpecialInstructionsField } from './components/SpecialInstructionsField';
import { TitleField } from './components/TitleField';

interface Props {
  uid: string;
  onPublishRequested: () => void;
  onClose: () => void;
  onDeleted?: () => void;
  locked?: boolean;
}

function tomorrowIso(): string {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${dd}`;
}

export function CustomBundleForm({ uid, onPublishRequested, onClose, onDeleted, locked }: Props) {
  const [bundle, setBundle] = useState<Bundle | null>(null);
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [priceDraft, setPriceDraft] = useState('');

  const reload = useCallback(async () => {
    const b = await getBundle(uid);
    setBundle(b);
    setPriceDraft(b.priceCents != null ? formatDollars(b.priceCents) : '');
  }, [uid]);

  useEffect(() => {
    let alive = true;
    Promise.all([reload(), listPersonas()])
      .then(([_, p]) => { if (alive) setPersonas(p); })
      .catch((e) => alive && setError(String(e)));
    return () => { alive = false; };
  }, [reload]);

  async function withBusy<T>(fn: () => Promise<T>): Promise<T | null> {
    setBusy(true); setError(null);
    try { return await fn(); }
    catch (e) { setError(stringifyError(e)); return null; }
    finally { setBusy(false); }
  }

  async function setPersona(code: string | null) {
    await withBusy(async () => {
      const conn = await db();
      await conn.execute('UPDATE bundles SET persona_code = $1, updated_at = datetime(\'now\') WHERE uid = $2', [code, uid]);
      await reload();
    });
  }
  async function commitTitle(s: string) {
    await withBusy(async () => { await updateBundleFields(uid, { title: s }); await reload(); });
  }
  async function commitGoLive(s: string | null) {
    await withBusy(async () => { await updateBundleFields(uid, { goLiveDate: s }); await reload(); });
  }
  async function commitSpecial(s: string) {
    await withBusy(async () => { await updateBundleFields(uid, { specialInstructions: s }); await reload(); });
  }
  async function commitRecipient(s: string) {
    await withBusy(async () => { await updateBundleFields(uid, { deliveryRecipient: s }); await reload(); });
  }
  async function commitDeliveryKind(k: 'site' | 'url' | null) {
    await withBusy(async () => { await updateBundleFields(uid, { deliveryKind: k }); await reload(); });
  }
  async function commitDeliverySiteId(id: number | null) {
    await withBusy(async () => { await updateBundleFields(uid, { deliverySiteId: id }); await reload(); });
  }
  async function commitDeliveryUrl(url: string | null) {
    await withBusy(async () => { await updateBundleFields(uid, { deliveryUrl: url }); await reload(); });
  }
  async function commitHandledInPlatform(v: boolean) {
    await withBusy(async () => {
      await updateBundleFields(uid, { handledInPlatform: v });
      if (v) {
        // When handled-in-platform is on, blank the price so the
        // value isn't ambiguous to Robert when he reads info.md later.
        await updateBundleFields(uid, { priceCents: null });
      }
      await reload();
    });
  }
  async function commitPrice() {
    const cents = parseDollars(priceDraft);
    await withBusy(async () => {
      await updateBundleFields(uid, { priceCents: cents });
      await reload();
    });
  }

  async function onPickFiles(srcPaths: string[]) {
    await withBusy(async () => {
      for (const src of srcPaths) {
        const kind: 'video' | 'image' = guessKind(src);
        await saveBundleFile(uid, src, kind, null);
      }
      await reload();
    });
  }
  async function onRemoveFile(id: number) {
    await withBusy(async () => { await deleteBundleFile(id); await reload(); });
  }
  async function onReorderFiles(orderedIds: number[]) {
    await withBusy(async () => { await reorderBundleFiles(uid, orderedIds); await reload(); });
  }

  async function onDeleteDraft() {
    if (locked) return;
    if (!confirm('Delete this draft and all uploaded files? This cannot be undone.')) return;
    const ok = await withBusy(async () => { await deleteBundleDraft(uid); });
    if (ok !== null) { onDeleted?.(); onClose(); }
  }

  if (!bundle) {
    return <div className="p-8 opacity-60 italic">Loading bundle…</div>;
  }

  return (
    <div className="p-8 space-y-5 max-w-3xl">
      <div className="flex items-center justify-between gap-2 -mt-2 mb-1">
        <button type="button" onClick={onClose} className="pretty-button secondary">← Bundles</button>
        {!locked && (
          <button type="button" onClick={onDeleteDraft} className="pretty-button danger text-xs" disabled={busy}>🗑 Delete draft</button>
        )}
      </div>
      <header className="space-y-1">
        <div className="flex items-baseline justify-between gap-3">
          <h2 className="display-font text-2xl font-bold persona-accent">Custom Bundle</h2>
          <span className="text-xs font-mono opacity-60">{uid}</span>
        </div>
        <p className="opacity-70 text-sm">
          A custom video for a specific buyer / platform. Save as you go.
        </p>
        {error && (
          <div className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2">{error}</div>
        )}
      </header>

      <fieldset disabled={locked} className="space-y-5">
        <PersonaPicker personas={personas} value={bundle.summary.personaCode} onChange={setPersona} />

        <TitleField value={bundle.summary.title} onCommit={commitTitle} disabled={busy || locked} />

        <GoLiveDatePicker
          value={bundle.summary.goLiveDate}
          onChange={commitGoLive}
          defaultValue={tomorrowIso()}
          disabled={busy || locked}
        />

        <OrderedFileList
          files={bundle.files}
          pickTitle="Pick videos / images for this custom"
          allowedKinds={['video', 'image']}
          busy={busy}
          onPick={onPickFiles}
          onRemove={onRemoveFile}
          onReorder={onReorderFiles}
        />

        <DeliveryField
          personaCode={bundle.summary.personaCode}
          deliveryKind={bundle.deliveryKind}
          deliverySiteId={bundle.deliverySiteId}
          deliveryUrl={bundle.deliveryUrl}
          onChangeKind={commitDeliveryKind}
          onChangeSiteId={commitDeliverySiteId}
          onChangeUrl={commitDeliveryUrl}
          disabled={busy || locked}
        />

        <div className="space-y-1">
          <label htmlFor="bundle-delivery-recipient" className="text-xs font-semibold opacity-75">Recipient (username / name)</label>
          <input
            id="bundle-delivery-recipient"
            type="text"
            className="pretty-input w-full"
            defaultValue={bundle.deliveryRecipient}
            onBlur={(e) => { if (e.target.value !== bundle.deliveryRecipient) commitRecipient(e.target.value); }}
            placeholder="e.g. @cute_buyer or 'Alice'"
            disabled={busy || locked}
          />
        </div>

        <div className="space-y-1">
          <label className="text-xs font-semibold opacity-75">Price</label>
          <div className="flex items-center gap-3">
            <input
              id="bundle-price"
              type="text"
              inputMode="decimal"
              className="pretty-input w-32 font-mono"
              value={bundle.handledInPlatform ? '' : priceDraft}
              onChange={(e) => setPriceDraft(e.target.value)}
              onBlur={() => { if (parseDollars(priceDraft) !== bundle.priceCents) commitPrice(); }}
              placeholder="$ 0.00"
              disabled={busy || locked || bundle.handledInPlatform}
            />
            <label className="text-sm flex items-center gap-2 select-none">
              <input
                type="checkbox"
                checked={bundle.handledInPlatform}
                onChange={(e) => commitHandledInPlatform(e.target.checked)}
                className="w-4 h-4"
                disabled={busy || locked}
              />
              handled in delivery platform
            </label>
          </div>
        </div>

        <SpecialInstructionsField
          value={bundle.specialInstructions}
          onCommit={commitSpecial}
          disabled={busy || locked}
        />
      </fieldset>

      <div className="flex justify-end gap-2 pt-2 border-t border-black/5">
        <button type="button" onClick={onPublishRequested} className="pretty-button">
          🎁 Review &amp; Publish…
        </button>
      </div>
    </div>
  );
}

function PersonaPicker({
  personas, value, onChange,
}: { personas: Persona[]; value: string | null; onChange: (code: string | null) => void; }) {
  return (
    <div className="space-y-1">
      <label htmlFor="bundle-persona" className="text-xs font-semibold opacity-75">Persona</label>
      <select
        id="bundle-persona"
        className="pretty-input"
        value={value ?? ''}
        onChange={(e) => onChange(e.target.value || null)}
      >
        <option value="">— required —</option>
        {personas.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}
      </select>
    </div>
  );
}

function guessKind(path: string): 'video' | 'image' {
  const ext = (path.split('.').pop() ?? '').toLowerCase();
  return ['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi'].includes(ext) ? 'video' : 'image';
}

function formatDollars(cents: number): string {
  return `${(cents / 100).toFixed(2)}`;
}
function parseDollars(s: string): number | null {
  const cleaned = s.trim().replace(/[$,\s]/g, '');
  if (cleaned === '') return null;
  const f = Number(cleaned);
  if (!Number.isFinite(f) || f < 0) return null;
  return Math.round(f * 100);
}

function stringifyError(e: unknown): string {
  if (typeof e === 'string') return e;
  if (e && typeof e === 'object') {
    const obj = e as { message?: string; kind?: string };
    if (obj.message) return obj.message;
    if (obj.kind === 'validationFailed') return 'Some required fields aren’t filled in yet — open the wizard to see the checklist.';
  }
  return String(e);
}
