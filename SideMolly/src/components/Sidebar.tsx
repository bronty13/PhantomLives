import { useEffect, useState, type ReactNode } from 'react';
import { getVersion } from '@tauri-apps/api/app';

// Phase 0 sidebar — Inbox / Settings / Manual only. Bundle workspace,
// runners (Content/Custom/FanSite), Jobs, etc. all land in later phases.
// Reuses Molly's HStack pattern (CLAUDE.md: NEVER NavigationSplitView).
export type ViewKey = 'inbox' | 'jobs' | 'settings' | 'manual';

interface SidebarProps {
  active: ViewKey;
  onSelect: (key: ViewKey) => void;
  visible: boolean;
}

interface NavItem {
  key: ViewKey;
  label: string;
  icon: ReactNode;
  hint?: string;
}

const NAV: NavItem[] = [
  { key: 'inbox',    label: 'Inbox',    icon: <span>📥</span>, hint: 'Ingested Molly bundles' },
  { key: 'jobs',     label: 'Jobs',     icon: <span>🛠</span>, hint: 'Background queue — video transcoding etc.' },
  { key: 'settings', label: 'Settings', icon: <span>⚙️</span>, hint: 'Backup, watched folder, watermarks, Dropbox, platforms' },
  { key: 'manual',   label: 'Manual',   icon: <span>💌</span>, hint: 'In-app guide' },
];

export function Sidebar({ active, onSelect, visible }: SidebarProps) {
  const [version, setVersion] = useState<string>('');
  useEffect(() => {
    getVersion().then(setVersion).catch(() => setVersion(''));
  }, []);
  if (!visible) return null;
  return (
    <aside
      className="flex flex-col"
      style={{
        width: 240,
        background: 'rgb(var(--surface-card))',
        borderRight: '1px solid rgb(var(--surface-border))',
      }}
    >
      <div className="px-5 pt-5 pb-3">
        <div className="display-font text-3xl" style={{ color: 'rgb(var(--surface-accent))' }}>
          SideMolly
        </div>
        <div className="text-[11px] mt-1" style={{ color: 'rgb(var(--surface-muted))' }}>
          Molly bundle workbench
        </div>
      </div>
      <nav className="flex-1 px-3 pb-4 overflow-y-auto">
        {NAV.map((item) => {
          const isActive = active === item.key;
          return (
            <button
              key={item.key}
              type="button"
              onClick={() => onSelect(item.key)}
              className="w-full text-left px-3 py-2 mb-1 rounded-xl flex items-center gap-3 transition"
              style={{
                background: isActive ? 'rgb(var(--surface-accent) / 0.12)' : 'transparent',
                color: isActive ? 'rgb(var(--surface-accent))' : 'rgb(var(--surface-text) / 0.82)',
                fontWeight: isActive ? 600 : 500,
              }}
              title={item.hint}
            >
              <span className="text-lg">{item.icon}</span>
              <span className="flex-1">{item.label}</span>
            </button>
          );
        })}
      </nav>
      <div
        className="px-5 py-3 text-[11px]"
        style={{
          color: 'rgb(var(--surface-muted))',
          borderTop: '1px solid rgb(var(--surface-border))',
        }}
      >
        SideMolly{version ? ` · v${version}` : ''}
      </div>
    </aside>
  );
}
