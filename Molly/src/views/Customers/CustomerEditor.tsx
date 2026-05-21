import { useEffect, useState } from 'react';
import type { Customer } from '../../data/customers';
import {
  deleteCustomer,
  setCustomerInterests,
  setCustomerKinks,
  setCustomerProducts,
  updateCustomer,
} from '../../data/customers';
import { kinks as kinksApi, type TaxonomyItem } from '../../data/taxonomy';
import { sumTotalCents } from '../../data/customerSales';
import type { Persona as PersonaRow } from '../../data/personas';
import { ChipMultiSelect } from '../../components/ChipMultiSelect';
import { ConfirmButton } from '../../components/ConfirmButton';
import { KinkChipPicker, type KinkOption } from '../../components/KinkChipPicker';
import { RichTextNotes } from '../../components/RichTextNotes';
import { CustomerHistoryCard } from './CustomerHistoryCard';
import { COUNTRIES } from '../../lib/countries';
import { formatUSPhone, isValidUSPhone } from '../../lib/phone';
import { US_STATES } from '../../lib/usStates';

interface Props {
  customer: Customer;
  productIds: number[];
  interestIds: number[];
  kinkIds: number[];
  products: TaxonomyItem[];
  interests: TaxonomyItem[];
  kinks: TaxonomyItem[];
  personas: PersonaRow[];
  onClose: () => Promise<void> | void;
}

