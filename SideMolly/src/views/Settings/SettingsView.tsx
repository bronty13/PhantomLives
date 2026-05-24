import { useState } from 'react';
import { BackupSettings } from './BackupSettings';
import { WatchSettings } from './WatchSettings';

type SettingsTab = 'watch' | 'backup' | 'about';

const TABS: { key: SettingsTab; label: string; icon: string }[] = [
  { key: 'watch',  label: 'Watched folder', icon: '👀' },
  { key: 'backup', label: 'Backup',         icon: '💾' },
  { key: 'about',  label: 'About',          icon: 'ℹ️' },
];

// Phase 0 ships Backup (required per CLAUDE.md) and a placeholder About
// pane. Watermarks / Dropbox / Platforms / Watched-folder / Transcription
// / FFmpeg tabs land in Phases 3, 6, 7, and 4 respectively.
export function SettingsView() {
  const [tab, setTab] = useState<SettingsTab>('watch');
  return (
    <div className="p-8 max-w-4xl">
      <h1 className="display-font text-4xl mb-2" style={{ color: 'rgb(var(--surface-accent))' }}>
        Settings
      </h1>

      <div className="flex gap-2 mb-6 mt-4">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            onClick={() => setTab(t.key)}
            className="px-3 py-1.5 rounded-lg text-sm transition"
            style={{
              background: tab === t.key ? 'rgb(var(--surface-accent) / 0.12)' : 'rgb(var(--surface-card))',
              color: tab === t.key ? 'rgb(var(--surface-accent))' : 'rgb(var(--surface-text) / 0.78)',
              border: '1px solid rgb(var(--surface-border))',
              fontWeight: tab === t.key ? 600 : 500,
            }}
          >
            <span className="mr-1.5">{t.icon}</span>
            {t.label}
          </button>
        ))}
      </div>

      {tab === 'watch' && <WatchSettings />}
      {tab === 'backup' && <BackupSettings />}
      {tab === 'about' && (
        <div className="sm-card">
          <p className="text-sm">
            SideMolly is the outbound counterpart to Molly's bundler. See{' '}
            <code>SideMolly/PLAN.md</code> for the full 13-phase plan.
          </p>
        </div>
      )}
    </div>
  );
}
