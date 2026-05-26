import { usePromosEnabled } from '../../state/featureFlags';

export function FeaturesSettings() {
  const { enabled: promosEnabled, setEnabled: setPromosEnabled, loaded } = usePromosEnabled();

  return (
    <div className="space-y-3">
      <div className="pretty-card">
        <h3 className="display-font text-xl font-semibold persona-accent mb-1">🚩 Features</h3>
        <p className="text-sm opacity-70 mb-4">
          Switch parts of Molly on or off. Hiding a section makes it
          disappear from the sidebar — your data stays put and comes
          back the moment you flip it on again.
        </p>

        <FeatureRow
          icon="📣"
          label="Promos"
          hint="Reddit / X / Instagram promo posts. Off by default — switch on if Sallie's using cross-platform promo tracking."
          enabled={promosEnabled}
          disabled={!loaded}
          onToggle={(v) => void setPromosEnabled(v)}
        />
      </div>
    </div>
  );
}

interface FeatureRowProps {
  icon: string;
  label: string;
  hint: string;
  enabled: boolean;
  disabled?: boolean;
  onToggle: (next: boolean) => void;
}

function FeatureRow({ icon, label, hint, enabled, disabled, onToggle }: FeatureRowProps) {
  return (
    <div
      className="flex items-start gap-3 rounded-2xl p-4 transition border-2"
      style={{
        borderColor: enabled
          ? 'rgb(var(--persona-accent))'
          : 'rgb(var(--persona-primary) / 0.35)',
        background: enabled ? 'rgb(var(--persona-tint))' : 'rgb(var(--surface-card))',
      }}
    >
      <span className="text-2xl leading-none mt-0.5" aria-hidden>{icon}</span>
      <div className="flex-1 min-w-0">
        <div className="font-semibold">{label}</div>
        <div className="text-xs opacity-70 mt-1">{hint}</div>
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={enabled}
        disabled={disabled}
        onClick={() => onToggle(!enabled)}
        className="relative shrink-0 rounded-full transition"
        style={{
          width: 52,
          height: 28,
          background: enabled
            ? 'rgb(var(--persona-accent))'
            : 'rgb(var(--persona-primary) / 0.35)',
          opacity: disabled ? 0.4 : 1,
          cursor: disabled ? 'not-allowed' : 'pointer',
          boxShadow: enabled
            ? '0 4px 12px -6px rgb(var(--persona-accent) / 0.55)'
            : 'none',
        }}
        title={enabled ? `Turn ${label} off` : `Turn ${label} on`}
      >
        <span
          className="absolute top-1 rounded-full bg-white transition-all"
          style={{
            width: 20,
            height: 20,
            left: enabled ? 28 : 4,
            boxShadow: '0 1px 3px rgba(0,0,0,0.25)',
          }}
        />
      </button>
    </div>
  );
}
