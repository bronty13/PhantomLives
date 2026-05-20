import { useEffect, useState, type ReactNode } from 'react';
import { getVersion } from '@tauri-apps/api/app';

export type ViewKey = 'home' | 'reminders' | 'calendar' | 'clips' | 'customers' | 'helper' | 'promos' | 'income' | 'expenses' | 'reports' | 'settings';

interface SidebarProps {
  active: ViewKey;
  onSelect: (key: ViewKey) => void;
  visible: boolean;
  pendingCount?: number;     // overdue + today; shows red badge on Reminders
}

interface NavItem {
  key: ViewKey;
  label: string;
  icon: ReactNode;
  hint?: string;
}

const NAV: NavItem[] = [
  { key: 'home',      label: 'Home',      icon: <span>🏠</span>, hint: "Today's reminders + dashboards" },
  { key: 'reminders', label: 'Reminders', icon: <span>🔔</span>, hint: 'Today, overdue, coming up' },
  { key: 'calendar',  label: 'Calendar',  icon: <span>📅</span>, hint: 'Clip releases + schedule overlay' },
  { key: 'clips',     label: 'Clips',     icon: <span>🎬</span>, hint: 'Imported from MasterClipper' },
  { key: 'customers', label: 'Customers', icon: <span>👯‍♀️</span>, hint: 'Customer tracker' },
  { key: 'helper',    label: "Molly Helper", icon: <span>💅</span>, hint: 'Site launcher + reminders' },
  { key: 'promos',    label: 'Promos',    icon: <span>📣</span>, hint: 'Reddit / X / Instagram promo posts' },
  { key: 'income',    label: 'Income',    icon: <span>💖</span>, hint: 'Adhoc + per-site' },
  { key: 'expenses',  label: 'Expenses',  icon: <span>🧾</span>, hint: 'One-off + recurring' },
  { key: 'reports',   label: 'Reports',   icon: <span>📊</span>, hint: 'MTD / YTD / per persona' },
  { key: 'settings',  label: 'Settings',  icon: <span>⚙️</span>, hint: 'Personas, sites, backup' },
];

export function Sidebar({ active, onSelect, visible, pendingCount = 0 }: SidebarProps) {
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
        background: 'rgb(var(--persona-secondary) / 0.65)',
        borderRight: '1px solid rgb(var(--persona-primary) / 0.4)',
        backdropFilter: 'blur(12px)',
      }}
    >
      <div className="px-5 pt-5 pb-3">
        <div className="display-font text-2xl font-semibold persona-accent">Molly</div>
        <div className="text-xs opacity-60 mt-1">your work, your way 💕</div>
      </div>
      <nav className="flex-1 px-3 pb-4 overflow-y-auto">
        {NAV.map((item) => {
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
