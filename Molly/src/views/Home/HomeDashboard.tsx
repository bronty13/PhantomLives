import { useEffect, useMemo, useState, type ReactNode } from 'react';
import type { Persona } from '../../state/personas';
import { clipCounts, countByPersona, detectReuse, recentImports, type ClipCounts, type ClipImportLog, type PersonaCount, type ReuseGroup } from '../../data/clips';
import { listPersonas, type Persona as PersonaRow } from '../../data/personas';
import { listOverdue, listToday, describeDueDate, type Occurrence } from '../../data/occurrences';
import { SayingsBanner } from '../../components/SayingsBanner';
import { TimersPanel } from './TimersPanel';

interface Props {
  active: Persona;
  onGoTo: (view: 'reminders') => void;
}

// Reorderable section IDs. The Saying banner and Welcome card stay locked
// at the top, and the Error card stays locked at the bottom (conditional).
// Sallie can rearrange everything in between; her chosen order persists
// across launches via localStorage under HOME_ORDER_KEY.
type HomeSectionId =
  | 'dueReminders'
  | 'stats'
  | 'clipsPerPersona'
  | 'reuse'
  | 'recentImports';

const DEFAULT_ORDER: HomeSectionId[] = [
  'dueReminders',
  'stats',
  'clipsPerPersona',
  'reuse',
  'recentImports',
];

const HOME_ORDER_KEY = 'molly:home:order';

function loadOrder(): HomeSectionId[] {
  try {
    const raw = localStorage.getItem(HOME_ORDER_KEY);
    if (!raw) return DEFAULT_ORDER;
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return DEFAULT_ORDER;
    const known = parsed.filter((id): id is HomeSectionId =>
      typeof id === 'string' && (DEFAULT_ORDER as string[]).includes(id),
    );
    // Forwards compat: append any newly-added sections at the bottom so
    // they don't disappear when an old saved order is shorter.
    for (const id of DEFAULT_ORDER) {
      if (!known.includes(id)) known.push(id);
    }
    return known;
  } catch {
    return DEFAULT_ORDER;
  }
}

function saveOrder(order: HomeSectionId[]): void {
  try {
    localStorage.setItem(HOME_ORDER_KEY, JSON.stringify(order));
  } catch {
    // localStorage can throw in private-browsing edge cases; preference
    // failing to persist is not worth surfacing.
  }
}

