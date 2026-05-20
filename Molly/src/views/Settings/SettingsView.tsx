import { useState, type ReactNode } from 'react';
import type { Persona } from '../../state/personas';
import { BackupSettings } from './BackupSettings';
import { PersonasSettings } from './PersonasSettings';
import { SitesSettings } from './SitesSettings';
import { TaxonomySettings } from './TaxonomySettings';

type Tab = 'personas' | 'sites' | 'products' | 'interests' | 'backup';

interface Props {
  active: Persona;
  onPersonasChanged: () => void | Promise<void>;
}

const TABS: { key: Tab; label: string; icon: string }[] = [
  { key: 'personas',  label: 'Personas',  icon: '👯‍♀️' },
  { key: 'sites',     label: 'Sites',     icon: '💻' },
  { key: 'products',  label: 'Products',  icon: '📦' },
  { key: 'interests', label: 'Interests', icon: '🌷' },
  { key: 'backup',    label: 'Backup',    icon: '💾' },
];

export function SettingsView({ active, onPersonasChanged }: Props) {
  const [tab, setTab] = useState<Tab>('personas');

  let body: ReactNode = null;
  switch (tab) {
    case 'personas':  body = <PersonasSettings onChanged={onPersonasChanged} />; break;
    case 'sites':     body = <SitesSettings activePersona={active} />; break;
    case 'products':  body = <TaxonomySettings kind="products" />; break;
    case 'interests': body = <TaxonomySettings kind="interests" />; break;
    case 'backup':    body = <BackupSettings />; break;
  }

  return (
    <div className="p-8 space-y-4 max-w-4xl">
      <div>
        <h2 className="display-font text-2xl font-bold persona-accent">Settings</h2>
        <p className="opacity-70 text-sm">
          Configure everything that makes Molly yours.
        </p>
      </div>

      <div className="flex flex-wrap gap-1.5">
        {TABS.map((t) => {
          const isActive = tab === t.key;
          return (
            <button
              key={t.key}
              type="button"
              onClick={() => setTab(t.key)}
              className="px-3.5 py-1.5 rounded-full text-sm font-semibold transition"
              style={{
                background: isActive ? 'rgb(var(--persona-accent))' : 'rgba(255,255,255,0.55)',
                color: isActive ? 'white' : 'rgb(var(--persona-text))',
                border: '1px solid rgb(var(--persona-primary) / 0.45)',
                boxShadow: isActive ? '0 4px 12px -6px rgb(var(--persona-accent) / 0.55)' : undefined,
              }}
            >
              <span className="mr-1.5">{t.icon}</span>{t.label}
            </button>
          );
        })}
      </div>

      {body}
    </div>
  );
}
