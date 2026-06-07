import { useState } from 'react';
import type { AppSettings, ExportMode, FillerEntry, Theme } from '../../model/types';
import { SAYINGS } from '../../data/sayings';
import { addCustomSaying, deleteCustomSaying } from '../../storage/db';
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

  const [newSaying, setNewSaying] = useState('');
  const [newAttrib, setNewAttrib] = useState('');

  const addSaying = async () => {
    const text = newSaying.trim();
    if (!text) return;
    await addCustomSaying({ id: newId('saying'), kind: 'saying', text, reference: newAttrib.trim() || undefined });
    setNewSaying('');
    setNewAttrib('');
    onSayingsChanged();
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
          <p className="hint" style={{ margin: '4px 0 8px' }}>Add your own sayings to the random pool. (Saved immediately.)</p>
          <div className="col" style={{ gap: 8 }}>
            <textarea rows={2} value={newSaying} placeholder="Your saying…" onChange={(e) => setNewSaying(e.target.value)} />
            <div className="row" style={{ gap: 8 }}>
              <input type="text" value={newAttrib} placeholder="Attribution (optional)" onChange={(e) => setNewAttrib(e.target.value)} />
              <button className="primary" onClick={addSaying} disabled={!newSaying.trim()} style={{ whiteSpace: 'nowrap' }}>+ Add</button>
            </div>
          </div>
          {customSayings.length > 0 && (
            <div className="col" style={{ gap: 6, marginTop: 10 }}>
              {customSayings.map((cs) => (
                <div className="item-row" key={cs.id} style={{ marginBottom: 0 }}>
                  <div className="grow">
                    <div>{cs.text}</div>
                    {cs.reference && <div className="hint">— {cs.reference}</div>}
                  </div>
                  <button className="ghost danger" onClick={() => removeSaying(cs.id)} title="Delete">✕</button>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </Modal>
  );
}
