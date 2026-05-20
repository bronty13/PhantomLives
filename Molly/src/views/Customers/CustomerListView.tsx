import { useState } from 'react';
import type { Persona } from '../../state/personas';
import {
  createCustomer,
  getCustomer,
  getCustomerInterestIds,
  getCustomerProductIds,
  listCustomers,
  type Customer,
  type CustomerSummary,
} from '../../data/customers';
import { CustomerEditor } from './CustomerEditor';
import { nextCustomerUid } from '../../lib/uid';
import { interests as interestsApi, products as productsApi, type TaxonomyItem } from '../../data/taxonomy';
import { listPersonas, type Persona as PersonaRow } from '../../data/personas';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';

interface Props {
  active: Persona;
}

const EMPTY_CUSTOMER = (uid: string, personaCode: string | null): Customer => ({
  uid,
  personaCode,
  username: '',
  realName: '',
  emails: ['', '', '', '', ''],
  notesHtml: '',
  archived: false,
  createdAt: '',
  updatedAt: '',
});

export function CustomerListView({ active }: Props) {
  const [summaries, setSummaries] = useState<CustomerSummary[]>([]);
  const [search, setSearch] = useState('');
  const [products, setProducts] = useState<TaxonomyItem[]>([]);
  const [interests, setInterests] = useState<TaxonomyItem[]>([]);
  const [personas, setPersonas] = useState<PersonaRow[]>([]);
  const [editor, setEditor] = useState<{ customer: Customer; productIds: number[]; interestIds: number[] } | null>(null);
  const [status, setStatus] = useState<string>('');

  const { loading, refresh } = useAsyncRefresh(async (alive) => {
    const [s, p, i, pe] = await Promise.all([
      listCustomers({ personaCode: active.code, search }),
      productsApi.list(),
      interestsApi.list(),
      listPersonas(),
    ]);
    if (!alive()) return;
    setSummaries(s);
    setProducts(p);
    setInterests(i);
    setPersonas(pe);
  }, [active.code]);

  async function addCustomer() {
    try {
      const uid = await nextCustomerUid();
      const personaCode = active.code === 'ALL' ? null : active.code;
      const c = EMPTY_CUSTOMER(uid, personaCode);
      await createCustomer(c);
      setEditor({ customer: c, productIds: [], interestIds: [] });
      await refresh();
    } catch (e) {
      setStatus(`Couldn't add customer: ${String(e)}`);
    }
  }

  async function openCustomer(uid: string) {
    const c = await getCustomer(uid);
    if (!c) return;
    const [pIds, iIds] = await Promise.all([getCustomerProductIds(uid), getCustomerInterestIds(uid)]);
    setEditor({ customer: c, productIds: pIds, interestIds: iIds });
  }

  if (editor) {
    return (
      <CustomerEditor
        customer={editor.customer}
        productIds={editor.productIds}
        interestIds={editor.interestIds}
        products={products}
        interests={interests}
        personas={personas}
        onClose={async () => {
          setEditor(null);
          try { await refresh(); } catch (e) { setStatus(String(e)); }
        }}
      />
    );
  }

  return (
    <div className="p-8 max-w-5xl space-y-4">
      <div className="flex items-end justify-between gap-3">
        <div>
          <h2 className="display-font text-2xl font-bold persona-accent">Customers</h2>
          <p className="opacity-70 text-sm">
            {active.code === 'ALL' ? 'All customers across personas.' : `${active.name} customers.`}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <input
            className="pretty-input w-64"
            placeholder="Search by name, username, UID…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') refresh(); }}
            onBlur={refresh}
          />
          <button type="button" className="pretty-button" onClick={addCustomer}>✨ Add customer</button>
        </div>
      </div>

      <div className="pretty-card">
        {loading && (
          <div className="text-sm opacity-60 italic">Loading customers…</div>
        )}
        {!loading && summaries.length === 0 && (
          <div className="text-sm opacity-70 italic">No customers yet. Click <strong>Add customer</strong> to create one.</div>
        )}
        <div className="space-y-1.5">
          {summaries.map((c) => {
            const persona = personas.find((p) => p.code === c.personaCode);
            return (
              <button
                key={c.uid}
                type="button"
                onClick={() => openCustomer(c.uid)}
                className="w-full text-left p-3 rounded-xl flex items-center justify-between gap-3 transition hover:bg-white"
                style={{ background: 'rgb(var(--persona-tint))', border: '1px solid rgb(var(--persona-primary) / 0.3)' }}
              >
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-mono text-xs opacity-60">{c.uid}</span>
                    {persona && (
                      <span
                        className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold"
                        style={{ background: persona.primaryColor, color: persona.textColor }}
                      >
                        {persona.code}
                      </span>
                    )}
                  </div>
                  <div className="font-semibold mt-0.5">
                    {c.username || c.realName || '(unnamed)'}
                  </div>
                  {c.primaryEmail && <div className="text-xs opacity-70">{c.primaryEmail}</div>}
                </div>
                <div className="flex items-center gap-1 text-[11px] opacity-70">
                  {c.productCount > 0 && <span>{c.productCount} product{c.productCount === 1 ? '' : 's'}</span>}
                  {c.productCount > 0 && c.interestCount > 0 && <span>·</span>}
                  {c.interestCount > 0 && <span>{c.interestCount} interest{c.interestCount === 1 ? '' : 's'}</span>}
                </div>
              </button>
            );
          })}
        </div>
      </div>
      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}
