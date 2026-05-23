import { useEffect, useState } from 'react';
import type { Persona } from '../../state/personas';
import {
  completeDailyTask,
  createDailyTask,
  deleteDailyTask,
  listDailyTasks,
  todayIso,
  undoDailyTask,
  type DailyCategory,
  type DailyTask,
} from '../../data/dailyTasks';

const QUICK_TASKS: { label: string; category: DailyCategory }[] = [
  { label: 'Reddit posts — Curves',    category: 'reddit' },
  { label: 'Reddit posts — Princess',  category: 'reddit' },
  { label: 'Reply to comments',        category: 'reddit' },
  { label: 'Upload YouTube video',     category: 'youtube' },
  { label: 'Post YT Short',            category: 'youtube' },
  { label: 'Post TikTok',              category: 'content' },
  { label: 'Post Reel',                category: 'content' },
  { label: 'Film batch session',       category: 'content' },
  { label: 'Check fan site queue',     category: 'admin' },
  { label: 'Check PTV store',          category: 'admin' },
  { label: 'Log hours',                category: 'admin' },
];

const CAT_LABEL: Record<DailyCategory, string> = {
  reddit:  'Reddit',
  youtube: 'YouTube',
  content: 'Content',
  admin:   'Admin',
  other:   'Other',
};

const CAT_COLORS: Record<DailyCategory, { bg: string; fg: string }> = {
  reddit:  { bg: '#FBEAF0', fg: '#72243E' },
  youtube: { bg: '#FFE9E9', fg: '#A32D2D' },
  content: { bg: '#EBF5FB', fg: '#1A5276' },
  admin:   { bg: '#FEF9E7', fg: '#854F0B' },
  other:   { bg: '#F1EFE8', fg: '#444444' },
};

interface Props {
  active: Persona;
}

