import { useState } from 'react';
import type { Customer } from '../../data/customers';
import {
  deleteCustomer,
  setCustomerInterests,
  setCustomerProducts,
  updateCustomer,
} from '../../data/customers';
import type { TaxonomyItem } from '../../data/taxonomy';
import type { Persona as PersonaRow } from '../../data/personas';
import { ChipMultiSelect } from '../../components/ChipMultiSelect';
import { ConfirmButton } from '../../components/ConfirmButton';
import { RichTextNotes } from '../../components/RichTextNotes';

interface Props {
  customer: Customer;
  productIds: number[];
  interestIds: number[];
  products: TaxonomyItem[];
  interests: TaxonomyItem[];
  personas: PersonaRow[];
  onClose: () => Promise<void> | void;
}

export function CustomerEditor({ customer, productIds, interestIds, products, interests, personas, onClose }: Props) {
  const [draft, setDraft] = useState<Customer>(customer);
  const [products$, setProducts$] = useState<number[]>(productIds);
  const [interests$, setInterests$] = useState<number[]>(interestIds);
  const [status, setStatus] = useState<string>('');
  const [dirty, setDirty] = useState(false);

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
    try {
      await updateCustomer(draft);
      await setCustomerProducts(draft.uid, products$);
      await setCustomerInterests(draft.uid, interests$);
      setStatus(`Saved ${draft.uid}.`);
      setDirty(false);
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    }
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
  const personaTint = personas.find((p) => p.code === draft.personaCode);

  return (
    <div className="p-8 max-w-4xl space-y-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <div className="text-xs opacity-60 font-mono">{draft.uid}</div>
          <h2 className="display-font text-2xl font-bold persona-accent">
            {draft.username || draft.realName || 'New customer'}
          </h2>
        </div>
        <div className="flex items-center gap-2">
          <button type="button" className="pretty-button secondary" onClick={onClose}>← Back</button>
          <button type="button" className="pretty-button" onClick={save} disabled={!dirty}>
            {dirty ? '💾 Save' : 'Saved'}
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
          <div className="text-xs uppercase tracking-wider opacity-60 mb-1">Emails (up to 5)</div>
          <div className="grid grid-cols-1 gap-2">
            {draft.emails.map((email, idx) => (
              <input
                key={idx}
                className="pretty-input"
                placeholder={idx === 0 ? 'Primary email' : `Alt email ${idx}`}
                value={email}
                onChange={(e) => patchEmail(idx as 0 | 1 | 2 | 3 | 4, e.target.value)}
              />
            ))}
          </div>
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
      </div>

      <div className="pretty-card">
        <div className="text-xs uppercase tracking-wider opacity-60 mb-2">Notes</div>
        <RichTextNotes
          value={draft.notesHtml}
          onChange={(html) => patch({ notesHtml: html })}
          placeholder="What do they like, what'd they ask for, what'd they pay? You can use **bold**, headings, bullet lists…"
        />
      </div>

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}