export function CustomerEditor({ customer, productIds, interestIds, kinkIds, products, interests, kinks, personas, onClose }: Props) {
  const [draft, setDraft] = useState<Customer>(customer);
  const [products$, setProducts$] = useState<number[]>(productIds);
  const [interests$, setInterests$] = useState<number[]>(interestIds);
  const [kinks$, setKinks$] = useState<number[]>(kinkIds);
  // Local copy of the kinks catalog — seeded from props, augmented when
  // the user creates a new kink inline via KinkChipPicker. Parent re-fetches
  // on close, so this only needs to live for the duration of the edit.
  const [kinksLocal, setKinksLocal] = useState<TaxonomyItem[]>(kinks);
  const [status, setStatus] = useState<string>('');
  const [dirty, setDirty] = useState(false);
  const [saving, setSaving] = useState(false);
  const [lifetimeCents, setLifetimeCents] = useState<number>(0);

  // Pull the customer's lifetime sales total on mount and whenever the
  // history card signals a sales change. Failure is silent — the pill
  // just shows $0.00 if the query throws.
  useEffect(() => {
    void refreshLifetime();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [customer.uid]);

  async function refreshLifetime() {
    try {
      const cents = await sumTotalCents(customer.uid);
      setLifetimeCents(cents);
    } catch {
      setLifetimeCents(0);
    }
  }

  function patch(p: Partial<Customer>) {
    setDraft((d) => ({ ...d, ...p }));
    setDirty(true);
  }
  function patchEmail(idx: 0 | 1 | 2 | 3 | 4, value: string) {
    setDraft((d) => {
      const emails = [...d.emails] as Customer['emails'];
      emails[idx] = value;
      return { ...d, emails };
    });
    setDirty(true);
  }

  async function save() {
    setSaving(true);
    try {
      await updateCustomer(draft);
      await setCustomerProducts(draft.uid, products$);
      await setCustomerInterests(draft.uid, interests$);
      await setCustomerKinks(draft.uid, kinks$);
      setDirty(false);
      setStatus('');
    } catch (e) {
      // Keep dirty=true so the next change retries; surface the error.
      setStatus(`Couldn't save: ${String(e)}`);
    } finally {
      setSaving(false);
    }
  }

  // Debounced auto-save: any dirty change schedules a save 800ms after the
  // user stops typing/clicking. Re-running this effect on every state change
  // resets the timer, so successive edits collapse into one save.
  useEffect(() => {
    if (!dirty || saving) return;
    const t = window.setTimeout(() => { void save(); }, 800);
    return () => window.clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dirty, draft, products$, interests$, kinks$]);

  async function closeWithSaveIfDirty() {
    if (dirty) {
      try { await save(); } catch { /* status carries the error; close anyway */ }
    }
    await onClose();
  }

  async function deleteAndClose() {
    try {
      await deleteCustomer(draft.uid);
      await onClose();
    } catch (e) {
      setStatus(`Couldn't delete: ${String(e)}`);
    }
  }

  const productOptions = products.map((p) => ({ id: p.id, label: p.name, color: p.color }));
  const interestOptions = interests.map((i) => ({ id: i.id, label: i.name, color: i.color }));
  const kinkOptions: KinkOption[] = kinksLocal.map((k) => ({
    id: k.id,
    name: k.name,
    description: k.description ?? '',
    color: k.color,
  }));
  const personaTint = personas.find((p) => p.code === draft.personaCode);

  async function createKinkInline(name: string): Promise<number | null> {
    const trimmed = name.trim();
    if (!trimmed) return null;
    const maxSort = kinksLocal.reduce((m, k) => Math.max(m, k.sortOrder), 0);
    const newId = await kinksApi.create(trimmed, '#EC4899', maxSort + 10);
    setKinksLocal((prev) => [
      ...prev,
      { id: newId, name: trimmed, color: '#EC4899', sortOrder: maxSort + 10, archived: false, description: '' },
    ]);
    setDirty(true);
    return newId;
  }

  return (
    <div className="p-8 max-w-4xl space-y-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <div className="text-xs opacity-60 font-mono">{draft.uid}</div>
          <h2 className="display-font text-2xl font-bold persona-accent flex items-center gap-2">
            {draft.vip && <span title="VIP" aria-label="VIP">⭐</span>}
            {draft.username || draft.realName || 'New customer'}
          </h2>
        </div>
        <div className="flex items-center gap-2 flex-wrap justify-end">
          {lifetimeCents > 0 && (
            <span
              className="px-3 py-1.5 rounded-full text-sm font-semibold"
              style={{
                background: 'rgb(var(--persona-accent))',
                color: 'white',
                boxShadow: '0 3px 8px -4px rgb(var(--persona-accent) / 0.6)',
              }}
              title="Lifetime sales total for this customer"
            >
              💖 ${(lifetimeCents / 100).toFixed(2)}
            </span>
          )}
          <button
            type="button"
            onClick={() => patch({ vip: !draft.vip })}
            className="px-3 py-1.5 rounded-full text-sm font-semibold transition border"
            style={{
              background: draft.vip ? '#FBBF24' : 'transparent',
              borderColor: draft.vip ? '#FBBF24' : 'rgb(var(--persona-primary) / 0.5)',
              color: draft.vip ? '#7C2D12' : 'rgb(var(--persona-text))',
              boxShadow: draft.vip ? '0 3px 8px -4px #FBBF2488' : undefined,
            }}
            title={draft.vip ? 'Click to unset VIP' : 'Click to mark as VIP'}
          >
            {draft.vip ? '⭐ VIP' : '☆ VIP'}
          </button>
          <span className="text-xs opacity-70 mr-1" aria-live="polite">
            {saving ? '💾 Saving…' : dirty ? '✏️ Unsaved — auto-saving…' : '✓ Saved'}
          </span>
          <button type="button" className="pretty-button secondary" onClick={closeWithSaveIfDirty}>← Back</button>
          <button type="button" className="pretty-button" onClick={save} disabled={!dirty || saving}>
            {saving ? 'Saving…' : dirty ? '💾 Save now' : 'Saved'}
          </button>
          <ConfirmButton label="Delete" confirmLabel="Confirm?" onConfirm={deleteAndClose} />
        </div>
      </div>

      <div className="pretty-card space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <label className="flex flex-col gap-1">
            <span className="text-xs uppercase tracking-wider opacity-60">Username</span>
            <input className="pretty-input" value={draft.username} onChange={(e) => patch({ username: e.target.value })} />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-xs uppercase tracking-wider opacity-60">Real name</span>
            <input className="pretty-input" value={draft.realName} onChange={(e) => patch({ realName: e.target.value })} />
          </label>
          <label className="flex flex-col gap-1 col-span-2">
            <span className="text-xs uppercase tracking-wider opacity-60">Persona</span>
            <div className="flex items-center gap-2">
              <select
                className="pretty-input flex-1"
                value={draft.personaCode ?? ''}
                onChange={(e) => patch({ personaCode: e.target.value || null })}
              >
                <option value="">(All — no specific persona)</option>
                {personas.map((p) => <option key={p.code} value={p.code}>{p.code} — {p.name}</option>)}
              </select>
              {personaTint && (
                <span
                  className="px-2 py-1 rounded-md text-xs font-semibold"
                  style={{ background: personaTint.primaryColor, color: personaTint.textColor }}
                >
                  {personaTint.code}
                </span>
              )}
            </div>
          </label>
        </div>

        <div>
          <div className="text-xs uppercase tracking-wider opacity-60 mb-1">
            Emails (up to 5) — select the primary
          </div>
          <div className="grid grid-cols-1 gap-2">
            {draft.emails.map((email, idx) => (
              <label key={idx} className="flex items-center gap-2">
                <input
                  type="radio"
                  name={`primary-email-${draft.uid}`}
                  checked={draft.primaryEmailIndex === idx}
                  onChange={() => patch({ primaryEmailIndex: idx })}
                  title={`Mark email ${idx + 1} as primary`}
                  aria-label={`Mark email ${idx + 1} as primary`}
                />
                <input
                  className="pretty-input flex-1"
                  placeholder={draft.primaryEmailIndex === idx ? 'Primary email' : `Alt email ${idx + 1}`}
                  value={email}
                  onChange={(e) => patchEmail(idx as 0 | 1 | 2 | 3 | 4, e.target.value)}
                />
              </label>
            ))}
          </div>
        </div>

        <div>
          <div className="text-xs uppercase tracking-wider opacity-60 mb-1">
            Phone numbers — check Mobile and select the primary
          </div>
          <div className="grid grid-cols-1 gap-2">
            {[0, 1].map((idx) => {
              const value = idx === 0 ? draft.phone1 : draft.phone2;
              const isMobile = idx === 0 ? draft.phone1IsMobile : draft.phone2IsMobile;
              const isUS = draft.country === 'US';
              const hasValue = value.trim().length > 0;
              const invalid = isUS && hasValue && !isValidUSPhone(value);
              return (
                <div key={idx}>
                  <div className="flex items-center gap-2">
                    <input
                      type="radio"
                      name={`primary-phone-${draft.uid}`}
                      checked={draft.primaryPhoneIndex === idx}
                      onChange={() => patch({ primaryPhoneIndex: idx })}
                      title={`Mark phone ${idx + 1} as primary`}
                      aria-label={`Mark phone ${idx + 1} as primary`}
                    />
                    <input
                      type="tel"
                      inputMode="tel"
                      autoComplete={idx === 0 ? 'tel' : 'off'}
                      className="pretty-input flex-1"
                      placeholder={isUS ? '(555) 123-4567' : '+44 7900 123456'}
                      value={value}
                      onChange={(e) => {
                        // Format-as-you-type for US numbers; let other countries pass through.
                        const v = isUS ? formatUSPhone(e.target.value) : e.target.value;
                        patch(idx === 0 ? { phone1: v } : { phone2: v });
                      }}
                      style={invalid ? { borderColor: '#F59E0B' } : undefined}
                    />
                    <label className="flex items-center gap-1 text-xs whitespace-nowrap select-none">
                      <input
                        type="checkbox"
                        checked={isMobile}
                        onChange={(e) =>
                          patch(idx === 0 ? { phone1IsMobile: e.target.checked } : { phone2IsMobile: e.target.checked })
                        }
                      />
                      📱 Mobile
                    </label>
                  </div>
                  {invalid && (
                    <div className="ml-7 mt-0.5 text-xs" style={{ color: '#B45309' }}>
                      10 digits required for a US number.
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      </div>

      <div className="pretty-card space-y-3">
        <div className="text-xs uppercase tracking-wider opacity-60">Mailing address</div>
        <div className="grid grid-cols-2 gap-3">
          <label className="flex flex-col gap-1 col-span-2">
            <span className="text-xs opacity-60">Address line 1</span>
            <input className="pretty-input" value={draft.address1} onChange={(e) => patch({ address1: e.target.value })} />
          </label>
          <label className="flex flex-col gap-1 col-span-2">
            <span className="text-xs opacity-60">Address line 2</span>
            <input className="pretty-input" value={draft.address2} onChange={(e) => patch({ address2: e.target.value })} placeholder="Apt, suite, etc. (optional)" />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-xs opacity-60">City</span>
            <input className="pretty-input" value={draft.city} onChange={(e) => patch({ city: e.target.value })} />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-xs opacity-60">State / Province</span>
            {draft.country === 'US' ? (
              <select
                className="pretty-input"
                value={draft.state}
                onChange={(e) => patch({ state: e.target.value })}
              >
                <option value="">— Select state —</option>
                {US_STATES.map((s) => (
                  <option key={s.code} value={s.code}>{s.code} — {s.name}</option>
                ))}
              </select>
            ) : (
              <input className="pretty-input" value={draft.state} onChange={(e) => patch({ state: e.target.value })} />
            )}
          </label>
          {draft.country === 'US' ? (
            <div className="grid grid-cols-3 gap-2 col-span-1">
              <label className="flex flex-col gap-1 col-span-2">
                <span className="text-xs opacity-60">Zip</span>
                <input className="pretty-input" value={draft.zip} onChange={(e) => patch({ zip: e.target.value })} />
              </label>
              <label className="flex flex-col gap-1">
                <span className="text-xs opacity-60">+4</span>
                <input className="pretty-input" value={draft.zip4} onChange={(e) => patch({ zip4: e.target.value })} />
              </label>
            </div>
          ) : (
            <label className="flex flex-col gap-1">
              <span className="text-xs opacity-60">Postal code</span>
              <input className="pretty-input" value={draft.zip} onChange={(e) => patch({ zip: e.target.value })} />
            </label>
          )}
          <label className="flex flex-col gap-1">
            <span className="text-xs opacity-60">Country</span>
            <select
              className="pretty-input"
              value={draft.country}
              onChange={(e) => patch({ country: e.target.value })}
            >
              {COUNTRIES.slice(0, 3).map((c) => (
                <option key={c.code} value={c.code}>{c.code} — {c.name}</option>
              ))}
              <option disabled>──────────</option>
              {COUNTRIES.slice(3).map((c) => (
                <option key={c.code} value={c.code}>{c.code} — {c.name}</option>
              ))}
            </select>
          </label>
        </div>
      </div>

      <div className="pretty-card space-y-3">
        <div>
          <div className="text-xs uppercase tracking-wider opacity-60 mb-1">Products</div>
          <ChipMultiSelect
            options={productOptions}
            selected={products$}
            onChange={(ids) => { setProducts$(ids); setDirty(true); }}
            emptyMessage="No products yet — add some in Settings → Products."
          />
        </div>
        <div>
          <div className="text-xs uppercase tracking-wider opacity-60 mb-1">Interests</div>
          <ChipMultiSelect
            options={interestOptions}
            selected={interests$}
            onChange={(ids) => { setInterests$(ids); setDirty(true); }}
            emptyMessage="No interests yet — add some in Settings → Interests."
          />
        </div>
        <div>
          <div className="text-xs uppercase tracking-wider opacity-60 mb-1">Kinks</div>
          <KinkChipPicker
            options={kinkOptions}
            selected={kinks$}
            onChange={(ids) => { setKinks$(ids); setDirty(true); }}
            onCreateKink={createKinkInline}
          />
        </div>
      </div>

      <div className="pretty-card">
        <div className="text-xs uppercase tracking-wider opacity-60 mb-2">Notes</div>
        <RichTextNotes
          value={draft.notesHtml}
          onChange={(html) => patch({ notesHtml: html })}
          placeholder="What do they like, what'd they ask for, what'd they pay? You can use **bold**, headings, bullet lists…"
        />
      </div>

      <CustomerHistoryCard
        customerUid={draft.uid}
        products={products}
        onSalesChanged={refreshLifetime}
      />

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}
