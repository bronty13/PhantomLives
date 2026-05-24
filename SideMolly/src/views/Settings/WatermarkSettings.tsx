import { useEffect, useState } from 'react';
import { getWatermarkProfiles, setWatermarkProfile,
         type WatermarkPosition, type WatermarkProfile } from '../../data/bundles';

const POSITIONS: WatermarkPosition[] = [
  'top-left', 'top-center', 'top-right',
  'middle-left', 'middle-center', 'middle-right',
  'bottom-left', 'bottom-center', 'bottom-right',
];

const PERSONA_LABEL: Record<string, string> = {
  '':    'Default (no persona)',
  CoC:   'Curse of Curves',
  PoA:   'Princess of Addiction',
  Sa:    'Sheer Attraction',
};

export function WatermarkSettings() {
  const [profiles, setProfiles] = useState<WatermarkProfile[]>([]);
  const [status, setStatus] = useState<string>('');
  const [busy, setBusy] = useState(false);

  const refresh = async () => {
    try {
      setProfiles(await getWatermarkProfiles());
    } catch (e) {
      setStatus(`Failed to load: ${e}`);
    }
  };

  useEffect(() => { refresh(); }, []);

  const updateOne = (idx: number, patch: Partial<WatermarkProfile>) => {
    setProfiles((arr) => arr.map((p, i) => (i === idx ? { ...p, ...patch } : p)));
  };

  const save = async (idx: number) => {
    setBusy(true);
    try {
      await setWatermarkProfile(profiles[idx]);
      setStatus(`Saved ${PERSONA_LABEL[profiles[idx].personaCode] ?? profiles[idx].personaCode}`);
    } catch (e) {
      setStatus(`Save failed: ${e}`);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="flex flex-col gap-4">
      <div className="sm-card">
        <div className="font-semibold mb-1">Watermark profiles</div>
        <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
          One profile per persona. Used by the Bundle workspace → Edit tab when
          you process images. Text is rendered in <em>Paper Daisy</em> at the
          configured opacity over the lower-right by default (matches the
          Phase 4.5 Auto-Assembly video burn-in spec).
        </div>
      </div>

      {profiles.map((p, idx) => (
        <div key={p.personaCode} className="sm-card flex flex-col gap-3">
          <div className="flex items-baseline justify-between">
            <div className="font-semibold">
              {PERSONA_LABEL[p.personaCode] ?? (p.personaCode || '(no persona)')}
              <span className="ml-2 text-xs font-normal" style={{ color: 'rgb(var(--surface-muted))' }}>
                {p.personaCode || '(default for null-persona bundles)'}
              </span>
            </div>
            <label className="flex items-center gap-2 text-xs cursor-pointer">
              <input
                type="checkbox"
                checked={p.enabled}
                onChange={(e) => updateOne(idx, { enabled: e.target.checked })}
              />
              Enabled
            </label>
          </div>

          <div className="grid grid-cols-[140px_1fr] gap-x-3 gap-y-2 text-sm items-center">
            <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Text</label>
            <input
              type="text"
              className="sm-input"
              value={p.text}
              onChange={(e) => updateOne(idx, { text: e.target.value })}
              placeholder="(blank disables watermark for this persona)"
            />

            <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Opacity</label>
            <div className="flex items-center gap-2">
              <input
                type="range"
                min={0}
                max={100}
                value={p.opacityPercent}
                onChange={(e) => updateOne(idx, { opacityPercent: Number(e.target.value) })}
                className="flex-1"
              />
              <span className="w-12 text-right font-mono text-xs">{p.opacityPercent}%</span>
            </div>

            <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Position</label>
            <PositionPicker value={p.position} onChange={(pos) => updateOne(idx, { position: pos })} />

            <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Font size</label>
            <div className="flex items-center gap-2">
              <input
                type="number"
                min={1}
                max={20}
                step={0.5}
                className="sm-input w-20"
                value={p.fontSizePct}
                onChange={(e) => updateOne(idx, { fontSizePct: Number(e.target.value) })}
              />
              <span className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
                % of image height
              </span>
            </div>

            <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Margin</label>
            <div className="flex items-center gap-2">
              <input
                type="number"
                min={0}
                max={20}
                step={0.5}
                className="sm-input w-20"
                value={p.marginPct}
                onChange={(e) => updateOne(idx, { marginPct: Number(e.target.value) })}
              />
              <span className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
                % of image height
              </span>
            </div>
          </div>

          <div className="flex justify-end">
            <button type="button" className="sm-button" disabled={busy} onClick={() => save(idx)}>
              💾 Save
            </button>
          </div>
        </div>
      ))}

      {status && (
        <div className="text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>{status}</div>
      )}
    </div>
  );
}

function PositionPicker({ value, onChange }: {
  value: WatermarkPosition; onChange: (p: WatermarkPosition) => void;
}) {
  return (
    <div className="inline-grid grid-cols-3 gap-1" style={{ width: 'fit-content' }}>
      {POSITIONS.map((pos) => {
        const active = pos === value;
        return (
          <button
            key={pos}
            type="button"
            onClick={() => onChange(pos)}
            title={pos}
            className="rounded transition"
            style={{
              width: 28, height: 28,
              background: active ? 'rgb(var(--surface-accent))' : 'rgb(var(--surface-card))',
              border: '1px solid rgb(var(--surface-border))',
              color: active ? 'white' : 'rgb(var(--surface-text))',
              fontSize: 11,
              fontWeight: active ? 700 : 400,
            }}
          >
            {posGlyph(pos)}
          </button>
        );
      })}
    </div>
  );
}

function posGlyph(pos: WatermarkPosition): string {
  switch (pos) {
    case 'top-left':      return '↖';
    case 'top-center':    return '↑';
    case 'top-right':     return '↗';
    case 'middle-left':   return '←';
    case 'middle-center': return '•';
    case 'middle-right':  return '→';
    case 'bottom-left':   return '↙';
    case 'bottom-center': return '↓';
    case 'bottom-right':  return '↘';
  }
}
