import type { CalendarBundle } from '../../model/types';
import { MONTH_NAMES } from '../../model/types';
import { resolveHolidaysForMonth } from '../../calendar/holidayResolver';
import { parseIso } from '../../calendar/dateUtil';
import { Drawer } from '../components/Modal';

const CATEGORY_LABEL: Record<string, string> = { federal: 'Federal', observance: 'Observance', christian: 'Christian' };

export function HolidaysPanel({ bundle, onChange, onClose }: { bundle: CalendarBundle; onChange: (b: CalendarBundle) => void; onClose: () => void }) {
  const resolved = resolveHolidaysForMonth(bundle.year, bundle.month);

  const isOn = (date: string, id: string) => bundle.days[date]?.holidayIds.includes(id) ?? false;

  const toggle = (date: string, id: string) => {
    const existing = bundle.days[date] ?? { date, items: [], holidayIds: [] };
    const has = existing.holidayIds.includes(id);
    const holidayIds = has ? existing.holidayIds.filter((h) => h !== id) : [...existing.holidayIds, id];
    const day = { ...existing, holidayIds };
    const days = { ...bundle.days, [date]: day };
    if (day.items.length === 0 && day.holidayIds.length === 0) delete days[date];
    onChange({ ...bundle, days });
  };

  return (
    <Drawer title={`Holidays — ${MONTH_NAMES[bundle.month - 1]} ${bundle.year}`} onClose={onClose}>
      <p className="hint" style={{ marginTop: 0 }}>Turn on the holidays you want shown on this calendar.</p>
      {resolved.length === 0 && <div className="empty">No holidays fall in this month.</div>}
      {resolved.map((h, i) => {
        const { day } = parseIso(h.date);
        const on = isOn(h.date, h.def.id);
        return (
          <div className="pill-toggle" key={`${h.def.id}-${h.date}-${i}`}>
            <div>
              <div style={{ fontWeight: 600 }}>{h.def.name}{h.observed ? ' (observed)' : ''}</div>
              <div className="hint">{MONTH_NAMES[bundle.month - 1]} {day} · {CATEGORY_LABEL[h.def.category]}</div>
            </div>
            <button className={on ? 'primary' : ''} onClick={() => toggle(h.date, h.def.id)}>{on ? 'On' : 'Off'}</button>
          </div>
        );
      })}
    </Drawer>
  );
}
