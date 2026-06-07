import { useState } from 'react';
import type { AppSettings, ExportMode, Theme } from '../../model/types';
import { Modal } from '../components/Modal';

export function SettingsModal({ settings, themes, onClose, onSave }: { settings: AppSettings; themes: Theme[]; onClose: () => void; onSave: (s: AppSettings) => void }) {
  const [s, setS] = useState<AppSettings>(settings);
  const set = (patch: Partial<AppSettings>) => setS({ ...s, ...patch });

  return (
    <Modal title="Settings" onClose={onClose} footer={<><button onClick={onClose}>Cancel</button><button className="primary" onClick={() => onSave(s)}>Save</button></>}>
      <div className="col">
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
      </div>
    </Modal>
  );
}
