import { useUiTheme, type ThemeMode } from '../../state/uiTheme';

const OPTIONS: { mode: ThemeMode; label: string; icon: string; hint: string }[] = [
  { mode: 'light',  label: 'Light',  icon: '☀️', hint: 'Always cute and bright (default).' },
  { mode: 'dark',   label: 'Dark',   icon: '🌙', hint: 'Easy on late-night editing eyes.' },
  { mode: 'system', label: 'System', icon: '🖥️', hint: 'Follow the OS appearance setting.' },
];

export function AppearanceSettings() {
  const { mode, setMode } = useUiTheme();

  return (
    <div className="space-y-3">
      <div className="pretty-card">
        <h3 className="display-font text-xl font-semibold persona-accent mb-1">🎨 Appearance</h3>
        <p className="text-sm opacity-70 mb-4">
          Pick the theme. Persona colors stay the same — only the page,
          cards, and inputs flip darker.
        </p>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
          {OPTIONS.map((o) => {
            const isActive = mode === o.mode;
            return (
              <button
                key={o.mode}
                type="button"
                onClick={() => setMode(o.mode)}
                className="text-left rounded-2xl p-4 transition border-2"
                style={{
                  borderColor: isActive ? 'rgb(var(--persona-accent))' : 'rgb(var(--persona-primary) / 0.35)',
                  background: isActive ? 'rgb(var(--persona-tint))' : 'rgb(var(--surface-card))',
                  boxShadow: isActive ? '0 4px 12px -6px rgb(var(--persona-accent) / 0.55)' : 'none',
                }}
              >
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-2xl">{o.icon}</span>
                  <span className="font-semibold">{o.label}</span>
                  {isActive && <span className="ml-auto text-xs persona-accent font-semibold">✓ Active</span>}
                </div>
                <div className="text-xs opacity-70">{o.hint}</div>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}
