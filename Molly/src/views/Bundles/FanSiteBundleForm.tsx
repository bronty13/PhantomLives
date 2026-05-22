import { useCallback, useEffect, useMemo, useState } from 'react';
import { db } from '../../data/db';
import {
  type Bundle,
  deleteBundleDraft,
  getBundle,
  updateBundleFields,
} from '../../data/bundles';
import { listPersonas, type Persona } from '../../data/personas';
import { daysInMonth } from '../../lib/bundleValidation';
import { FanDayCell } from './components/FanDayCell';
import { FanDayModal } from './components/FanDayModal';
import { SpecialInstructionsField } from './components/SpecialInstructionsField';
import { TitleField } from './components/TitleField';

interface Props {
  uid: string;
  onPublishRequested: () => void;
  onClose: () => void;
  onDeleted?: () => void;
  locked?: boolean;
}

export function FanSiteBundleForm({ uid, onPublishRequested, onClose, onDeleted, locked }: Props) {
  const [bundle, setBundle] = useState<Bundle | null>(null);
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [openDay, setOpenDay] = useState<number | null>(null);

  const reload = useCallback(async () => {
    const b = await getBundle(uid);
    setBundle(b);
  }, [uid]);

  useEffect(() => {
    let alive = true;
    Promise.all([reload(), listPersonas()])
      .then(([_, p]) => { if (alive) setPersonas(p); })
      .catch((e) => alive && setError(String(e)));
    return () => { alive = false; };
  }, [reload]);

  async function withBusy<T>(fn: () => Promise<T>): Promise<T | null> {
    setBusy(true); setError(null);
    try { return await fn(); }
    catch (e) { setError(String(e)); return null; }
    finally { setBusy(false); }
  }
  async function setPersona(code: string | null) {
    await withBusy(async () => {
      const conn = await db();
      await conn.execute('UPDATE bundles SET persona_code = $1, updated_at = datetime(\'now\') WHERE uid = $2', [code, uid]);
      await reload();
    });
  }
  async function commitTitle(s: string) {
    await withBusy(async () => { await updateBundleFields(uid, { title: s }); await reload(); });
  }
  async function commitSpecial(s: string) {
    await withBusy(async () => { await updateBundleFields(uid, { specialInstructions: s }); await reload(); });
  }
  async function commitYearMonth(year: number | null, month: number | null) {
    await withBusy(async () => {
      await updateBundleFields(uid, { fansiteYear: year, fansiteMonth: month });
      await reload();
    });
  }
  async function onDeleteDraft() {
    if (locked) return;
    if (!confirm('Delete this draft, including every day’s files and messages?')) return;
    const ok = await withBusy(async () => { await deleteBundleDraft(uid); });
    if (ok !== null) { onDeleted?.(); onClose(); }
  }

  const completionStats = useMemo(() => {
    if (!bundle?.fansiteYear || !bundle?.fansiteMonth) return null;
    const total = daysInMonth(bundle.fansiteYear, bundle.fansiteMonth);
    if (total === 0) return null;
    const byDay = new Map(bundle.fanDays.map((d) => [d.dayOfMonth, d]));
    let complete = 0;
    let partial = 0;
    for (let day = 1; day <= total; day++) {
      const d = byDay.get(day);
      const hasMessage = !!d && d.message.trim().length > 0;
      const hasFile = !!d && d.fileCount >= 1;
      if (hasMessage && hasFile) complete++;
      else if (hasMessage || hasFile) partial++;
    }
    return { total, complete, partial, empty: total - complete - partial };
  }, [bundle?.fansiteYear, bundle?.fansiteMonth, bundle?.fanDays]);

  if (!bundle) {
    return <div className="p-8 opacity-60 italic">Loading bundle…</div>;
  }

  return (
    <div className="p-8 space-y-5 max-w-4xl">
      <div className="flex items-center justify-between gap-2 -mt-2 mb-1">
        <button type="button" onClick={onClose} className="pretty-button secondary">← Bundles</button>
        {!locked && (
          <button type="button" onClick={onDeleteDraft} className="pretty-button danger text-xs" disabled={busy}>🗑 Delete draft</button>
        )}
      </div>
      <header className="space-y-1">
        <div className="flex items-baseline justify-between gap-3">
          <h2 className="display-font text-2xl font-bold persona-accent">Fan Site Bundle</h2>
          <span className="text-xs font-mono opacity-60">{uid}</span>
        </div>
        <p className="opacity-70 text-sm">
          One whole month of fan-site posts. Click each day to add a message + files.
          Bundle becomes publishable when every day is complete.
        </p>
        {error && (
          <div className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2">{error}</div>
        )}
      </header>

      <fieldset disabled={locked} className="space-y-5">
        <PersonaPicker personas={personas} value={bundle.summary.personaCode} onChange={setPersona} />

        <TitleField value={bundle.summary.title} onCommit={commitTitle} disabled={busy || locked} />

        <YearMonthPicker
          year={bundle.fansiteYear}
          month={bundle.fansiteMonth}
          onChange={commitYearMonth}
          disabled={busy || locked}
        />

        {bundle.fansiteYear != null && bundle.fansiteMonth != null && (
          <CalendarGrid
            bundle={bundle}
            year={bundle.fansiteYear}
            month={bundle.fansiteMonth}
            onClickDay={(d) => setOpenDay(d)}
          />
        )}

        {completionStats && (
          <CompletionBar stats={completionStats} />
        )}

        <SpecialInstructionsField
          value={bundle.specialInstructions}
          onCommit={commitSpecial}
          disabled={busy || locked}
        />
      </fieldset>

      <div className="flex justify-end gap-2 pt-2 border-t border-black/5">
        <button type="button" onClick={onPublishRequested} className="pretty-button">
          🎁 Review &amp; Publish…
        </button>
      </div>

      {openDay != null && (
        <FanDayModal
          bundleUid={uid}
          dayOfMonth={openDay}
          bundle={bundle}
          onClose={() => setOpenDay(null)}
          onChanged={reload}
        />
      )}
    </div>
  );
}

