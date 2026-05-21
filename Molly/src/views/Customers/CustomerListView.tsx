import { useState } from 'react';
import type { Persona } from '../../state/personas';
import {
  createCustomer,
  getCustomer,
  getCustomerInterestIds,
  getCustomerKinkIds,
  getCustomerProductIds,
  listCustomers,
  type Customer,
  type CustomerSummary,
} from '../../data/customers';
import { CustomerEditor } from './CustomerEditor';
import { nextCustomerUid } from '../../lib/uid';
import { interests as interestsApi, kinks as kinksApi, products as productsApi, type TaxonomyItem } from '../../data/taxonomy';
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
  primaryEmailIndex: 0,
  notesHtml: '',
  archived: false,
  vip: false,
  address1: '',
  address2: '',
  city: '',
  state: '',
  zip: '',
  zip4: '',
  country: 'US',
  phone1: '',
  phone1IsMobile: false,
  phone2: '',
  phone2IsMobile: false,
  primaryPhoneIndex: 0,
  createdAt: '',
  updatedAt: '',
});

export function CustomerListView({ active }: Props) {
  const [summaries, setSummaries] = useState<CustomerSummary[]>([]);
  const [search, setSearch] = useState('');
  const [useRegex, setUseRegex] = useState(false);
  const [products, setProducts] = useState<TaxonomyItem[]>([]);
  const [interests, setInterests] = useState<TaxonomyItem[]>([]);
  const [kinks, setKinks] = useState<TaxonomyItem[]>([]);
  const [personas, setPersonas] = useState<PersonaRow[]>([]);
  const [editor, setEditor] = useState<{ customer: Customer; productIds: number[]; interestIds: number[]; kinkIds: number[] } | null>(null);
  const [status, setStatus] = useState<string>('');

  // Filter customer-side so regex mode and substring mode share one UX (as
  // you type, no Enter/blur required). Persona scoping still happens in SQL.
  const { loading, refresh } = useAsyncRefresh(async (alive) => {
    const [s, p, i, k, pe] = await Promise.all([
      listCustomers({ personaCode: active.code }),
      productsApi.list(),
      interestsApi.list(),
      kinksApi.list(),
      listPersonas(),
    ]);
    if (!alive()) return;
    setSummaries(s);
    setProducts(p);
    setInterests(i);
    setKinks(k);
    setPersonas(pe);
  }, [active.code]);

  async function addCustomer() {
    try {
      const uid = await nextCustomerUid();
      const personaCode = active.code === 'ALL' ? null : active.code;
      const c = EMPTY_CUSTOMER(uid, personaCode);
      await createCustomer(c);
      setEditor({ customer: c, productIds: [], interestIds: [], kinkIds: [] });
      await refresh();
    } catch (e) {
      setStatus(`Couldn't add customer: ${String(e)}`);
    }
  }

  async function openCustomer(uid: string) {
    const c = await getCustomer(uid);
    if (!c) return;
    const [pIds, iIds, kIds] = await Promise.all([
      getCustomerProductIds(uid),
      getCustomerInterestIds(uid),
      getCustomerKinkIds(uid),
    ]);
    setEditor({ customer: c, productIds: pIds, interestIds: iIds, kinkIds: kIds });
  }

  if (editor) {
    return (
      <CustomerEditor
        customer={editor.customer}
        productIds={editor.productIds}
        interestIds={editor.interestIds}
        kinkIds={editor.kinkIds}
        products={products}
        interests={interests}
        kinks={kinks}
        personas={personas}
        onClose={async () => {
          setEditor(null);
          try { await refresh(); } catch (e) { setStatus(String(e)); }
        }}
      />
    );
  }

  // Build a matcher for the current search + regex toggle. Pass-through
  // when invalid regex so we don't blank the list mid-typing; surface the
  // error inline beneath the input.
  const q = search.trim();
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
  const filteredSummaries = matcher
    ? summaries.filter((c) =>
        matcher!(c.username) ||
        matcher!(c.realName) ||
        matcher!(c.uid) ||
        matcher!(c.primaryEmail),
      )
    : summaries;

  return (
    <div className="p-8 max-w-5xl space-y-4">
      <div className="flex items-end justify-between gap-3 flex-wrap">
        <div>
          <h2 className="display-font text-2xl font-bold persona-accent">Customers</h2>
          <p className="opacity-70 text-sm">
            {active.code === 'ALL' ? 'All customers across personas.' : `${active.name} customers.`}
          </p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <input
            className="pretty-input w-64"
            placeholder={useRegex ? 'Regex pattern (case-insensitive)…' : 'Search by name, username, UID, email…'}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
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
              {filteredSummaries.length} of {summaries.length}
            </div>
          )}
          {q && (
            <button type="button" className="pretty-button secondary" onClick={() => setSearch('')}>
              Clear
            </button>
          )}
          <button type="button" className="pretty-button" onClick={addCustomer}>✨ Add customer</button>
        </div>
      </div>
      {regexError && (
        <div className="text-xs" style={{ color: '#B45309' }}>Invalid regex: {regexError}</div>
      )}

      <div className="pretty-card">
        {loading && (
          <div className="text-sm opacity-60 italic">Loading customers…</div>
        )}
        {!loading && summaries.length === 0 && (
          <div className="text-sm opacity-70 italic">No customers yet. Click <strong>Add customer</strong> to create one.</div>
        )}
        {!loading && summaries.length > 0 && filteredSummaries.length === 0 && (
          <div className="text-sm opacity-70 italic">No customers match "{q}".</div>
        )}
        <div className="space-y-1.5">
          {filteredSummaries.map((c) => {
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
                    {c.vip && (
                      <span
                        className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold"
                        style={{ background: '#FBBF24', color: '#7C2D12' }}
                        title="VIP"
                      >
                        ⭐ VIP
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
                  {c.productCount > 0 && (c.interestCount > 0 || c.kinkCount > 0) && <span>·</span>}
                  {c.interestCount > 0 && <span>{c.interestCount} interest{c.interestCount === 1 ? '' : 's'}</span>}
                  {c.interestCount > 0 && c.kinkCount > 0 && <span>·</span>}
                  {c.kinkCount > 0 && <span>{c.kinkCount} kink{c.kinkCount === 1 ? '' : 's'}</span>}
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
