import { useState } from 'react';
import type { AppSettings, ExportMode, FillerEntry, Theme } from '../../model/types';
import { SAYINGS } from '../../data/sayings';
import { addCustomSaying, deleteCustomSaying, updateCustomSaying } from '../../storage/db';
import { newId } from '../../model/factory';
import { Modal } from '../components/Modal';

interface Props {
  settings: AppSettings;
  themes: Theme[];
  customSayings: FillerEntry[];
  onClose: () => void;
  onSave: (s: AppSettings) => void;
  onSayingsChanged: () => void;
}

export function SettingsModal({ settings, themes, customSayings, onClose, onSave, onSayingsChanged }: Props) {
  const [s, setS] = useState<AppSettings>(settings);
  const set = (patch: Partial<AppSettings>) => setS({ ...s, ...patch });

  const [editingId, setEditingId] = useState<string | null>(null);
  const [editText, setEditText] = useState('');
  const [editRef, setEditRef] = useState('');
  const [showBuiltin, setShowBuiltin] = useState(false);

  const startEdit = (saying: FillerEntry) => {
    setEditingId(saying.id);
    setEditText(saying.text);
    setEditRef(saying.reference || '');
  };

  const saveEdit = async () => {
    const text = editText.trim();
    if (!text || !editingId) return;
    const saying = customSayings.find((s) => s.id === editingId);
    if (!saying) return;
    await updateCustomSaying({ ...saying, text, reference: editRef.trim() || undefined });
    setEditingId(null);
    onSayingsChanged();
  };

  const cancelEdit = () => {
    setEditingId(null);
    setEditText('');
    setEditRef('');
  };

  const removeSaying = async (id: string) => {
    await deleteCustomSaying(id);
    onSayingsChanged();
  };

  return (
    <Modal title="Settings" onClose={onClose} footer={<><button onClick={onClose}>Cancel</button><button className="primary" onClick={() => onSave(s)}>Save</button></>}>
      <div className="col">
        <div>
          <label>Your name (used in the home greeting)</label>
          <input type="text" value={s.userName} placeholder="Jan" onChange={(e) => set({ userName: e.target.value })} />
        </div>
        <div>
          <label>Default theme for new calendars</label>
          <select value={s.defaultThemeId} onChange={(e) => set({ defaultThemeId: e.target.value })}>
            {themes.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
          </select>
        </div>
        <div>
          <label>Week starts on</label>
          <select value={s.defaultWeekStartsOn} onChange={(e) => set({ defaultWeekStartsOn: parseInt(e.target.value, 10) as 0 | 1 })}>
            <option value={0}>Sunday</option>
            <option value={1}>Monday</option>
          </select>
        </div>
        <div>
          <label>Default export view</label>
          <select value={s.defaultExportMode} onChange={(e) => set({ defaultExportMode: e.target.value as ExportMode })}>
            <option value="month">Month view</option>
            <option value="detail">Detail view</option>
            <option value="both">Both</option>
          </select>
        </div>
        <div>
          <label>Max items shown per day on the month grid (safety cap): {s.maxItemsPerMonthCell}</label>
          <input type="range" min={2} max={8} value={s.maxItemsPerMonthCell} onChange={(e) => set({ maxItemsPerMonthCell: parseInt(e.target.value, 10) })} style={{ width: '100%' }} />
        </div>
        <label className="row" style={{ gap: 8, margin: 0, color: 'var(--ink)' }}>
          <input type="checkbox" style={{ width: 'auto' }} checked={s.showVerseOnHome} onChange={(e) => set({ showVerseOnHome: e.target.checked })} />
          Show a random Bible verse on the home screen
        </label>
        <label className="row" style={{ gap: 8, margin: 0, color: 'var(--ink)' }}>
          <input type="checkbox" style={{ width: 'auto' }} checked={s.showSayingOnHome} onChange={(e) => set({ showSayingOnHome: e.target.checked })} />
          Show a random saying on the home screen
        </label>

        <hr style={{ width: '100%', border: 'none', borderTop: '1px solid var(--line)', margin: '6px 0' }} />

        <div>
          <label style={{ margin: 0 }}>Sayings ({SAYINGS.length} built-in + {customSayings.length} yours)</label>
          <p className="hint" style={{ margin: '4px 0 8px' }}>Add, edit, or delete your own sayings. (Saved immediately.)</p>

          <button className="secondary" onClick={() => setShowBuiltin(!showBuiltin)} style={{ marginBottom: 8, width: '100%' }}>
            {showBuiltin ? '▼' : '▶'} Built-in Sayings ({SAYINGS.length})
          </button>
          {showBuiltin && (
            <div className="col" style={{ gap: 6, marginBottom: 12, fontSize: 13, color: 'var(--text-muted)' }}>
              {SAYINGS.map((bs) => (
                <div key={bs.id}>
                  <div>{bs.text}</div>
                  {bs.reference && <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>— {bs.reference}</div>}
                </div>
              ))}
            </div>
          )}

          <label style={{ margin: 0 }}>Your Sayings ({customSayings.length})</label>
          <div className="col" style={{ gap: 8, marginTop: 8 }}>
            {customSayings.map((cs) => (
              <div key={cs.id}>
                {editingId === cs.id ? (
                  <div className="col" style={{ gap: 6, padding: 8, background: 'var(--bg-secondary)', borderRadius: 4 }}>
                    <textarea rows={2} value={editText} placeholder="Saying text…" onChange={(e) => setEditText(e.target.value)} />
                    <input type="text" value={editRef} placeholder="Attribution (optional)" onChange={(e) => setEditRef(e.target.value)} />
                    <div className="row" style={{ gap: 6 }}>
                      <button className="primary" onClick={saveEdit} disabled={!editText.trim()}>Save</button>
                      <button className="secondary" onClick={cancelEdit}>Cancel</button>
                    </div>
                  </div>
                ) : (
                  <div className="item-row" style={{ marginBottom: 0 }}>
                    <div className="grow col" style={{ gap: 2 }}>
                      <div>{cs.text}</div>
                      {cs.reference && <div className="hint">— {cs.reference}</div>}
                    </div>
                    <div className="row" style={{ gap: 4 }}>
                      <button className="secondary" onClick={() => startEdit(cs)} title="Edit">✎</button>
                      <button className="ghost danger" onClick={() => removeSaying(cs.id)} title="Delete">✕</button>
                    </div>
                  </div>
                )}
              </div>
            ))}

            <button className="secondary" onClick={() => {
              setEditingId('new');
              setEditText('');
              setEditRef('');
            }} style={{ width: '100%' }}>+ Add new saying</button>

            {editingId === 'new' && (
              <div className="col" style={{ gap: 6, padding: 8, background: 'var(--bg-secondary)', borderRadius: 4 }}>
                <textarea rows={2} value={editText} placeholder="Your saying…" onChange={(e) => setEditText(e.target.value)} />
                <input type="text" value={editRef} placeholder="Attribution (optional)" onChange={(e) => setEditRef(e.target.value)} />
                <div className="row" style={{ gap: 6 }}>
                  <button className="primary" onClick={async () => {
                    const text = editText.trim();
                    if (!text) return;
                    await addCustomSaying({ id: newId('saying'), kind: 'saying', text, reference: editRef.trim() || undefined });
                    setEditingId(null);
                    setEditText('');
                    setEditRef('');
                    onSayingsChanged();
                  }} disabled={!editText.trim()}>Add</button>
                  <button className="secondary" onClick={() => {
                    setEditingId(null);
                    setEditText('');
                    setEditRef('');
                  }}>Cancel</button>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </Modal>
  );
}
