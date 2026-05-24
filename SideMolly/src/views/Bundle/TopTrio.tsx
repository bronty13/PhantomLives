import type { DocKind } from './DocDrawer';

interface Props {
  onOpen: (kind: DocKind) => void;
  hasManifestJsonInBundle: boolean;
}

interface Entry {
  kind: DocKind;
  label: string;
  glyph: string;
  hint: string;
}

const ENTRIES: Entry[] = [
  { kind: 'manifest', label: 'Manifest',  glyph: '🗂', hint: 'Parsed bundle manifest' },
  { kind: 'log',      label: 'Molly.log', glyph: '📜', hint: 'Molly\'s build log (every wizard input + per-file SHA)' },
  { kind: 'info',     label: 'info.md',   glyph: '📄', hint: 'Human-readable summary' },
];

export function TopTrio({ onOpen, hasManifestJsonInBundle }: Props) {
  return (
    <section className="sm-card flex flex-wrap gap-2">
      {ENTRIES.map((e) => (
        <button
          key={e.kind}
          type="button"
          onClick={() => onOpen(e.kind)}
          title={e.hint}
          className="flex-1 min-w-[160px] text-left flex items-center gap-3 px-3 py-2.5 rounded-lg transition"
          style={{
            background: 'rgb(var(--surface-base))',
            border: '1px solid rgb(var(--surface-border))',
          }}
        >
          <span className="text-2xl">{e.glyph}</span>
          <span className="flex-1 min-w-0">
            <div className="font-semibold text-sm">{e.label}</div>
            <div className="text-[11px]" style={{ color: 'rgb(var(--surface-muted))' }}>
              {e.kind === 'manifest' && !hasManifestJsonInBundle
                ? '(parsed from Molly.log)'
                : e.hint}
            </div>
          </span>
        </button>
      ))}
    </section>
  );
}