export function HomeDashboard({ active, onGoTo }: Props) {
  const [counts, setCounts] = useState<ClipCounts | null>(null);
  const [byPersona, setByPersona] = useState<PersonaCount[]>([]);
  const [reuse, setReuse] = useState<ReuseGroup[]>([]);
  const [imports, setImports] = useState<ClipImportLog[]>([]);
  const [personas, setPersonas] = useState<PersonaRow[]>([]);
  const [today, setToday] = useState<Occurrence[]>([]);
  const [overdue, setOverdue] = useState<Occurrence[]>([]);
  const [error, setError] = useState<string | null>(null);

  const [order, setOrder] = useState<HomeSectionId[]>(() => loadOrder());
  const [draggingId, setDraggingId] = useState<HomeSectionId | null>(null);
  const [dropTargetId, setDropTargetId] = useState<HomeSectionId | null>(null);

  useEffect(() => {
    let alive = true;
    const opts = active.code === 'ALL' ? undefined : { personaCode: active.code };
    Promise.all([
      clipCounts(active.code === 'ALL' ? undefined : active.code),
      countByPersona(),
      detectReuse(),
      recentImports(5),
      listPersonas(),
      listToday(opts),
      listOverdue(opts),
    ])
      .then(([c, bp, r, im, p, t, o]) => {
        if (!alive) return;
        setCounts(c);
        setByPersona(bp);
        setReuse(r);
        setImports(im);
        setPersonas(p);
        setToday(t);
        setOverdue(o);
      })
      .catch((e) => setError(String(e)));
    return () => {
      alive = false;
    };
  }, [active.code]);

  const personaByCode = new Map(personas.map((p) => [p.code, p]));
  const totalForBars = byPersona.reduce((acc, x) => acc + x.count, 0) || 1;

  function reorder(fromId: HomeSectionId, toId: HomeSectionId) {
    if (fromId === toId) return;
    setOrder((cur) => {
      const next = cur.filter((id) => id !== fromId);
      const idx = next.indexOf(toId);
      next.splice(idx, 0, fromId);
      saveOrder(next);
      return next;
    });
  }

  // Build each reorderable section's content once. `null` means the
  // section has nothing to show right now — we still render the
  // wrapper so the drop slot stays available, but invisibly.
  const sectionContent: Record<HomeSectionId, ReactNode> = {
    dueReminders:
      overdue.length > 0 || today.length > 0 ? (
        <DueRemindersCard
          overdue={overdue}
          today={today}
          personaByCode={personaByCode}
          onGoTo={onGoTo}
        />
      ) : null,
    stats: <StatsRow counts={counts} />,
    clipsPerPersona: (
      <ClipsPerPersonaCard
        byPersona={byPersona}
        personaByCode={personaByCode}
        totalForBars={totalForBars}
      />
    ),
    reuse: <ReuseCard reuse={reuse} personaByCode={personaByCode} />,
    recentImports: <RecentImportsCard imports={imports} />,
  };

  return (
    <div className="p-8 space-y-4 max-w-5xl">
      <SayingsBanner variant="hero" rerollKey={active.code} />

      <WelcomeCard active={active} />

      <div className="text-[10px] font-bold uppercase tracking-widest opacity-50 px-1">
        Your dashboard <span className="opacity-60 normal-case font-medium tracking-normal">· drag ⋮⋮ to reorder</span>
      </div>

      {order.map((id) => {
        const content = sectionContent[id];
        if (content === null) {
          // Section is empty right now; render a zero-height placeholder
          // so its position in the order is preserved without showing UI.
          return <div key={id} />;
        }
        const isDragging = draggingId === id;
        const isDropTarget = dropTargetId === id && draggingId !== null && draggingId !== id;
        return (
          <div
            key={id}
            draggable
            onDragStart={(e) => {
              setDraggingId(id);
              e.dataTransfer.effectAllowed = 'move';
              e.dataTransfer.setData('text/plain', id);
            }}
            onDragOver={(e) => {
              if (draggingId !== null && draggingId !== id) {
                e.preventDefault();
                e.dataTransfer.dropEffect = 'move';
                if (dropTargetId !== id) setDropTargetId(id);
              }
            }}
            onDragLeave={() => {
              if (dropTargetId === id) setDropTargetId(null);
            }}
            onDrop={(e) => {
              e.preventDefault();
              if (draggingId !== null) reorder(draggingId, id);
              setDraggingId(null);
              setDropTargetId(null);
            }}
            onDragEnd={() => {
              setDraggingId(null);
              setDropTargetId(null);
            }}
            className="relative transition"
            style={{
              opacity: isDragging ? 0.45 : 1,
              cursor: isDragging ? 'grabbing' : 'grab',
              outline: isDropTarget ? '2px solid rgb(var(--persona-accent))' : 'none',
              outlineOffset: isDropTarget ? '4px' : 0,
              borderRadius: '1.25rem',
              userSelect: 'none',
            }}
          >
            <span
              aria-hidden
              className="absolute top-3 right-3 z-10 text-base opacity-30 hover:opacity-70 select-none pointer-events-none"
              title="Drag to reorder"
            >
              ⋮⋮
            </span>
            {content}
          </div>
        );
      })}

      {error && <div className="pretty-card text-sm text-red-700"><strong>Error:</strong> {error}</div>}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Locked top card — welcome + live clock
// ---------------------------------------------------------------------------

function WelcomeCard({ active }: { active: Persona }) {
  return (
    <div className="pretty-card">
      <div className="text-xs uppercase tracking-wider opacity-60">welcome back</div>
      <h2 className="display-font text-3xl font-bold persona-accent mt-1">Hi, I'm Molly 💕</h2>
      <p className="opacity-80 mt-2">
        {active.code === 'ALL'
          ? 'Cross-persona dashboard. Pick a persona to filter.'
          : `Dashboard filtered to ${active.name}. Pick ★ All to see everything.`}
      </p>
      <PrettyClock />
      <TimersPanel />
    </div>
  );
}

function PrettyClock() {
  const [now, setNow] = useState<Date>(() => new Date());
  useEffect(() => {
    // Wall-clock display — no seconds, no need to re-render every second.
    // Align the first tick to the next minute boundary so the visible
    // minute flips precisely on :00 instead of drifting up to a minute
    // late; from then on, repeat every 60s.
    const interval: { id: number | null } = { id: null };
    const msToNextMinute = 60_000 - (Date.now() % 60_000);
    const initial = window.setTimeout(() => {
      setNow(new Date());
      interval.id = window.setInterval(() => setNow(new Date()), 60_000);
    }, msToNextMinute);
    return () => {
      window.clearTimeout(initial);
      if (interval.id !== null) window.clearInterval(interval.id);
    };
  }, []);

  const time = useMemo(
    () => now.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true }).toLowerCase(),
    [now],
  );
  const dayOfWeek = useMemo(() => now.toLocaleDateString('en-US', { weekday: 'long' }), [now]);
  const dateStr = useMemo(() => formatPrettyDate(now), [now]);

  return (
    <div
      className="mt-4 flex items-end gap-4 flex-wrap rounded-2xl px-4 py-3"
      style={{
        background:
          'linear-gradient(135deg, rgb(var(--persona-secondary) / 0.55), rgb(var(--persona-tint) / 0.85))',
        border: '1px solid rgb(var(--persona-primary) / 0.35)',
      }}
    >
      <span
        className="persona-accent"
        style={{
          fontFamily: 'Caveat, "Paper Daisy", cursive',
          fontSize: '3.25rem',
          lineHeight: 0.9,
          fontWeight: 600,
          letterSpacing: '0.5px',
        }}
      >
        {time}
      </span>
      <div className="leading-tight pb-1">
        <div
          className="display-font font-semibold"
          style={{ fontSize: '1.05rem', color: 'rgb(var(--persona-accent))' }}
        >
          {dayOfWeek}
        </div>
        <div className="text-sm opacity-75">{dateStr}</div>
      </div>
    </div>
  );
}

