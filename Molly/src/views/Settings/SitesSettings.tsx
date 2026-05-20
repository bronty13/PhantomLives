import { useEffect, useMemo, useState } from 'react';
import { createSite, deleteSite, listSites, updateSite, type Site } from '../../data/sites';
import { listPersonas, type Persona } from '../../data/personas';
import type { Persona as ActivePersona } from '../../state/personas';
import { ColorPicker } from '../../components/ColorPicker';
import { ConfirmButton } from '../../components/ConfirmButton';

interface Props {
  activePersona: ActivePersona;
}

const EMPTY_DRAFT = (personaCode: string): Site => ({
  id: 0,
  personaCode,
  name: '',
  shortCode: '',
  url: 'https://',
  username: '',
  note: '',
  color: '#FFB6C1',
  loginGroup: null,
  sortOrder: 100,
  archived: false,
});

export function SitesSettings({ activePersona }: Props) {
  const [sites, setSites] = useState<Site[]>([]);
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [draft, setDraft] = useState<Site | null>(null);
  const [editing, setEditing] = useState<Site | null>(null);
  const [status, setStatus] = useState<string>('');

  async function refresh() {
    const [s, p] = await Promise.all([listSites(), listPersonas()]);
    setSites(s);
    setPersonas(p);
  }

  useEffect(() => {
    refresh().catch((e) => setStatus(String(e)));
  }, []);

  const grouped = useMemo(() => {
    const filter = activePersona.code === 'ALL' ? null : activePersona.code;
    const m = new Map<string, Site[]>();
    for (const s of sites) {
      if (filter && s.personaCode !== filter) continue;
      const list = m.get(s.personaCode) ?? [];
      list.push(s);
      m.set(s.personaCode, list);
    }
    return m;
  }, [sites, activePersona]);

  async function save(s: Site) {
    try {
      if (s.id === 0) {
        await createSite(s);
        setStatus(`Added ${s.name}.`);
        setDraft(null);
      } else {
        await updateSite(s);
        setStatus(`Saved ${s.name}.`);
        setEditing(null);
      }
      await refresh();
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    }
  }

  async function remove(s: Site) {
    try {
      await deleteSite(s.id);
      setStatus(`Removed ${s.name}.`);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't delete: ${String(e)}`);
    }
  }

  const newDraftForPersona = activePersona.code === 'ALL' ? (personas[0]?.code ?? 'CoC') : activePersona.code;

  return (
    <div className="space-y-3">
      <div className="pretty-card">
        <div className="flex items-center justify-between mb-3">
          <div>
            <h3 className="display-font text-xl font-semibold persona-accent">Sites</h3>
            <p className="text-sm opacity-70">
              {activePersona.code === 'ALL'
                ? 'All persona site grids. Switch personas to filter.'
                : `Sites for ${activePersona.name}.`}
            </p>
          </div>
          <button type="button" className="pretty-button" onClick={() => setDraft(EMPTY_DRAFT(newDraftForPersona))}>
            ✨ Add site
          </button>
        </div>

        {draft && (
          <SiteEditor
            site={draft}
            personas={personas}
            onChange={setDraft}
            onCancel={() => setDraft(null)}
            onSave={() => save(draft)}
          />
        )}

        {[...grouped.entries()].map(([personaCode, list]) => {
          const persona = personas.find((p) => p.code === personaCode);
          return (
            <div key={personaCode} className="mt-4">
              <div className="text-xs uppercase tracking-wider opacity-60 mb-1">
                {persona?.name ?? personaCode} · {list.length} site{list.length === 1 ? '' : 's'}
              </div>
              <div className="space-y-2">
                {list.map((s) => {
                  const isEditing = editing?.id === s.id;
                  return (
                    <div
                      key={s.id}
                      className="p-3 rounded-xl border"
                      style={{
                        borderColor: `${s.color}88`,
                        background: 'rgb(var(--persona-tint))',
                      }}
                    >
                      <div className="flex items-center justify-between gap-3">
                        <div className="flex items-center gap-3">
                          <span
                            className="w-3 h-3 rounded-full"
                            style={{ background: s.color, border: '1px solid rgba(0,0,0,0.1)' }}
                          />
                          <div>
                            <div className="font-semibold">
                              {s.name}{' '}
                              <span className="opacity-50 text-xs font-mono">[{s.shortCode}]</span>
                              {s.loginGroup && <span className="ml-2 text-[11px] px-1.5 py-0.5 rounded-md bg-black/10">🔗 {s.loginGroup}</span>}
                            </div>
                            <div className="text-xs opacity-70">
                              <a href={s.url} target="_blank" rel="noreferrer" className="underline">{s.url}</a>
                              {s.username && <> · <strong>{s.username}</strong></>}
                              {s.note && <> · {s.note}</>}
                            </div>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <button type="button" className="pretty-button secondary" onClick={() => setEditing(isEditing ? null : { ...s })}>
                            {isEditing ? 'Cancel' : 'Edit'}
                          </button>
                          <ConfirmButton label="Delete" confirmLabel="Confirm?" onConfirm={() => remove(s)} />
                        </div>
                      </div>
                      {isEditing && editing && (
                        <div className="mt-3">
                          <SiteEditor
                            site={editing}
                            personas={personas}
                            onChange={setEditing}
                            onCancel={() => setEditing(null)}
                            onSave={() => save(editing)}
                          />
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          );
        })}

        {grouped.size === 0 && (
          <div className="text-sm opacity-70 italic mt-3">No sites for this persona yet — click <strong>Add site</strong>.</div>
        )}
      </div>
      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}

function SiteEditor({
  site,
  personas,
  onChange,
  onCancel,
  onSave,
}: {
  site: Site;
  personas: Persona[];
  onChange: (s: Site) => void;
  onCancel: () => void;
  onSave: () => void;
}) {
  return (
    <div className="mt-3 grid grid-cols-2 gap-3 p-3 rounded-xl bg-white border border-black/5">
      <label className="flex flex-col gap-1">
        <span className="text-xs uppercase tracking-wider opacity-60">Persona</span>
        <select
          className="pretty-input"
          value={site.personaCode}
          onChange={(e) => onChange({ ...site, personaCode: e.target.value })}
        >
          {personas.map((p) => <option key={p.code} value={p.code}>{p.code} — {p.name}</option>)}
        </select>
      </label>
      <label className="flex flex-col gap-1">
        <span className="text-xs uppercase tracking-wider opacity-60">Sort order</span>
        <input
          type="number"
          className="pretty-input"
          value={site.sortOrder}
          onChange={(e) => onChange({ ...site, sortOrder: Number(e.target.value) || 0 })}
        />
      </label>
      <label className="flex flex-col gap-1">
        <span className="text-xs uppercase tracking-wider opacity-60">Name</span>
        <input className="pretty-input" value={site.name} onChange={(e) => onChange({ ...site, name: e.target.value })} />
      </label>
      <label className="flex flex-col gap-1">
        <span className="text-xs uppercase tracking-wider opacity-60">Short code</span>
        <input className="pretty-input" value={site.shortCode} onChange={(e) => onChange({ ...site, shortCode: e.target.value })} />
      </label>
      <label className="flex flex-col gap-1 col-span-2">
        <span className="text-xs uppercase tracking-wider opacity-60">URL</span>
        <input className="pretty-input" value={site.url} onChange={(e) => onChange({ ...site, url: e.target.value })} />
      </label>
      <label className="flex flex-col gap-1">
        <span className="text-xs uppercase tracking-wider opacity-60">Username</span>
        <input className="pretty-input" value={site.username} onChange={(e) => onChange({ ...site, username: e.target.value })} />
      </label>
      <label className="flex flex-col gap-1">
        <span className="text-xs uppercase tracking-wider opacity-60">Login group (optional)</span>
        <input
          className="pretty-input"
          placeholder="e.g. of-shared"
          value={site.loginGroup ?? ''}
          onChange={(e) => onChange({ ...site, loginGroup: e.target.value || null })}
        />
      </label>
      <label className="flex flex-col gap-1 col-span-2">
        <span className="text-xs uppercase tracking-wider opacity-60">Note</span>
        <input className="pretty-input" value={site.note} onChange={(e) => onChange({ ...site, note: e.target.value })} />
      </label>
      <div className="col-span-2">
        <ColorPicker label="Color" value={site.color} onChange={(v) => onChange({ ...site, color: v })} />
      </div>
      <div className="col-span-2 flex justify-end gap-2">
        <button type="button" className="pretty-button secondary" onClick={onCancel}>Cancel</button>
        <button type="button" className="pretty-button" onClick={onSave}>Save</button>
      </div>
    </div>
  );
}
