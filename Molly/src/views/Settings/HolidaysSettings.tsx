import { useMemo, useState } from 'react';
import {
  createHoliday,
  deleteHoliday,
  listHolidays,
  resetHolidaysToUSDefaults,
  setHolidayEnabled,
  updateHoliday,
  type Holiday,
  type HolidayInput,
  type HolidayKind,
} from '../../data/holidays';
import { ColorPicker } from '../../components/ColorPicker';
import { useAsyncRefresh } from '../../lib/useAsyncRefresh';
import {
  daysInMonth,
  holidayPillStyle,
  resolveHolidayForMonth,
} from '../../lib/holidayResolver';

const MONTH_NAMES = [
  '', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const WEEKDAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const NTH_OPTIONS: { value: number; label: string }[] = [
  { value: 1,  label: '1st' },
  { value: 2,  label: '2nd' },
  { value: 3,  label: '3rd' },
  { value: 4,  label: '4th' },
  { value: -1, label: 'Last' },
];

const EMPTY_INPUT: HolidayInput = {
  name: '',
  kind: 'fixed',
  month: 1,
  day: 1,
  weekday: null,
  nth: null,
  colorPrimary: '#EC4899',
  colorSecondary: null,
  colorText: '#FFFFFF',
  emoji: '',
  enabled: true,
};

function holidayToInput(h: Holiday): HolidayInput {
  return {
    name: h.name,
    kind: h.kind,
    month: h.month,
    day: h.day,
    weekday: h.weekday,
    nth: h.nth,
    colorPrimary: h.colorPrimary,
    colorSecondary: h.colorSecondary,
    colorText: h.colorText,
    emoji: h.emoji ?? '',
    enabled: h.enabled,
  };
}

function describeWhen(h: Holiday): string {
  if (h.kind === 'fixed' && h.day != null) {
    return `${MONTH_NAMES[h.month]} ${h.day}`;
  }
  if (h.kind === 'nth_weekday' && h.weekday != null && h.nth != null) {
    const nthLabel = NTH_OPTIONS.find((o) => o.value === h.nth)?.label ?? `${h.nth}`;
    return `${nthLabel} ${WEEKDAY_NAMES[h.weekday]} of ${MONTH_NAMES[h.month]}`;
  }
  return '—';
}

export function HolidaysSettings() {
  const [holidays, setHolidays] = useState<Holiday[]>([]);
  const [editing, setEditing] = useState<{ id: number | 'new'; input: HolidayInput } | null>(null);
  const [status, setStatus] = useState<string>('');
  const [busy, setBusy] = useState(false);

  const { refresh } = useAsyncRefresh(async (alive) => {
    const list = await listHolidays();
    if (!alive()) return;
    setHolidays(list);
  }, []);

  const grouped = useMemo(() => {
    const byMonth = new Map<number, Holiday[]>();
    for (const h of holidays) {
      const arr = byMonth.get(h.month) ?? [];
      arr.push(h);
      byMonth.set(h.month, arr);
    }
    return Array.from(byMonth.entries()).sort((a, b) => a[0] - b[0]);
  }, [holidays]);

  async function save() {
    if (!editing) return;
    setBusy(true);
    try {
      if (editing.id === 'new') {
        await createHoliday(editing.input);
        setStatus(`Added ${editing.input.name}.`);
      } else {
        await updateHoliday(editing.id, editing.input);
        setStatus(`Saved ${editing.input.name}.`);
      }
      setEditing(null);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  async function toggleEnabled(h: Holiday) {
    setBusy(true);
    try {
      await setHolidayEnabled(h.id, !h.enabled);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't toggle: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  async function remove(h: Holiday) {
    if (!confirm(`Delete ${h.name}? This can't be undone (use "Reset to US defaults" to restore the standard set).`)) return;
    setBusy(true);
    try {
      await deleteHoliday(h.id);
      setStatus(`Removed ${h.name}.`);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't delete: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  async function resetDefaults() {
    if (!confirm('Reset the US default holiday set? Your custom-added holidays will be kept, but any edits to the default holidays will be reverted.')) return;
    setBusy(true);
    try {
      const n = await resetHolidaysToUSDefaults();
      setStatus(`Reset complete — ${n} default holidays restored.`);
      await refresh();
    } catch (e) {
      setStatus(`Couldn't reset: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-3">
      <div className="pretty-card">
        <div className="flex items-start justify-between mb-2">
          <div>
            <h3 className="display-font text-xl font-semibold persona-accent">🎉 Holidays</h3>
            <p className="text-sm opacity-70 mt-1">
              Holidays show up on the Calendar as pretty themed pills. Add custom ones, recolor the defaults,
              or hide individual entries with the toggle. Edits to the default set can always be reverted.
            </p>
          </div>
          <div className="flex gap-2 shrink-0">
            <button type="button" className="pretty-button secondary" onClick={resetDefaults} disabled={busy}>
              Reset US defaults
            </button>
            <button
              type="button"
              className="pretty-button"
              onClick={() => setEditing({ id: 'new', input: { ...EMPTY_INPUT } })}
              disabled={busy}
            >
              ＋ New holiday
            </button>
          </div>
        </div>

        {grouped.length === 0 && (
          <div className="text-sm opacity-60 italic">No holidays defined. Click <strong>＋ New holiday</strong> to add one, or <strong>Reset US defaults</strong>.</div>
        )}

        <div className="space-y-3">
          {grouped.map(([month, rows]) => (
            <section key={month}>
              <h4 className="text-xs uppercase tracking-wider opacity-60 mb-1">{MONTH_NAMES[month]}</h4>
              <ul className="space-y-1.5">
                {rows.map((h) => (
                  <li
                    key={h.id}
                    className="flex items-center gap-3 px-3 py-2 rounded-xl border"
                    style={{
                      borderColor: 'rgb(var(--persona-primary) / 0.25)',
                      background: h.enabled ? 'rgb(var(--persona-tint))' : 'rgba(0,0,0,0.04)',
                      opacity: h.enabled ? 1 : 0.6,
                    }}
                  >
                    <span
                      className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold whitespace-nowrap shrink-0"
                      style={holidayPillStyle(h)}
                    >
                      {h.emoji && <span aria-hidden>{h.emoji}</span>}
                      <span>{h.name}</span>
                    </span>
                    <div className="flex-1 min-w-0">
                      <div className="text-sm">{describeWhen(h)}</div>
                      <div className="text-xs opacity-60">{h.source === 'us_default' ? 'Default (US)' : 'Custom'}</div>
                    </div>
                    <button
                      type="button"
                      className="pretty-button secondary text-xs"
                      onClick={() => toggleEnabled(h)}
                      disabled={busy}
                    >
                      {h.enabled ? 'Hide' : 'Show'}
                    </button>
                    <button
                      type="button"
                      className="pretty-button secondary text-xs"
                      onClick={() => setEditing({ id: h.id, input: holidayToInput(h) })}
                      disabled={busy}
                    >
                      Edit
                    </button>
                    <button
                      type="button"
                      className="pretty-button danger text-xs"
                      onClick={() => remove(h)}
                      disabled={busy}
                    >
                      Delete
                    </button>
                  </li>
                ))}
              </ul>
            </section>
          ))}
        </div>
      </div>

      {editing && (
        <HolidayEditor
          input={editing.input}
          isNew={editing.id === 'new'}
          busy={busy}
          onChange={(input) => setEditing({ ...editing, input })}
          onCancel={() => setEditing(null)}
          onSave={save}
        />
      )}

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}

interface EditorProps {
  input: HolidayInput;
  isNew: boolean;
  busy: boolean;
  onChange: (input: HolidayInput) => void;
  onCancel: () => void;
  onSave: () => void;
}

function HolidayEditor({ input, isNew, busy, onChange, onCancel, onSave }: EditorProps) {
  const previewYear = new Date().getFullYear();
  const previewDate = useMemo(() => {
    // Build a stub Holiday for preview only — id/timestamps don't matter
    // because resolveHolidayForMonth only reads geometry.
    const stub: Holiday = {
      id: 0, name: input.name || 'Preview', kind: input.kind,
      month: input.month, day: input.day, weekday: input.weekday, nth: input.nth,
      colorPrimary: input.colorPrimary, colorSecondary: input.colorSecondary,
      colorText: input.colorText, emoji: input.emoji,
      enabled: true, source: 'custom', createdAt: '', updatedAt: '',
    };
    return resolveHolidayForMonth(stub, previewYear, input.month);
  }, [input, previewYear]);

  function update<K extends keyof HolidayInput>(key: K, value: HolidayInput[K]) {
    onChange({ ...input, [key]: value });
  }

  const monthDays = daysInMonth(previewYear, input.month);

  return (
    <div className="pretty-card space-y-3">
      <div className="flex items-center justify-between">
        <h4 className="display-font text-lg font-semibold persona-accent">
          {isNew ? 'New holiday' : `Edit: ${input.name}`}
        </h4>
        <span
          className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold"
          style={holidayPillStyle({
            ...input, id: 0, source: 'custom', enabled: true, createdAt: '', updatedAt: '',
          } as Holiday)}
        >
          {input.emoji && <span aria-hidden>{input.emoji}</span>}
          <span>{input.name || 'Preview'}</span>
        </span>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <label className="flex flex-col gap-1">
          <span className="text-xs uppercase tracking-wider opacity-60">Name</span>
          <input
            className="pretty-input"
            value={input.name}
            onChange={(e) => update('name', e.target.value)}
            placeholder="e.g. Sallie's Birthday"
          />
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-xs uppercase tracking-wider opacity-60">Emoji (optional)</span>
          <input
            className="pretty-input"
            value={input.emoji ?? ''}
            onChange={(e) => update('emoji', e.target.value)}
            placeholder="🎂"
            maxLength={4}
          />
        </label>

        <label className="flex flex-col gap-1 col-span-2">
          <span className="text-xs uppercase tracking-wider opacity-60">Kind</span>
          <select
            className="pretty-input"
            value={input.kind}
            onChange={(e) => {
              const kind = e.target.value as HolidayKind;
              if (kind === 'fixed') {
                onChange({ ...input, kind, weekday: null, nth: null, day: input.day ?? 1 });
              } else {
                onChange({ ...input, kind, day: null, weekday: input.weekday ?? 1, nth: input.nth ?? 1 });
              }
            }}
          >
            <option value="fixed">Fixed date — same day every year (e.g. July 4)</option>
            <option value="nth_weekday">Nth weekday — e.g. 3rd Monday of January</option>
          </select>
        </label>

        <label className="flex flex-col gap-1">
          <span className="text-xs uppercase tracking-wider opacity-60">Month</span>
          <select
            className="pretty-input"
            value={input.month}
            onChange={(e) => update('month', Number(e.target.value))}
          >
            {MONTH_NAMES.slice(1).map((name, i) => (
              <option key={i + 1} value={i + 1}>{name}</option>
            ))}
          </select>
        </label>

        {input.kind === 'fixed' ? (
          <label className="flex flex-col gap-1">
            <span className="text-xs uppercase tracking-wider opacity-60">Day</span>
            <select
              className="pretty-input"
              value={input.day ?? 1}
              onChange={(e) => update('day', Number(e.target.value))}
            >
              {Array.from({ length: monthDays }, (_, i) => i + 1).map((d) => (
                <option key={d} value={d}>{d}</option>
              ))}
            </select>
          </label>
        ) : (
          <>
            <label className="flex flex-col gap-1">
              <span className="text-xs uppercase tracking-wider opacity-60">Weekday</span>
              <select
                className="pretty-input"
                value={input.weekday ?? 1}
                onChange={(e) => update('weekday', Number(e.target.value))}
              >
                {WEEKDAY_NAMES.map((name, i) => (
                  <option key={i} value={i}>{name}</option>
                ))}
              </select>
            </label>
            <label className="flex flex-col gap-1 col-span-2">
              <span className="text-xs uppercase tracking-wider opacity-60">Which one?</span>
              <select
                className="pretty-input"
                value={input.nth ?? 1}
                onChange={(e) => update('nth', Number(e.target.value))}
              >
                {NTH_OPTIONS.map((o) => (
                  <option key={o.value} value={o.value}>{o.label}</option>
                ))}
              </select>
            </label>
          </>
        )}

        <ColorPicker label="Primary color" value={input.colorPrimary} onChange={(v) => update('colorPrimary', v)} />
        <ColorPicker
          label="Secondary color (optional — adds a stripe)"
          value={input.colorSecondary ?? ''}
          onChange={(v) => update('colorSecondary', v.trim() === '' ? null : v)}
        />
        <ColorPicker label="Text color" value={input.colorText} onChange={(v) => update('colorText', v)} />

        <label className="col-span-2 flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={input.enabled}
            onChange={(e) => update('enabled', e.target.checked)}
          />
          Show on calendar
        </label>

        {previewDate && (
          <div className="col-span-2 text-xs opacity-60">
            In {previewYear}, this falls on <strong>{previewDate}</strong>.
          </div>
        )}
      </div>

      <div className="flex justify-end gap-2">
        <button type="button" className="pretty-button secondary" onClick={onCancel} disabled={busy}>Cancel</button>
        <button
          type="button"
          className="pretty-button"
          onClick={onSave}
          disabled={busy || !input.name.trim()}
        >
          {isNew ? '＋ Add holiday' : 'Save'}
        </button>
      </div>
    </div>
  );
}
