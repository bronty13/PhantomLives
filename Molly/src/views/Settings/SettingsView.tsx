import { useState, type ReactNode } from 'react';
import type { Persona } from '../../state/personas';
import { BackupSettings } from './BackupSettings';
import { BundlerSettings } from './BundlerSettings';
import { C4SSettings } from './C4SSettings';
import { DataSettings } from './DataSettings';
import { SecuritySettings } from './SecuritySettings';
import { PersonasSettings } from './PersonasSettings';
import { PlatformsSettings } from './PlatformsSettings';
import { SitesSettings } from './SitesSettings';
import { TaxonomySettings } from './TaxonomySettings';
import { UpdatesSettings } from './UpdatesSettings';

type Tab = 'personas' | 'sites' | 'products' | 'interests' | 'kinks' | 'platforms' | 'c4s' | 'bundler' | 'security' | 'data' | 'updates' | 'backup';

interface Props {
  active: Persona;
  onPersonasChanged: () => void | Promise<void>;
}

const TABS: { key: Tab; label: string; icon: string }[] = [
  { key: 'personas',  label: 'Personas',   icon: '👯‍♀️' },
  { key: 'sites',     label: 'Sites',      icon: '💻' },
  { key: 'platforms', label: 'Platforms',  icon: '📣' },
  { key: 'products',  label: 'Products',   icon: '📦' },
  { key: 'interests', label: 'Interests',  icon: '🌷' },
  { key: 'kinks',     label: 'Kinks',      icon: '💕' },
  { key: 'c4s',       label: 'C4S',        icon: '🛍️' },
  { key: 'bundler',   label: 'Bundler',    icon: '🎁' },
  { key: 'security',  label: 'Security',   icon: '🔐' },
  { key: 'data',      label: 'Data',       icon: '📦' },
  { key: 'updates',   label: 'Updates',    icon: '⬇️' },
  { key: 'backup',    label: 'Backup',     icon: '💾' },
];

export function SettingsView({ active, onPersonasChanged }: Props) {
  const [tab, setTab] = useState<Tab>('personas');

  let body: ReactNode = null;
  switch (tab) {
    case 'personas':  body = <PersonasSettings onChanged={onPersonasChanged} />; break;
    case 'sites':     body = <SitesSettings activePersona={active} />; break;
    case 'platforms': body = <PlatformsSettings />; break;
    case 'products':  body = <TaxonomySettings kind="products" />; break;
    case 'interests': body = <TaxonomySettings kind="interests" />; break;
    case 'kinks':     body = <TaxonomySettings kind="kinks" />; break;
    case 'c4s':       body = <C4SSettings />; break;
    case 'bundler':   body = <BundlerSettings />; break;
    case 'security':  body = <SecuritySettings />; break;
    case 'data':      body = <DataSettings />; break;
    case 'updates':   body = <UpdatesSettings />; break;
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
