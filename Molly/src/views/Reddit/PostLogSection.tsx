import { useEffect, useMemo, useState } from 'react';
import type { Persona } from '../../state/personas';
import {
  createSubredditPost,
  deleteSubredditPost,
  listSubredditPostsInRange,
  listSubreddits,
  type Subreddit,
  type SubredditPost,
} from '../../data/reddit';
import { listContentTags, type ContentTag } from '../../data/contentTags';
import { todayIso } from '../../data/dailyTasks';

interface Props {
  active: Persona;
}

export function PostLogSection({ active }: Props) {
  const [posts, setPosts] = useState<SubredditPost[]>([]);
  const [subs, setSubs] = useState<Subreddit[]>([]);
  const [tags, setTags] = useState<ContentTag[]>([]);
  // Form state for adding a post.
  const [draftName, setDraftName] = useState('');
  const [draftSubId, setDraftSubId] = useState<number | null>(null);
  const [draftDate, setDraftDate] = useState(todayIso());
  const [draftTagId, setDraftTagId] = useState<number | ''>('');
  const [draftNotes, setDraftNotes] = useState('');
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState('');

  const personaCode = active.code === 'ALL' ? null : active.code;

  async function refresh() {
    try {
      // Wide window: last 90 days → next 365 days. Covers backlog + future schedule.
      const today = new Date();
      const past = new Date(today); past.setDate(past.getDate() - 90);
      const future = new Date(today); future.setDate(future.getDate() + 365);
      const fmt = (d: Date) =>
        `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
      const [p, s, t] = await Promise.all([
        listSubredditPostsInRange(fmt(past), fmt(future), personaCode),
        listSubreddits(personaCode),
        listContentTags(),
      ]);
      setPosts(p);
      setSubs(s);
      setTags(t);
    } catch (e) {
      setStatus(String(e));
    }
  }

  useEffect(() => {
    refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active.code]);

  const tagById = useMemo(() => new Map(tags.map((t) => [t.id, t])), [tags]);
  const subByName = useMemo(() => new Map(subs.map((s) => [s.name.toLowerCase(), s])), [subs]);

  async function add() {
    const name = draftName.trim().replace(/^r\//i, '');
    if (!name) return;
    setBusy(true);
    try {
      // If the typed name matches a tracker sub, link it; otherwise log free-form.
      const matched = subByName.get(name.toLowerCase());
      await createSubredditPost({
        personaCode,
        subredditId: matched?.id ?? draftSubId,
        subredditName: name,
        tagId: draftTagId === '' ? matched?.tagId ?? null : draftTagId,
        postedDate: draftDate,
        notes: draftNotes.trim(),
      });
      setDraftName('');
      setDraftSubId(null);
      setDraftTagId('');
      setDraftNotes('');
      // Keep draftDate so logging a few posts for the same day is fast.
      await refresh();
      setStatus(`Logged r/${name} for ${draftDate}.`);
    } catch (e) {
      setStatus(String(e));
    } finally {
      setBusy(false);
    }
  }

  async function remove(p: SubredditPost) {
    if (!confirm(`Delete the log entry for r/${p.subredditName} on ${p.postedDate}?`)) return;
    try { await deleteSubredditPost(p.id); await refresh(); }
    catch (e) { setStatus(String(e)); }
  }

  // Bucket posts by day relationship: Future / Tomorrow / Today / Yesterday / Earlier.
  const today = todayIso();
  const tomorrow = (() => { const d = new Date(); d.setDate(d.getDate() + 1); return iso(d); })();
  const yesterday = (() => { const d = new Date(); d.setDate(d.getDate() - 1); return iso(d); })();

  const buckets: { key: string; label: string; items: SubredditPost[] }[] = [
    { key: 'future',    label: 'Scheduled (future)', items: [] },
    { key: 'tomorrow',  label: 'Tomorrow',           items: [] },
    { key: 'today',     label: 'Today',              items: [] },
    { key: 'yesterday', label: 'Yesterday',          items: [] },
    { key: 'earlier',   label: 'Earlier',            items: [] },
  ];
  for (const p of posts) {
    if (p.postedDate > tomorrow) buckets[0].items.push(p);
    else if (p.postedDate === tomorrow) buckets[1].items.push(p);
    else if (p.postedDate === today) buckets[2].items.push(p);
    else if (p.postedDate === yesterday) buckets[3].items.push(p);
    else buckets[4].items.push(p);
  }

  return (
    <div className="space-y-3">
      <div className="pretty-card">
        <h3 className="display-font text-xl font-semibold persona-accent mb-1">📅 Post log</h3>
        <p className="text-xs opacity-60 mb-3">
          Log a post for any date — yesterday, today, or scheduled in the future.
          Linking to a tracker sub flips its rotation to "Resting" and stamps the last-posted date.
        </p>
        <div className="grid grid-cols-[1fr_1fr_auto_auto] gap-2 mb-2">
          <input
            list="post-sub-autocomplete"
            className="pretty-input"
            placeholder="Subreddit name (without r/)…"
            value={draftName}
            onChange={(e) => {
              setDraftName(e.target.value);
              const matched = subByName.get(e.target.value.trim().toLowerCase());
              setDraftSubId(matched?.id ?? null);
            }}
            onKeyDown={(e) => { if (e.key === 'Enter') add(); }}
          />
          <datalist id="post-sub-autocomplete">
            {subs.map((s) => <option key={s.id} value={s.name} />)}
          </datalist>
          <input
            type="date"
            className="pretty-input"
            value={draftDate}
            onChange={(e) => setDraftDate(e.target.value)}
          />
          <select
            className="pretty-input"
            value={draftTagId}
            onChange={(e) => setDraftTagId(e.target.value === '' ? '' : Number(e.target.value))}
          >
            <option value="">Category (auto)</option>
            {tags.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
          </select>
          <button type="button" className="pretty-button" onClick={add} disabled={busy || !draftName.trim()}>
            + Log
          </button>
        </div>
        <input
          className="pretty-input w-full"
          placeholder="Notes (optional) — caption used, link, etc."
          value={draftNotes}
          onChange={(e) => setDraftNotes(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') add(); }}
        />
      </div>

      {buckets.every((b) => b.items.length === 0) ? (
        <div className="pretty-card text-sm opacity-60 italic">
          Nothing logged yet — log a past post, today's posts, or schedule something for tomorrow.
        </div>
      ) : (
        buckets.map((b) => b.items.length === 0 ? null : (
          <section key={b.key}>
            <div className="text-[10px] font-bold uppercase tracking-widest opacity-60 mb-1.5">
              {b.label} <span className="opacity-50">· {b.items.length}</span>
            </div>
            <ul className="space-y-1.5">
              {b.items.map((p) => {
                const tag = p.tagId ? tagById.get(p.tagId) : null;
                const isFuture = p.postedDate > today;
                return (
                  <li
                    key={p.id}
                    className="rounded-xl px-3 py-2 flex items-center gap-3 border"
                    style={{
                      background: isFuture ? 'rgba(255,255,255,0.6)' : 'rgb(var(--persona-tint))',
                      borderColor: isFuture ? 'rgb(var(--persona-primary) / 0.35)' : 'rgb(var(--persona-primary) / 0.25)',
                      borderStyle: isFuture ? 'dashed' : 'solid',
                    }}
                  >
                    <span className="font-mono text-xs opacity-70 w-24">{p.postedDate}</span>
                    <span className="font-semibold text-sm flex-1">r/{p.subredditName}</span>
                    {tag && (
                      <span
                        className="px-2 py-0.5 rounded-full text-[10px] font-semibold whitespace-nowrap"
                        style={{ background: tag.color, color: idealTextColor(tag.color) }}
                      >
                        {tag.name}
                      </span>
                    )}
                    {p.notes && (
                      <span className="text-xs opacity-70 italic truncate max-w-[200px]" title={p.notes}>{p.notes}</span>
                    )}
                    <button
                      type="button"
                      className="text-base opacity-50 hover:opacity-100 hover:text-red-600 px-1"
                      onClick={() => remove(p)}
                      title="Delete entry"
                    >
                      ✕
                    </button>
                  </li>
                );
              })}
            </ul>
          </section>
        ))
      )}

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}

function iso(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function idealTextColor(hex: string): string {
  const h = hex.replace('#', '');
  if (h.length !== 6) return '#1F2937';
  const r = parseInt(h.slice(0, 2), 16);
  const g = parseInt(h.slice(2, 4), 16);
  const b = parseInt(h.slice(4, 6), 16);
  const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return lum > 160 ? '#1F2937' : '#FFFFFF';
}
