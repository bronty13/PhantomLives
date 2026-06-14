import { useState } from 'react';
import type { CalendarBundle, Day, Item, ItemType, Theme, FillerEntry } from '../../model/types';
import { ITEM_TYPES, ITEM_TYPE_LABELS, MONTH_NAMES, WEEKDAY_NAMES } from '../../model/types';
import { classifyDay, isMonthEligible, type FitContext } from '../../calendar/fit';
import { monthGeometry } from '../../pdf/geometry';
import { computeWeeks } from '../../calendar/grid';
import { makeItem } from '../../model/factory';
import { holidayNamesFor } from '../../pdf/holidayNames';
import { parseIso, weekdayOf } from '../../calendar/dateUtil';
import { Drawer } from '../components/Modal';
import { BiblePicker } from './BiblePicker';
import { SayingPicker } from './SayingPicker';

interface Props {
  date: string;
  day: Day;
  theme: Theme;
  cap: number;
  bundle: CalendarBundle;
  customSayings: FillerEntry[];
  onChange: (day: Day) => void;
  onClose: () => void;
}

export function DayEditorPanel({ date, day, theme, cap, bundle, customSayings, onChange, onClose }: Props) {
  const [newType, setNewType] = useState<ItemType>('reminder');
  const [newText, setNewText] = useState('');
  const [showBiblePicker, setShowBiblePicker] = useState(false);
  const [showSayingPicker, setShowSayingPicker] = useState(false);
  // When set, the open picker is editing this existing item rather than adding a new one.
  const [editingId, setEditingId] = useState<string | null>(null);

  const grid = computeWeeks(bundle.year, bundle.month, bundle.weekStartsOn);
  const hasFooter = bundle.fillers.some((f) => f.slot === 'footer');
  const ctx: FitContext = { geo: monthGeometry(grid.weeks, hasFooter), theme, cap };
  const holidayLines = holidayNamesFor(day).length;

  const verseMode = bundle.verseMode ?? 'force';
  const cls = classifyDay(day, ctx, holidayLines, verseMode);
  const monthIds = new Set(cls.monthItems.map((i) => i.id));

  const { day: dnum } = parseIso(date);
  const wd = WEEKDAY_NAMES[weekdayOf(bundle.year, bundle.month, dnum)];

  const updateItem = (id: string, patch: Partial<Item>) =>
    onChange({ ...day, items: day.items.map((i) => (i.id === id ? { ...i, ...patch } : i)) });

  const deleteItem = (id: string) => onChange({ ...day, items: day.items.filter((i) => i.id !== id) });

  const addItem = () => {
    const nextOrder = day.items.reduce((m, i) => Math.max(m, i.order), -1) + 1;
    const item = makeItem(newType, nextOrder, newText.trim());
    onChange({ ...day, items: [...day.items, item] });
    setNewText('');
  };

  /**
   * Add (or, when editing, update) a verse/saying item the instant it's picked, so
   * it appears in the list immediately — no separate "+ Add item" step.
   */
  const commitStructured = (type: 'bibleVerse' | 'saying', text: string, reference: string) => {
    if (editingId) {
      onChange({ ...day, items: day.items.map((i) => (i.id === editingId ? { ...i, type, text, reference: reference || undefined } : i)) });
    } else {
      const nextOrder = day.items.reduce((m, i) => Math.max(m, i.order), -1) + 1;
      const item = makeItem(type, nextOrder, text, reference || undefined);
      onChange({ ...day, items: [...day.items, item] });
    }
    setEditingId(null);
    setShowBiblePicker(false);
    setShowSayingPicker(false);
  };

  const sorted = [...day.items].sort((a, b) => a.order - b.order);

  return (
    <Drawer title={`${wd}, ${MONTH_NAMES[bundle.month - 1]} ${dnum}`} onClose={onClose}>
      {holidayNamesFor(day).map((n, i) => (
        <div key={i} className="hint" style={{ marginBottom: 6 }}>🎉 Holiday: {n}</div>
      ))}

      {cls.detailOnly.length > 0 && (
        <div className="alert" style={{ marginBottom: 12 }}>
          <b>{cls.detailOnly.length}</b> item(s) won’t fit on the month grid and will appear in the <b>Detail view</b> only
          (marked <NoSymbol color="#8a2436" />). Use <b>Show on month</b> to choose which items take the limited grid slots.
        </div>
      )}

      {sorted.length === 0 && <div className="hint">No items yet. Add one below.</div>}

      {sorted.map((item) => {
        const isStructured = item.type === 'bibleVerse' || item.type === 'saying';
        const eligible = isMonthEligible(item, ctx);
        const onMonth = monthIds.has(item.id);
        // Verses/sayings are placed intentionally (forced into cells, or on the
        // Scripture page in Separate mode), so they're never the overflow ⊘ case.
        const detailOnly = !isStructured && !onMonth;
        const st = theme.itemStyles[item.type];
        return (
          <div key={item.id} className={`item-row${detailOnly ? ' detail-only' : ''}`}>
            <span className="type-pill" style={{ background: st.color }}>{ITEM_TYPE_LABELS[item.type]}</span>
            <div className="grow col" style={{ gap: 6 }}>
              {isStructured ? (
                <div style={{ display: 'flex', gap: 4, alignItems: 'center' }}>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 13, fontWeight: 500 }}>{item.text.substring(0, 50)}{item.text.length > 50 ? '…' : ''}</div>
                    {item.reference && <div style={{ fontSize: 11, color: 'var(--muted)' }}>— {item.reference}</div>}
                  </div>
                  <button className="secondary" onClick={() => {
                    setEditingId(item.id);
                    if (item.type === 'bibleVerse') { setShowBiblePicker(true); setShowSayingPicker(false); }
                    else if (item.type === 'saying') { setShowSayingPicker(true); setShowBiblePicker(false); }
                  }} style={{ whiteSpace: 'nowrap' }}>✎ Edit</button>
                </div>
              ) : (
                <input type="text" value={item.text} placeholder="Event text…" onChange={(e) => updateItem(item.id, { text: e.target.value })} />
              )}
              <div className="row" style={{ gap: 8, fontSize: 12 }}>
                <select value={item.type} onChange={(e) => updateItem(item.id, { type: e.target.value as ItemType })} style={{ width: 'auto', flex: 1 }}>
                  {ITEM_TYPES.map((t) => <option key={t} value={t}>{ITEM_TYPE_LABELS[t]}</option>)}
                </select>
                {isStructured ? (
                  <span className="row" style={{ gap: 4, color: 'var(--muted)', whiteSpace: 'nowrap' }}>
                    ✓ {verseMode === 'force' ? 'shown in day cells' : 'on Scripture page'}
                  </span>
                ) : eligible ? (
                  <label className="row" style={{ gap: 4, margin: 0, color: 'var(--ink)', whiteSpace: 'nowrap' }}>
                    <input type="checkbox" style={{ width: 'auto' }} checked={item.pinned} onChange={(e) => updateItem(item.id, { pinned: e.target.checked })} />
                    Pin to month
                  </label>
                ) : (
                  <span className="row" style={{ gap: 4, color: 'var(--muted)', whiteSpace: 'nowrap' }}>
                    <NoSymbol color="var(--muted)" /> detail only (too long)
                  </span>
                )}
              </div>
              {detailOnly && eligible && (
                <span className="row" style={{ gap: 4, fontSize: 12, color: theme.overflowColor }}>
                  <NoSymbol color={theme.overflowColor} /> shown in Detail view only
                </span>
              )}
            </div>
            <button className="ghost danger" onClick={() => deleteItem(item.id)} title="Delete">✕</button>
          </div>
        );
      })}

      {showBiblePicker && (
        <div style={{ marginTop: 16, padding: 12, background: 'var(--bg-secondary)', borderRadius: 4 }}>
          <div className="row" style={{ justifyContent: 'space-between', marginBottom: 8 }}>
            <label style={{ margin: 0 }}>{editingId ? 'Change the Bible verse' : 'Select a Bible verse'}</label>
            <button className="ghost" onClick={() => { setShowBiblePicker(false); setEditingId(null); }}>Cancel</button>
          </div>
          <BiblePicker onSelect={(text, reference) => commitStructured('bibleVerse', text, reference)} />
        </div>
      )}

      {showSayingPicker && (
        <div style={{ marginTop: 16, padding: 12, background: 'var(--bg-secondary)', borderRadius: 4 }}>
          <div className="row" style={{ justifyContent: 'space-between', marginBottom: 8 }}>
            <label style={{ margin: 0 }}>{editingId ? 'Change the saying' : 'Select a saying'}</label>
            <button className="ghost" onClick={() => { setShowSayingPicker(false); setEditingId(null); }}>Cancel</button>
          </div>
          <SayingPicker sayings={customSayings} onSelect={(text, reference) => commitStructured('saying', text, reference)} />
        </div>
      )}

      <div className="col" style={{ marginTop: 16, gap: 8 }}>
        <label style={{ margin: 0 }}>Add an item</label>
        <div className="row" style={{ gap: 8 }}>
          <select value={newType} onChange={(e) => {
            const t = e.target.value as ItemType;
            setNewType(t);
            setNewText('');
            // Switching to a structured type opens its picker for a fresh add.
            setEditingId(null);
            setShowBiblePicker(t === 'bibleVerse');
            setShowSayingPicker(t === 'saying');
          }} style={{ width: 140 }}>
            {ITEM_TYPES.map((t) => <option key={t} value={t}>{ITEM_TYPE_LABELS[t]}</option>)}
          </select>
          {newType !== 'bibleVerse' && newType !== 'saying' && (
            <input type="text" value={newText} placeholder="Event text…" onChange={(e) => setNewText(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') addItem(); }} />
          )}
        </div>
        {newType !== 'bibleVerse' && newType !== 'saying' ? (
          <button className="primary" onClick={addItem} disabled={!newText.trim()}>+ Add item</button>
        ) : (
          <p className="hint" style={{ margin: 0 }}>Pick a {newType === 'bibleVerse' ? 'verse' : 'saying'} above — it’s added to the day right away.</p>
        )}
      </div>
    </Drawer>
  );
}

function NoSymbol({ color }: { color: string }) {
  return (
    <svg className="no-symbol" viewBox="0 0 16 16" style={{ display: 'inline-block', verticalAlign: 'middle' }}>
      <circle cx="8" cy="8" r="6" fill="none" stroke={color} strokeWidth="1.5" />
      <line x1="3.8" y1="12.2" x2="12.2" y2="3.8" stroke={color} strokeWidth="1.5" />
    </svg>
  );
}
