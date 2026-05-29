import { useEffect, useState, type ReactNode } from 'react';
import { getVersion } from '@tauri-apps/api/app';
import { SayingsBanner } from './SayingsBanner';

export type ViewKey = 'home' | 'log' | 'notes' | 'reminders' | 'calendar' | 'clips' | 'c4s' | 'bundles' | 'jobs' | 'customers' | 'helper' | 'promos' | 'social' | 'income' | 'expenses' | 'reports' | 'settings' | 'manual';

interface SidebarProps {
  active: ViewKey;
  onSelect: (key: ViewKey) => void;
  visible: boolean;
  pendingCount?: number;     // overdue + today; shows red badge on Reminders
  /** Feature flag — when false the Promos nav entry is hidden. */
  promosEnabled?: boolean;
}

interface NavItem {
  key: ViewKey;
  label: string;
  icon: ReactNode;
  hint?: string;
}

const NAV: NavItem[] = [
  { key: 'home',      label: 'Home',      icon: <span>🏠</span>, hint: "Today's reminders + dashboards" },
  { key: 'log',       label: "Molly's Log", icon: <span>📔</span>, hint: 'Personal journal — notes to self with optional attachments' },
  { key: 'notes',     label: 'Notes',     icon: <span>📝</span>, hint: 'Folders + tagged notes + WYSIWYG editor + attachments' },
  { key: 'reminders', label: 'Reminders', icon: <span>🔔</span>, hint: 'Today, overdue, coming up' },
  { key: 'calendar',  label: 'Calendar',  icon: <span>📅</span>, hint: 'Clip releases + schedule overlay' },
  { key: 'clips',     label: 'Clips',     icon: <span>🎬</span>, hint: 'Imported from MasterClipper' },
  { key: 'c4s',       label: 'C4S Store', icon: <span>🛍️</span>, hint: 'Live Clips4Sale catalog snapshot' },
  { key: 'bundles',   label: 'Bundles',   icon: <span>🎁</span>, hint: 'Compose delivery bundles for Robert' },
  { key: 'jobs',      label: 'Jobs',      icon: <span>🌀</span>, hint: 'Background tasks (ATW Repost + future)' },
  { key: 'customers', label: 'Customers', icon: <span>👯‍♀️</span>, hint: 'Customer tracker' },
  { key: 'helper',    label: "Molly Helper", icon: <span>💅</span>, hint: 'Site launcher + reminders' },
  { key: 'promos',    label: 'Promos',    icon: <span>📣</span>, hint: 'Reddit / X / Instagram promo posts' },
  { key: 'social',    label: 'Social',    icon: <span>🪙</span>, hint: 'Piggy bank · daily post goals · streaks · Reddit deep tools' },
  { key: 'income',    label: 'Income',    icon: <span>💖</span>, hint: 'Adhoc + per-site' },
  { key: 'expenses',  label: 'Expenses',  icon: <span>🧾</span>, hint: 'One-off + recurring' },
  { key: 'reports',   label: 'Reports',   icon: <span>📊</span>, hint: 'MTD / YTD / per persona' },
  { key: 'settings',  label: 'Settings',  icon: <span>⚙️</span>, hint: 'Personas, sites, backup' },
  { key: 'manual',    label: 'Manual',    icon: <span>💌</span>, hint: 'Sallie’s in-app user guide' },
];

export function Sidebar({ active, onSelect, visible, pendingCount = 0, promosEnabled = true }: SidebarProps) {
  const [version, setVersion] = useState<string>('');
  useEffect(() => {
    getVersion().then(setVersion).catch(() => setVersion(''));
  }, []);
  if (!visible) return null;
  const items = NAV.filter((item) => (item.key === 'promos' ? promosEnabled : true));
  return (
    <aside
      className="flex flex-col"
      style={{
        width: 240,
        background: 'rgb(var(--persona-secondary) / 0.65)',
        borderRight: '1px solid rgb(var(--persona-primary) / 0.4)',
        backdropFilter: 'blur(12px)',
      }}
    >
      <div className="px-5 pt-5 pb-3">
        <div className="display-font text-2xl font-semibold persona-accent">Molly</div>
        <div className="mt-1.5">
          <SayingsBanner variant="compact" />
        </div>
      </div>
      <nav className="flex-1 px-3 pb-4 overflow-y-auto">
        {items.map((item) => {
          const isActive = active === item.key;
          return (
            <button
              key={item.key}
              type="button"
              onClick={() => onSelect(item.key)}
              className="w-full text-left px-3 py-2 mb-1 rounded-2xl flex items-center gap-3 transition"
              style={{
                background: isActive ? 'rgb(var(--persona-primary) / 0.7)' : 'transparent',
                color: isActive ? 'rgb(var(--persona-text))' : 'rgb(var(--persona-text) / 0.78)',
                fontWeight: isActive ? 600 : 500,
                boxShadow: isActive ? '0 4px 12px -6px rgb(var(--persona-accent) / 0.4)' : undefined,
              }}
              title={item.hint}
            >
              <span className="text-lg">{item.icon}</span>
              <span className="flex-1">{item.label}</span>
              {item.key === 'reminders' && pendingCount > 0 && (
                <span
                  className="text-[11px] font-semibold rounded-full px-1.5 py-0.5"
                  style={{ background: '#E5527A', color: 'white', minWidth: 22, textAlign: 'center' }}
                >
                  {pendingCount > 99 ? '99+' : pendingCount}
                </span>
              )}
            </button>
          );
        })}
      </nav>
      <div className="px-5 py-3 text-[11px] opacity-50 border-t border-white/40">
        Molly{version ? ` · v${version}` : ''}
      </div>
    </aside>
  );
}