function PersonaPicker({
  personas, value, onChange,
}: { personas: Persona[]; value: string | null; onChange: (code: string | null) => void; }) {
  return (
    <div className="space-y-1">
      <label htmlFor="bundle-persona" className="text-xs font-semibold opacity-75">Persona</label>
      <select id="bundle-persona" className="pretty-input" value={value ?? ''} onChange={(e) => onChange(e.target.value || null)}>
        <option value="">— required —</option>
        {personas.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}
      </select>
    </div>
  );
}

function YearMonthPicker({
  year, month, onChange, disabled,
}: { year: number | null; month: number | null; onChange: (y: number | null, m: number | null) => void; disabled?: boolean }) {
  const now = new Date();
  const yearOptions = [now.getFullYear() - 1, now.getFullYear(), now.getFullYear() + 1];
  return (
    <div className="space-y-1" id="bundle-fansite-month" tabIndex={-1}>
      <label className="text-xs font-semibold opacity-75">Month being planned</label>
      <div className="flex gap-2">
        <select
          className="pretty-input"
          value={year ?? ''}
          onChange={(e) => onChange(e.target.value === '' ? null : Number(e.target.value), month)}
          disabled={disabled}
        >
          <option value="">— year —</option>
          {yearOptions.map((y) => <option key={y} value={y}>{y}</option>)}
        </select>
        <select
          className="pretty-input"
          value={month ?? ''}
          onChange={(e) => onChange(year, e.target.value === '' ? null : Number(e.target.value))}
          disabled={disabled}
        >
          <option value="">— month —</option>
          {Array.from({ length: 12 }, (_, i) => i + 1).map((m) => (
            <option key={m} value={m}>{monthName(m)}</option>
          ))}
        </select>
      </div>
    </div>
  );
}

function monthName(m: number): string {
  return ['January', 'February', 'March', 'April', 'May', 'June',
          'July', 'August', 'September', 'October', 'November', 'December'][m - 1] ?? '';
}

function CalendarGrid({
  bundle, year, month, onClickDay,
}: { bundle: Bundle; year: number; month: number; onClickDay: (d: number) => void }) {
  const total = daysInMonth(year, month);
  if (total === 0) return null;
  const firstWeekday = new Date(year, month - 1, 1).getDay(); // 0=Sun
  const cells: { day: number; inMonth: boolean }[] = [];
  for (let i = 0; i < firstWeekday; i++) cells.push({ day: 0, inMonth: false });
  for (let d = 1; d <= total; d++) cells.push({ day: d, inMonth: true });
  while (cells.length % 7 !== 0) cells.push({ day: 0, inMonth: false });

  const byDay = new Map(bundle.fanDays.map((d) => [d.dayOfMonth, d]));

  return (
    <div className="space-y-2">
      <div className="grid grid-cols-7 gap-1 text-[10px] font-semibold opacity-60 text-center">
        {['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map((d) => <div key={d}>{d}</div>)}
      </div>
      <div className="grid grid-cols-7 gap-1">
        {cells.map((c, i) => {
          if (!c.inMonth) {
            return <div key={`pad-${i}`} className="aspect-square" />;
          }
          const day = byDay.get(c.day);
          const hasMessage = !!day && day.message.trim().length > 0;
          const hasFile = !!day && day.fileCount >= 1;
          const isComplete = hasMessage && hasFile;
          const hasPartial = !isComplete && (hasMessage || hasFile);
          return (
            <FanDayCell
              key={c.day}
              dayOfMonth={c.day}
              isInMonth={c.inMonth}
              isComplete={isComplete}
              hasPartial={hasPartial}
              onClick={() => onClickDay(c.day)}
            />
          );
        })}
      </div>
    </div>
  );
}

function CompletionBar({ stats }: { stats: { total: number; complete: number; partial: number; empty: number } }) {
  const pct = stats.total === 0 ? 0 : (stats.complete / stats.total) * 100;
  return (
    <div className="space-y-1">
      <div className="flex items-baseline justify-between text-xs">
        <span className="font-semibold opacity-75">Completion</span>
        <span className="opacity-70 font-mono">
          {stats.complete}/{stats.total} complete
          {stats.partial > 0 && ` · ${stats.partial} partial`}
        </span>
      </div>
      <div className="h-3 rounded-full overflow-hidden bg-white/60 border border-black/10">
        <div
          className="h-full transition-all"
          style={{ width: `${pct}%`, background: 'rgb(var(--persona-accent))' }}
        />
      </div>
    </div>
  );
}
