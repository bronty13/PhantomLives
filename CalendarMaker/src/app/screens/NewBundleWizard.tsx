import { useState } from 'react';
import type { AppSettings, CalendarBundle, Theme } from '../../model/types';
import { makeBundle } from '../../model/factory';
import { Modal } from '../components/Modal';
import { MonthYearPicker, defaultYearMonth } from '../components/MonthYearPicker';

export function NewBundleWizard({ themes, settings, onCancel, onCreate }: { themes: Theme[]; settings: AppSettings; onCancel: () => void; onCreate: (b: CalendarBundle) => void }) {
  const [title, setTitle] = useState('');
  const def = defaultYearMonth();
  const [year, setYear] = useState(def.year);
  const [month, setMonth] = useState(def.month);
  const [themeId, setThemeId] = useState(settings.defaultThemeId in Object.fromEntries(themes.map((t) => [t.id, t])) ? settings.defaultThemeId : themes[0]?.id);

  const create = () => {
    const b = makeBundle({
      title: title.trim() || 'Untitled Calendar',
      year, month,
      themeId: themeId ?? themes[0].id,
      weekStartsOn: settings.defaultWeekStartsOn,
    });
    onCreate(b);
  };

  return (
    <Modal
      title="New calendar"
      onClose={onCancel}
      footer={<>
        <button onClick={onCancel}>Cancel</button>
        <button className="primary" onClick={create} disabled={!title.trim()}>Create</button>
      </>}
    >
      <div className="col">
        <div>
          <label>Title (this is the saved name)</label>
          <input type="text" autoFocus value={title} placeholder="e.g. Grace Church — June 2026" onChange={(e) => setTitle(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter' && title.trim()) create(); }} />
        </div>
        <div>
          <label>Month &amp; year</label>
          <MonthYearPicker year={year} month={month} onChange={(y, m) => { setYear(y); setMonth(m); }} />
        </div>
        <div>
          <label>Theme</label>
          <select value={themeId} onChange={(e) => setThemeId(e.target.value)}>
            {themes.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
          </select>
        </div>
      </div>
    </Modal>
  );
}