function ordinal(n: number): string {
  const suffixes = ['th', 'st', 'nd', 'rd'];
  const mod100 = n % 100;
  const suffix = suffixes[(mod100 - 20) % 10] ?? suffixes[mod100] ?? suffixes[0];
  return `${n}${suffix}`;
}

function formatPrettyDate(d: Date): string {
  const month = d.toLocaleDateString('en-US', { month: 'long' });
  return `${month} ${ordinal(d.getDate())}, ${d.getFullYear()}`;
}

// ---------------------------------------------------------------------------
// Reorderable section cards
// ---------------------------------------------------------------------------

function DueRemindersCard({
  overdue,
  today,
  personaByCode,
  onGoTo,
}: {
  overdue: Occurrence[];
  today: Occurrence[];
  personaByCode: Map<string, PersonaRow>;
  onGoTo: (view: 'reminders') => void;
}) {
  return (
    <div className="pretty-card">
      <div className="flex items-center justify-between mb-2">
        <h3 className="display-font text-lg font-semibold persona-accent">
          {overdue.length > 0
            ? `⏰ ${overdue.length} overdue, ${today.length} today`
            : `💖 ${today.length} due today`}
        </h3>
        <button
          type="button"
          className="pretty-button secondary"
          draggable={false}
          onClick={() => onGoTo('reminders')}
        >
          Open Reminders →
        </button>
      </div>
      <div className="space-y-1.5">
        {[
          ...overdue.slice(0, 4),
          ...today.slice(0, Math.max(0, 4 - Math.min(overdue.length, 4))),
        ].map((o) => {
          const p = o.personaCode ? personaByCode.get(o.personaCode) : null;
          const isOverdue = overdue.some((x) => x.id === o.id);
          return (
            <div
              key={o.id}
              className="flex items-center gap-2 text-sm p-2 rounded-lg"
              style={{
                background: isOverdue
                  ? 'rgba(254, 226, 226, 0.4)'
                  : 'rgb(var(--persona-tint))',
                border: `1px solid ${isOverdue ? '#fca5a5' : 'rgb(var(--persona-primary) / 0.35)'}`,
              }}
            >
              {p ? (
                <span
                  className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold"
                  style={{ background: p.primaryColor, color: p.textColor }}
                >
                  {p.code}
                </span>
              ) : (
                <span className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold bg-black/10">ALL</span>
              )}
              <span className="font-semibold flex-1 truncate">{o.scheduleName}</span>
              <span className="text-xs opacity-70">{describeDueDate(o.dueAt)}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function StatsRow({ counts }: { counts: ClipCounts | null }) {
  return (
    <div className="grid grid-cols-3 gap-3">
      <Stat title="This month" value={counts?.mtd ?? 0} sub={`vs ${counts?.priorMtd ?? 0} last month`} />
      <Stat title="Year to date" value={counts?.ytd ?? 0} sub="clip releases" />
      <Stat title="All time" value={counts?.total ?? 0} sub="clips on file" />
    </div>
  );
}

function ClipsPerPersonaCard({
  byPersona,
  personaByCode,
  totalForBars,
}: {
  byPersona: PersonaCount[];
  personaByCode: Map<string, PersonaRow>;
  totalForBars: number;
}) {
  return (
    <div className="pretty-card">
      <h3 className="display-font text-lg font-semibold persona-accent mb-3">Clips per persona</h3>
      {byPersona.length === 0 && <div className="text-sm opacity-70 italic">No clips imported yet.</div>}
      <div className="space-y-2">
        {byPersona.map((row) => {
          const p = row.personaCode ? personaByCode.get(row.personaCode) : null;
          const pct = (row.count / totalForBars) * 100;
          return (
            <div key={row.personaCode ?? '(none)'} className="flex items-center gap-3">
              <div className="w-28 flex items-center gap-2">
                {p ? (
                  <>
                    <span
                      className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold"
                      style={{ background: p.primaryColor, color: p.textColor }}
                    >
                      {p.code}
                    </span>
                    <span className="text-xs">{p.name}</span>
                  </>
                ) : (
                  <span className="text-xs italic opacity-60">(unassigned)</span>
                )}
              </div>
              <div className="flex-1 h-3 rounded-full bg-black/5 overflow-hidden">
                <div
                  className="h-full rounded-full"
                  style={{ width: `${pct}%`, background: p?.primaryColor ?? '#A16D9C' }}
                />
              </div>
              <div className="w-12 text-right text-sm font-mono">{row.count}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function ReuseCard({
  reuse,
  personaByCode,
}: {
  reuse: ReuseGroup[];
  personaByCode: Map<string, PersonaRow>;
}) {
  return (
    <div className="pretty-card">
      <h3 className="display-font text-lg font-semibold persona-accent mb-2">Reuse detection</h3>
      <p className="text-xs opacity-60 mb-3">
        Possible duplicate posts: same external ID, or same title posted within ~2 weeks.
      </p>
      {reuse.length === 0 && <div className="text-sm opacity-70 italic">Looking good — nothing flagged.</div>}
      <div className="space-y-2">
        {reuse.slice(0, 8).map((g) => (
          <div key={`${g.reason}-${g.key}`} className="p-2 rounded-xl border border-amber-200 bg-amber-50/60">
            <div className="text-xs uppercase tracking-wider opacity-60">
              {g.reason === 'external_id' ? 'Same external ID' : 'Same title (within 14 days)'}
            </div>
            <div className="font-semibold text-sm">{g.key}</div>
            <div className="text-xs opacity-80 mt-1 space-y-0.5">
              {g.clips.map((c) => {
                const p = c.personaCode ? personaByCode.get(c.personaCode) : null;
                return (
                  <div key={c.id} className="flex items-center gap-2">
                    <span className="font-mono">{c.id}</span>
                    {p && (
                      <span
                        className="px-1.5 py-0 rounded text-[10px]"
                        style={{ background: p.primaryColor, color: p.textColor }}
                      >
                        {p.code}
                      </span>
                    )}
                    <span className="opacity-80">{c.goLiveDate ?? '—'}</span>
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function RecentImportsCard({ imports }: { imports: ClipImportLog[] }) {
  return (
    <div className="pretty-card">
      <h3 className="display-font text-lg font-semibold persona-accent mb-2">Recent imports</h3>
      {imports.length === 0 && (
        <div className="text-sm opacity-70 italic">
          No imports yet. Head to <strong>Clips → Import</strong>.
        </div>
      )}
      <div className="space-y-1.5">
        {imports.map((im) => (
          <div
            key={im.id}
            className="flex items-center justify-between text-sm p-2 rounded-xl border border-black/5"
          >
            <div>
              <div className="font-mono text-xs opacity-60">{im.importedAt}</div>
              <div>{im.sourceFile || '(file)'}</div>
            </div>
            <div className="text-xs text-right">
              <span className="font-semibold">{im.rowsInserted}</span> added ·{' '}
              <span className="font-semibold">{im.rowsUpdated}</span> updated
              {im.rowsSkipped > 0 && (
                <>
                  {' '}
                  · <span className="text-red-700">{im.rowsSkipped} skipped</span>
                </>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function Stat({ title, value, sub }: { title: string; value: number; sub: string }) {
  return (
    <div className="pretty-card">
      <div className="text-xs uppercase tracking-wider opacity-60">{title}</div>
      <div className="display-font text-3xl font-bold persona-accent mt-1">{value}</div>
      <div className="text-xs opacity-70 mt-1">{sub}</div>
    </div>
  );
}