export function TodaySection({ active }: Props) {
  const [tasks, setTasks] = useState<DailyTask[]>([]);
  const [text, setText] = useState('');
  const [cat, setCat] = useState<DailyCategory>('reddit');
  const [status, setStatus] = useState('');
  const personaCode = active.code === 'ALL' ? null : active.code;

  async function refresh() {
    try {
      const rows = await listDailyTasks(todayIso(), personaCode);
      setTasks(rows);
    } catch (e) {
      setStatus(String(e));
    }
  }

  useEffect(() => {
    refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active.code]);

  async function add(predefined?: { text: string; category: DailyCategory }) {
    const t = predefined?.text ?? text.trim();
    const c = predefined?.category ?? cat;
    if (!t) return;
    try {
      await createDailyTask({
        personaCode,
        forDate: todayIso(),
        text: t,
        category: c,
      });
      if (!predefined) setText('');
      await refresh();
    } catch (e) {
      setStatus(String(e));
    }
  }

  async function complete(id: number) {
    try { await completeDailyTask(id); await refresh(); }
    catch (e) { setStatus(String(e)); }
  }
  async function undo(id: number) {
    try { await undoDailyTask(id); await refresh(); }
    catch (e) { setStatus(String(e)); }
  }
  async function remove(id: number) {
    try { await deleteDailyTask(id); await refresh(); }
    catch (e) { setStatus(String(e)); }
  }

  const open = tasks.filter((t) => !t.doneAt);
  const done = tasks.filter((t) => !!t.doneAt);
  const pct = tasks.length === 0 ? 0 : Math.round((done.length / tasks.length) * 100);

  return (
    <div className="space-y-3">
      <div
        className="pretty-card flex items-center gap-6 flex-wrap"
        style={{ background: 'rgb(var(--persona-tint))' }}
      >
        <div>
          <div className="display-font text-2xl font-bold persona-accent">
            {new Date().toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' })}
          </div>
          <div className="text-xs opacity-60">Daily master list · resets at midnight</div>
        </div>
        <div className="flex gap-6 ml-auto">
          <Stat n={open.length} label="to do" />
          <Stat n={done.length} label="done" />
          <Stat n={`${pct}%`} label="complete" />
        </div>
      </div>

      <div className="pretty-card">
        <div className="text-xs uppercase tracking-wider opacity-60 mb-2">Quick add</div>
        <div className="flex flex-wrap gap-1.5 mb-3">
          {QUICK_TASKS.map((q) => (
            <button
              key={q.label}
              type="button"
              className="text-xs px-2.5 py-1 rounded-full border bg-white/70 hover:bg-white"
              style={{ borderColor: 'rgb(var(--persona-primary) / 0.4)' }}
              onClick={() => add({ text: q.label, category: q.category })}
            >
              + {q.label}
            </button>
          ))}
        </div>
        <div className="flex gap-2 flex-wrap">
          <input
            className="pretty-input flex-1 min-w-[200px]"
            placeholder="Add a task…"
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') add(); }}
          />
          <select className="pretty-input" value={cat} onChange={(e) => setCat(e.target.value as DailyCategory)}>
            {(Object.keys(CAT_LABEL) as DailyCategory[]).map((c) => (
              <option key={c} value={c}>{CAT_LABEL[c]}</option>
            ))}
          </select>
          <button type="button" className="pretty-button" onClick={() => add()}>+ Add</button>
        </div>
      </div>

      <section>
        <div className="text-[10px] font-bold uppercase tracking-widest opacity-60 mb-1.5">To do</div>
        {open.length === 0 ? (
          <div className="pretty-card text-sm opacity-60 italic">Nothing left — great work! 🎉</div>
        ) : (
          <ul className="space-y-1.5">
            {open.map((t) => (
              <li key={t.id} className="pretty-card flex items-center gap-3 py-2.5">
                <CatPill cat={t.category} />
                <span className="flex-1 text-sm font-medium">{t.text}</span>
                <button
                  type="button"
                  className="text-xs font-semibold px-3 py-1 rounded-lg border-2"
                  style={{ borderColor: '#2ecc71', color: '#2ecc71' }}
                  onClick={() => complete(t.id)}
                >
                  ✓ Done
                </button>
                <button
                  type="button"
                  className="text-base opacity-50 hover:opacity-100 hover:text-red-600 px-1"
                  onClick={() => remove(t.id)}
                  title="Delete"
                >
                  ✕
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>

      {done.length > 0 && (
        <section>
          <div className="text-[10px] font-bold uppercase tracking-widest opacity-60 mb-1.5">Completed today</div>
          <ul className="space-y-1.5">
            {done.map((t) => (
              <li
                key={t.id}
                className="flex items-center gap-3 rounded-xl px-3 py-2 border"
                style={{ background: '#eafbf1', borderColor: '#a8e6c1' }}
              >
                <span style={{ color: '#2ecc71' }}>✓</span>
                <span className="flex-1 text-xs line-through" style={{ color: '#1a7a45' }}>{t.text}</span>
                <span className="text-[10px]" style={{ color: '#2a9a55' }}>
                  {t.doneAt && new Date(t.doneAt + 'Z').toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}
                </span>
                <button
                  type="button"
                  className="text-[11px] underline"
                  style={{ color: '#2a9a55' }}
                  onClick={() => undo(t.id)}
                >
                  undo
                </button>
              </li>
            ))}
          </ul>
        </section>
      )}

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}

function Stat({ n, label }: { n: number | string; label: string }) {
  return (
    <div className="text-center">
      <div className="display-font text-2xl font-bold persona-accent leading-none">{n}</div>
      <div className="text-[10px] uppercase tracking-wider opacity-60 mt-0.5">{label}</div>
    </div>
  );
}

function CatPill({ cat }: { cat: DailyCategory }) {
  const c = CAT_COLORS[cat];
  return (
    <span
      className="text-[9px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-full whitespace-nowrap"
      style={{ background: c.bg, color: c.fg }}
    >
      {CAT_LABEL[cat]}
    </span>
  );
}
