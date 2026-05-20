import { ALL_PERSONAS, type Persona } from '../state/personas';

interface Props {
  personas: Persona[];
  active: Persona;
  onChoose: (p: Persona) => void;
  onToggleSidebar: () => void;
}

export function PersonaSwitcher({ personas, active, onChoose, onToggleSidebar }: Props) {
  const items: Persona[] = [...personas, ALL_PERSONAS];
  return (
    <header
      className="h-16 flex items-center justify-between px-4 sticky top-0 z-10"
      style={{
        background: 'rgb(var(--persona-tint) / 0.85)',
        borderBottom: '1px solid rgb(var(--persona-primary) / 0.45)',
        backdropFilter: 'blur(14px)',
      }}
    >
      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={onToggleSidebar}
          className="rounded-xl px-2.5 py-1.5 hover:bg-white/40 transition"
          title="Toggle sidebar (Ctrl/Cmd + S)"
        >
          ☰
        </button>
        <div>
          <div className="text-xs uppercase tracking-wider opacity-60">Active persona</div>
          <div className="display-font text-lg font-semibold persona-accent leading-tight">{active.name}</div>
        </div>
      </div>
      <div className="flex items-center gap-1.5">
        {items.map((p) => {
          const isActive = p.code === active.code;
          return (
            <button
              key={p.code}
              type="button"
              onClick={() => onChoose(p)}
              className="px-3.5 py-1.5 rounded-full text-sm font-semibold transition"
              style={{
                background: isActive ? p.primaryColor : 'rgba(255,255,255,0.55)',
                color: isActive ? p.textColor : 'rgb(var(--persona-text) / 0.78)',
                border: `1px solid ${isActive ? p.accentColor : 'rgb(var(--persona-primary) / 0.4)'}`,
                boxShadow: isActive ? `0 6px 14px -6px ${p.accentColor}88` : undefined,
              }}
              title={p.description}
            >
              {p.code === 'ALL' ? '★ All' : p.code}
            </button>
          );
        })}
      </div>
    </header>
  );
}
