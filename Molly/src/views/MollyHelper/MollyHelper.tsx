import { useEffect, useMemo, useState } from 'react';
import { openUrl } from '@tauri-apps/plugin-opener';
import type { Persona } from '../../state/personas';
import { listSites, type Site } from '../../data/sites';
import { listPersonas, type Persona as PersonaRow } from '../../data/personas';

interface Props {
  active: Persona;
}

export function MollyHelper({ active }: Props) {
  const [sites, setSites] = useState<Site[]>([]);
  const [personas, setPersonas] = useState<PersonaRow[]>([]);
  const [status, setStatus] = useState<string>('');

  useEffect(() => {
    Promise.all([listSites(), listPersonas()])
      .then(([s, p]) => {
        setSites(s);
        setPersonas(p);
      })
      .catch((e) => setStatus(String(e)));
  }, []);

  const grouped = useMemo(() => {
    const filter = active.code === 'ALL' ? null : active.code;
    const m = new Map<string, Site[]>();
    for (const s of sites) {
      if (filter && s.personaCode !== filter) continue;
      const list = m.get(s.personaCode) ?? [];
      list.push(s);
      m.set(s.personaCode, list);
    }
    return m;
  }, [sites, active]);

  async function launch(s: Site) {
    try {
      await openUrl(s.url);
      setStatus(`Opening ${s.name}…`);
    } catch (e) {
      setStatus(`Couldn't open ${s.url}: ${String(e)}`);
    }
  }

  async function copyUsername(s: Site) {
    try {
      await navigator.clipboard.writeText(s.username);
      setStatus(`Copied "${s.username}" to clipboard.`);
    } catch (e) {
      setStatus(`Couldn't copy: ${String(e)}`);
    }
  }

  return (
    <div className="p-8 max-w-5xl space-y-4">
      <div>
        <h2 className="display-font text-2xl font-bold persona-accent">Molly Helper</h2>
        <p className="opacity-70 text-sm">
          One-click site launcher with your username right there so you don't have to remember.
          {active.code !== 'ALL' && <> Filtered to <strong>{active.name}</strong>.</>}
        </p>
      </div>

      {grouped.size === 0 && (
        <div className="pretty-card text-sm opacity-70 italic">
          No sites for this persona yet — add some in Settings → Sites.
        </div>
      )}

      {[...grouped.entries()].map(([code, list]) => {
        const persona = personas.find((p) => p.code === code);
        return (
          <div key={code} className="space-y-2">
            <div className="flex items-center gap-2">
              {persona && (
                <span
                  className="px-2 py-0.5 rounded-md text-xs font-semibold"
                  style={{ background: persona.primaryColor, color: persona.textColor, border: `1px solid ${persona.accentColor}` }}
                >
                  {persona.code}
                </span>
              )}
              <div className="display-font font-semibold persona-accent">{persona?.name ?? code}</div>
              <div className="text-xs opacity-60">{list.length} site{list.length === 1 ? '' : 's'}</div>
            </div>
            <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
              {list.map((s) => (
                <div
                  key={s.id}
                  className="rounded-2xl p-4 text-left flex flex-col gap-2"
                  style={{
                    background: 'white',
                    borderTop: `6px solid ${s.color}`,
                    boxShadow: `0 4px 14px -6px ${s.color}88`,
                  }}
                >
                  <div className="flex items-baseline justify-between gap-2">
                    <div className="font-semibold persona-text" style={{ color: s.color }}>{s.name}</div>
                    <div className="text-[10px] font-mono opacity-60">{s.shortCode}</div>
                  </div>
                  {s.username && (
                    <div className="text-xs">
                      <span className="opacity-60">user:</span> <span className="font-mono">{s.username}</span>
                    </div>
                  )}
                  {s.note && <div className="text-[11px] opacity-70 italic">{s.note}</div>}
                  {s.loginGroup && (
                    <div className="text-[11px] opacity-60">🔗 shared login: <span className="font-mono">{s.loginGroup}</span></div>
                  )}
                  <div className="flex gap-2 mt-1">
                    <button type="button" className="pretty-button" style={{ background: s.color, boxShadow: `0 4px 12px -4px ${s.color}aa` }} onClick={() => launch(s)}>
                      Open
                    </button>
                    {s.username && (
                      <button type="button" className="pretty-button secondary" onClick={() => copyUsername(s)} title="Copy username to clipboard">
                        Copy user
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        );
      })}

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}
