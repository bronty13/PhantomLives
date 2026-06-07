import { useState } from 'react';
import type { ItemType, Theme } from '../../model/types';
import { ITEM_TYPES, ITEM_TYPE_LABELS } from '../../model/types';
import { duplicateTheme } from '../../model/factory';
import { deleteTheme, saveTheme } from '../../storage/db';
import { Modal } from '../components/Modal';
import { ColorField, FontPicker } from '../components/Fields';

interface Props {
  themes: Theme[];
  activeThemeId: string;
  onClose: () => void;
  onSelect: (id: string) => void;
  onThemesChanged: () => void;
}

export function ThemeManager({ themes, activeThemeId, onClose, onSelect, onThemesChanged }: Props) {
  const [draft, setDraft] = useState<Theme | null>(null);

  const duplicate = async (t: Theme) => {
    const copy = duplicateTheme(t);
    await saveTheme(copy);
    onThemesChanged();
    setDraft(copy);
  };

  const remove = async (t: Theme) => {
    if (!confirm(`Delete theme "${t.name}"?`)) return;
    await deleteTheme(t.id);
    onThemesChanged();
    if (draft?.id === t.id) setDraft(null);
  };

  const save = async () => {
    if (!draft) return;
    await saveTheme(draft);
    onThemesChanged();
    setDraft(null);
  };

  if (draft) {
    const setItem = (type: ItemType, patch: Partial<{ font: string; color: string }>) =>
      setDraft({ ...draft, itemStyles: { ...draft.itemStyles, [type]: { ...draft.itemStyles[type], ...patch } } });
    const setCal = (patch: Partial<Theme['calendar']>) => setDraft({ ...draft, calendar: { ...draft.calendar, ...patch } });

    return (
      <Modal title={`Edit theme`} wide onClose={() => setDraft(null)} footer={<><button onClick={() => setDraft(null)}>Cancel</button><button className="primary" onClick={save}>Save theme</button></>}>
        <div className="col">
          <div>
            <label>Name</label>
            <input type="text" value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} />
          </div>

          <label style={{ margin: '6px 0 0' }}>Item types (font &amp; color)</label>
          {ITEM_TYPES.map((t) => (
            <div className="row" key={t} style={{ gap: 10 }}>
              <span style={{ width: 110 }}>{ITEM_TYPE_LABELS[t]}</span>
              <FontPicker value={draft.itemStyles[t].font} onChange={(f) => setItem(t, { font: f })} />
              <ColorField value={draft.itemStyles[t].color} onChange={(c) => setItem(t, { color: c })} />
            </div>
          ))}

          <label style={{ margin: '10px 0 0' }}>Calendar chrome</label>
          <CalRow label="Title" font={draft.calendar.titleFont} color={draft.calendar.titleColor} onFont={(f) => setCal({ titleFont: f })} onColor={(c) => setCal({ titleColor: c })} />
          <CalRow label="Weekday header" font={draft.calendar.headerFont} color={draft.calendar.headerColor} onFont={(f) => setCal({ headerFont: f })} onColor={(c) => setCal({ headerColor: c })} />
          <CalRow label="Holiday" font={draft.calendar.holidayFont} color={draft.calendar.holidayColor} onFont={(f) => setCal({ holidayFont: f })} onColor={(c) => setCal({ holidayColor: c })} />
          <CalRow label="Saying / verse" font={draft.calendar.fillerFont} color={draft.calendar.fillerColor} onFont={(f) => setCal({ fillerFont: f })} onColor={(c) => setCal({ fillerColor: c })} />

          <label style={{ margin: '10px 0 0' }}>Colors</label>
          <ColorRow label="Header background" value={draft.calendar.headerBackground} onChange={(c) => setCal({ headerBackground: c })} />
          <ColorRow label="Page background" value={draft.calendar.backgroundColor} onChange={(c) => setCal({ backgroundColor: c })} />
          <ColorRow label="Grid lines" value={draft.calendar.gridLineColor} onChange={(c) => setCal({ gridLineColor: c })} />
          <ColorRow label="Day numbers" value={draft.calendar.dayNumberColor} onChange={(c) => setCal({ dayNumberColor: c })} />
          <ColorRow label="Detail-only mark" value={draft.overflowColor} onChange={(c) => setDraft({ ...draft, overflowColor: c })} />
        </div>
      </Modal>
    );
  }

  return (
    <Modal title="Themes" onClose={onClose}>
      <div className="col">
        {themes.map((t) => (
          <div className="item-row" key={t.id}>
            <div className="grow">
              <div style={{ fontWeight: 600 }}>{t.name}{t.id === activeThemeId ? ' · in use' : ''}</div>
              <div className="hint">{t.builtin ? 'Built-in' : 'Custom'}</div>
            </div>
            {t.id !== activeThemeId && <button onClick={() => onSelect(t.id)}>Use</button>}
            <button onClick={() => duplicate(t)}>Duplicate</button>
            {!t.builtin && <button onClick={() => setDraft(t)}>Edit</button>}
            {!t.builtin && <button className="ghost danger" onClick={() => remove(t)}>Delete</button>}
          </div>
        ))}
      </div>
    </Modal>
  );
}

function CalRow({ label, font, color, onFont, onColor }: { label: string; font: string; color: string; onFont: (f: string) => void; onColor: (c: string) => void }) {
  return (
    <div className="row" style={{ gap: 10 }}>
      <span style={{ width: 110 }}>{label}</span>
      <FontPicker value={font} onChange={onFont} />
      <ColorField value={color} onChange={onColor} />
    </div>
  );
}

function ColorRow({ label, value, onChange }: { label: string; value: string; onChange: (c: string) => void }) {
  return (
    <div className="row" style={{ gap: 10 }}>
      <span style={{ width: 140 }}>{label}</span>
      <ColorField value={value} onChange={onChange} />
    </div>
  );
}
