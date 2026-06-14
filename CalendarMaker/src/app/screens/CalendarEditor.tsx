import { useState } from 'react';
import type { AppSettings, CalendarBundle, Day, FillerEntry, Theme } from '../../model/types';
import { CalendarPreview } from '../CalendarPreview';
import { DayEditorPanel } from './DayEditorPanel';
import { HolidaysPanel } from './HolidaysPanel';
import { FillerPicker } from './FillerPicker';
import { ThemeManager } from './ThemeManager';
import { ExportDialog } from './ExportDialog';

interface Props {
  bundle: CalendarBundle;
  theme: Theme;
  themes: Theme[];
  settings: AppSettings;
  sayings: FillerEntry[];
  onChange: (b: CalendarBundle) => void;
  onThemesChanged: () => void;
}

type Panel = 'none' | 'day' | 'holidays' | 'fillers' | 'theme' | 'export';

export function CalendarEditor({ bundle, theme, themes, settings, sayings, onChange, onThemesChanged }: Props) {
  const [panel, setPanel] = useState<Panel>('none');
  const [selectedDate, setSelectedDate] = useState<string | null>(null);

  const setDay = (date: string, day: Day) => {
    const days = { ...bundle.days, [date]: day };
    // Drop empty day records to keep storage tidy.
    if (day.items.length === 0 && day.holidayIds.length === 0) delete days[date];
    onChange({ ...bundle, days });
  };

  const openDay = (date: string) => { setSelectedDate(date); setPanel('day'); };

  return (
    <>
      <div className="row" style={{ marginBottom: 14, flexWrap: 'wrap' }}>
        <input
          type="text"
          value={bundle.title}
          onChange={(e) => onChange({ ...bundle, title: e.target.value })}
          style={{ maxWidth: 320, fontWeight: 600 }}
        />
        <div style={{ flex: 1 }} />
        <select value={bundle.themeId} onChange={(e) => onChange({ ...bundle, themeId: e.target.value })} style={{ width: 170 }}>
          {themes.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
        </select>
        <button onClick={() => setPanel('holidays')}>Holidays</button>
        <button onClick={() => setPanel('fillers')}>Sayings &amp; Verses</button>
        <div className="row" style={{ gap: 4, background: 'var(--border)', padding: 2, borderRadius: 4 }}>
          <button
            className={bundle.verseMode !== 'force' ? 'secondary' : 'ghost'}
            onClick={() => onChange({ ...bundle, verseMode: 'separate' })}
            style={{ flex: 1 }}
          >
            Separate
          </button>
          <button
            className={bundle.verseMode === 'force' ? 'secondary' : 'ghost'}
            onClick={() => onChange({ ...bundle, verseMode: 'force' })}
            style={{ flex: 1 }}
          >
            Force
          </button>
        </div>
        <button onClick={() => setPanel('theme')}>Themes</button>
        <button className="primary" onClick={() => setPanel('export')}>Export PDF</button>
      </div>

      <p className="hint" style={{ marginTop: 0 }}>Click any day to add events. Items that don’t fit the month grid are kept and shown in the Detail view.</p>

      <CalendarPreview
        bundle={bundle}
        theme={theme}
        cap={settings.maxItemsPerMonthCell}
        onSelectDay={openDay}
        selectedDate={selectedDate}
      />

      {panel === 'day' && selectedDate && (
        <DayEditorPanel
          date={selectedDate}
          day={bundle.days[selectedDate] ?? { date: selectedDate, items: [], holidayIds: [] }}
          theme={theme}
          cap={settings.maxItemsPerMonthCell}
          bundle={bundle}
          customSayings={sayings}
          onChange={(d) => setDay(selectedDate, d)}
          onClose={() => setPanel('none')}
        />
      )}
      {panel === 'holidays' && (
        <HolidaysPanel bundle={bundle} onChange={onChange} onClose={() => setPanel('none')} />
      )}
      {panel === 'fillers' && (
        <FillerPicker bundle={bundle} sayings={sayings} onChange={onChange} onClose={() => setPanel('none')} />
      )}
      {panel === 'theme' && (
        <ThemeManager
          themes={themes}
          activeThemeId={bundle.themeId}
          onClose={() => setPanel('none')}
          onSelect={(id) => onChange({ ...bundle, themeId: id })}
          onThemesChanged={onThemesChanged}
        />
      )}
      {panel === 'export' && (
        <ExportDialog bundle={bundle} theme={theme} settings={settings} onClose={() => setPanel('none')} />
      )}
    </>
  );
}
