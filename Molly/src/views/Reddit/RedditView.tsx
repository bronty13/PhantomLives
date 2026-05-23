import { useState } from 'react';
import type { Persona } from '../../state/personas';
import { TodaySection } from './TodaySection';
import { HoursSection } from './HoursSection';
import { SubredditsSection } from './SubredditsSection';
import { PostLogSection } from './PostLogSection';
import { CaptionsSection } from './CaptionsSection';

type Section = 'today' | 'hours' | 'subs' | 'posts' | 'captions';

const SECTIONS: { key: Section; label: string; icon: string }[] = [
  { key: 'today',    label: 'Today',      icon: '✅' },
  { key: 'subs',     label: 'Subreddits', icon: '📌' },
  { key: 'posts',    label: 'Post log',   icon: '📅' },
  { key: 'captions', label: 'Captions',   icon: '💬' },
  { key: 'hours',    label: 'Hours',      icon: '⏱' },
];

interface Props {
  active: Persona;
}

export function RedditView({ active }: Props) {
  const [section, setSection] = useState<Section>('today');

  return (
    <div className="p-8 max-w-6xl space-y-4">
      <div>
        <h2 className="display-font text-2xl font-bold persona-accent">🔴 Reddit</h2>
        <p className="opacity-70 text-sm">
          Daily ops hub — to-do list, subreddit tracker, post log, captions, and hours.
          {active.code !== 'ALL' && <> Filtered to <strong>{active.name}</strong>.</>}
        </p>
      </div>

      <div className="flex flex-wrap gap-1.5">
        {SECTIONS.map((s) => {
          const isActive = section === s.key;
          return (
            <button
              key={s.key}
              type="button"
              onClick={() => setSection(s.key)}
              className="px-3.5 py-1.5 rounded-full text-sm font-semibold transition"
              style={{
                background: isActive ? 'rgb(var(--persona-accent))' : 'rgba(255,255,255,0.55)',
                color: isActive ? 'white' : 'rgb(var(--persona-text))',
                border: '1px solid rgb(var(--persona-primary) / 0.45)',
                boxShadow: isActive ? '0 4px 12px -6px rgb(var(--persona-accent) / 0.55)' : undefined,
              }}
            >
              <span className="mr-1.5">{s.icon}</span>{s.label}
            </button>
          );
        })}
      </div>

      {section === 'today'    && <TodaySection active={active} />}
      {section === 'subs'     && <SubredditsSection active={active} />}
      {section === 'posts'    && <PostLogSection active={active} />}
      {section === 'captions' && <CaptionsSection active={active} />}
      {section === 'hours'    && <HoursSection />}
    </div>
  );
}
