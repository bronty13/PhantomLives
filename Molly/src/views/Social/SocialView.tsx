import { useEffect, useState } from 'react';
import type { Persona } from '../../state/personas';
import { listPlatforms, type SocialPlatform } from '../../data/socialPlatforms';
import { PiggyBank } from './PiggyBank';
import { PlatformTab } from './PlatformTab';
import { RedditView } from '../Reddit/RedditView';

interface Props {
  active: Persona;
}

type Section =
  | { kind: 'piggy' }
  | { kind: 'reddit' }                    // existing Reddit deep tools
  | { kind: 'platform'; platformId: number };

const REDDIT_PLATFORM_ID = 1;

export function SocialView({ active }: Props) {
  const [platforms, setPlatforms] = useState<SocialPlatform[]>([]);
  const [section, setSection] = useState<Section>({ kind: 'piggy' });

  useEffect(() => {
    let alive = true;
    listPlatforms()
      .then((p) => { if (alive) setPlatforms(p); })
      .catch(() => { if (alive) setPlatforms([]); });
    return () => { alive = false; };
  }, []);

  return (
    <div className="p-8 max-w-6xl space-y-4">
      <div>
        <h2 className="display-font text-2xl font-bold persona-accent">🪙 Social</h2>
        <p className="opacity-70 text-sm">
          Daily piggy-bank for every platform. Drop a coin each time you post; the streak grows
          when you hit every platform's goal for the day.
          {active.code !== 'ALL' && <> Filtered to <strong>{active.name}</strong>.</>}
        </p>
      </div>

      <div className="flex flex-wrap gap-1.5">
        <TabPill
          label="🪙 Piggy bank"
          active={section.kind === 'piggy'}
          onClick={() => setSection({ kind: 'piggy' })}
        />
        {platforms.map((p) => {
          // Reddit gets its own deep tab (existing tools). The piggy
          // bank still surfaces a Reddit row that drops generic coins.
          if (p.id === REDDIT_PLATFORM_ID) return null;
          const isActive = section.kind === 'platform' && section.platformId === p.id;
          return (
            <TabPill
              key={p.id}
              label={`${p.icon} ${p.name}`}
              active={isActive}
              onClick={() => setSection({ kind: 'platform', platformId: p.id })}
            />
          );
        })}
        <TabPill
          label="🔴 Reddit"
          active={section.kind === 'reddit'}
          onClick={() => setSection({ kind: 'reddit' })}
        />
      </div>

      <div>
        {section.kind === 'piggy'    && <PiggyBank active={active} />}
        {section.kind === 'platform' && (
          <PlatformTab active={active} platformId={section.platformId} />
        )}
        {section.kind === 'reddit'   && <RedditView active={active} embedded />}
      </div>
    </div>
  );
}

function TabPill({
  label, active, onClick,
}: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="px-3.5 py-1.5 rounded-full text-sm font-semibold transition"
      style={{
        background: active ? 'rgb(var(--persona-accent))' : 'rgba(255,255,255,0.55)',
        color: active ? 'white' : 'rgb(var(--persona-text))',
        border: '1px solid rgb(var(--persona-primary) / 0.45)',
        boxShadow: active ? '0 4px 12px -6px rgb(var(--persona-accent) / 0.55)' : undefined,
      }}
    >
      {label}
    </button>
  );
}
