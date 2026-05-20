import { useEffect, useState } from 'react';
import { listPersonas, updatePersona, type Persona } from '../../data/personas';
import { ColorPicker } from '../../components/ColorPicker';

interface Props {
  onChanged: () => void | Promise<void>;
}

export function PersonasSettings({ onChanged }: Props) {
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [editing, setEditing] = useState<Persona | null>(null);
  const [status, setStatus] = useState<string>('');

  async function refresh() {
    setPersonas(await listPersonas());
  }

  useEffect(() => {
    refresh().catch((e) => setStatus(String(e)));
  }, []);

  async function save() {
    if (!editing) return;
    try {
      await updatePersona(editing);
      setStatus(`Saved ${editing.name}.`);
      setEditing(null);
      await refresh();
      await onChanged();
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    }
  }

  return (
    <div className="space-y-3">
      <div className="pretty-card">
        <h3 className="display-font text-xl font-semibold persona-accent mb-2">Personas</h3>
        <p className="text-sm opacity-70 mb-4">
          Personas drive the app's color theme and act as a filter across every view. The three preloaded personas
          can be renamed and recolored; new personas can be added in a later phase.
        </p>

        <div className="space-y-2">
          {personas.map((p) => {
            const isEditing = editing?.code === p.code;
            return (
              <div key={p.code} className="p-3 rounded-xl border border-black/5" style={{ background: 'rgb(var(--persona-tint))' }}>
                <div className="flex items-center justify-between gap-3">
                  <div className="flex items-center gap-3">
                    <span
                      style={{
                        background: p.primaryColor,
                        color: p.textColor,
                        border: `1px solid ${p.accentColor}`,
                      }}
                      className="px-2.5 py-1 rounded-full text-sm font-semibold"
                    >
                      {p.code}
                    </span>
                    <div>
                      <div className="font-semibold">{p.name}</div>
                      <div className="text-xs opacity-70">{p.description}</div>
                    </div>
                  </div>
                  <button
                    type="button"
                    className="pretty-button secondary"
                    onClick={() => setEditing(isEditing ? null : { ...p })}
                  >
                    {isEditing ? 'Cancel' : 'Edit'}
                  </button>
                </div>

                {isEditing && editing && (
                  <div className="mt-3 grid grid-cols-2 gap-3">
                    <label className="flex flex-col gap-1">
                      <span className="text-xs uppercase tracking-wider opacity-60">Name</span>
                      <input className="pretty-input" value={editing.name} onChange={(e) => setEditing({ ...editing, name: e.target.value })} />
                    </label>
                    <label className="flex flex-col gap-1 col-span-2">
                      <span className="text-xs uppercase tracking-wider opacity-60">Description</span>
                      <input className="pretty-input" value={editing.description} onChange={(e) => setEditing({ ...editing, description: e.target.value })} />
                    </label>
                    <ColorPicker label="Primary" value={editing.primaryColor} onChange={(v) => setEditing({ ...editing, primaryColor: v })} />
                    <ColorPicker label="Secondary" value={editing.secondaryColor} onChange={(v) => setEditing({ ...editing, secondaryColor: v })} />
                    <ColorPicker label="Tint" value={editing.tintColor} onChange={(v) => setEditing({ ...editing, tintColor: v })} />
                    <ColorPicker label="Accent" value={editing.accentColor} onChange={(v) => setEditing({ ...editing, accentColor: v })} />
                    <ColorPicker label="Text" value={editing.textColor} onChange={(v) => setEditing({ ...editing, textColor: v })} />
                    <div className="col-span-2 flex justify-end gap-2">
                      <button type="button" className="pretty-button secondary" onClick={() => setEditing(null)}>Cancel</button>
                      <button type="button" className="pretty-button" onClick={save}>Save</button>
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>
      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}
