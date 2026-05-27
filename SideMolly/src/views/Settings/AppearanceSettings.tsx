// Settings → Appearance. Pick the theme: Dark (default), Light, or
// Auto (follow the system appearance). Persists to localStorage via
// the theme module and applies live.

import { useEffect, useState } from 'react';
import { getTheme, setTheme, type Theme } from '../../lib/theme';

const OPTIONS: { value: Theme; label: string; icon: string; desc: string }[] = [
  { value: 'dark',  label: 'Dark',  icon: '🌙', desc: 'Always dark (default).' },
  { value: 'light', label: 'Light', icon: '☀️', desc: 'Always light.' },
  { value: 'auto',  label: 'Auto',  icon: '🖥', desc: 'Follow the system appearance.' },
];

export function AppearanceSettings() {
  const [theme, setLocal] = useState<Theme>(getTheme());
  const [systemDark, setSystemDark] = useState(false);

  useEffect(() => {
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const update = () => setSystemDark(mq.matches);
    update();
    mq.addEventListener('change', update);
    return () => mq.removeEventListener('change', update);
  }, []);

  const choose = (t: Theme) => { setLocal(t); setTheme(t); };

  const resolved = theme === 'auto' ? (systemDark ? 'Dark' : 'Light')
                                    : (theme === 'dark' ? 'Dark' : 'Light');

  return (
    <div className="flex flex-col gap-4">
      <div className="sm-card">
        <div className="font-semibold mb-1">Appearance</div>
        <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
          Choose SideMolly's theme. <strong>Auto</strong> follows your
          macOS Light/Dark setting and updates live.
        </div>
      </div>

      <div className="sm-card flex flex-col gap-3">
        <div className="grid grid-cols-3 gap-2">
          {OPTIONS.map((o) => {
            const active = theme === o.value;
            return (
              <button
                key={o.value}
                type="button"
                onClick={() => choose(o.value)}
                className="rounded-lg p-3 text-left transition flex flex-col gap-1"
                style={{
                  border: active ? '2px solid rgb(var(--surface-accent))' : '1px solid rgb(var(--surface-border))',
                  background: active ? 'rgb(var(--surface-accent) / 0.12)' : 'rgb(var(--surface-card))',
                }}
              >
                <div className="flex items-center gap-2 font-semibold text-sm">
                  <span style={{ fontSize: 18 }}>{o.icon}</span>
                  {o.label}
                  {active && <span className="ml-auto" style={{ color: 'rgb(var(--surface-accent))' }}>✓</span>}
                </div>
                <div className="text-[11px]" style={{ color: 'rgb(var(--surface-muted))' }}>{o.desc}</div>
              </button>
            );
          })}
        </div>

        {theme === 'auto' && (
          <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
            System is currently <strong>{resolved}</strong>.
          </div>
        )}
      </div>
    </div>
  );
}
