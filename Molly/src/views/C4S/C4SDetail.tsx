import type { C4SClip } from '../../data/c4sClips';

interface Props {
  clip: C4SClip;
  onBack: () => void;
}

function fmtMoneyCents(c: number | null | undefined): string {
  if (c == null) return '—';
  return `$${(c / 100).toFixed(2)}`;
}

const PERSONA_TINT: Record<string, { bg: string; fg: string; label: string }> = {
  CoC: { bg: '#FFC0CB', fg: '#5B2540', label: 'Curse Of Curves' },
  PoA: { bg: '#C8102E', fg: '#FFFFFF', label: 'Princess of Addiction' },
};

function Chips({ raw }: { raw: string }) {
  const parts = raw.split(',').map((s) => s.trim()).filter(Boolean);
  if (parts.length === 0) return <span className="opacity-60 italic">—</span>;
  return (
    <div className="flex flex-wrap gap-1.5">
      {parts.map((p) => (
        <span key={p} className="px-2 py-0.5 rounded-full text-[11px] font-semibold bg-black/[0.06]">
          {p}
        </span>
      ))}
    </div>
  );
}

export function C4SDetail({ clip, onBack }: Props) {
  const tint = PERSONA_TINT[clip.personaCode];
  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <button type="button" className="pretty-button secondary" onClick={onBack}>← Back</button>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <span
              className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold"
              style={{ background: tint?.bg ?? '#ddd', color: tint?.fg ?? '#222' }}
              title={tint?.label}
            >
              {clip.personaCode}
            </span>
            {clip.clipStatus && (
              <span className="px-2 py-0.5 rounded-full text-[11px] font-semibold bg-black/[0.06]">
                {clip.clipStatus}
              </span>
            )}
            <span className="font-mono text-xs opacity-60">#{clip.clipId}</span>
          </div>
          <h2 className="display-font text-2xl font-bold persona-accent">{clip.clipTitle || '(untitled)'}</h2>
        </div>
        <div className="flex gap-2">
          <button
            type="button"
            className="pretty-button secondary"
            onClick={() => navigator.clipboard?.writeText(clip.clipTitle).catch(() => {})}
            title="Copy title"
          >
            📋 Title
          </button>
          <button
            type="button"
            className="pretty-button secondary"
            onClick={() => navigator.clipboard?.writeText(clip.clipId).catch(() => {})}
            title="Copy clip ID"
          >
            📋 ID
          </button>
        </div>
      </div>

      <div className="pretty-card">
        <div className="text-xs uppercase tracking-wider opacity-60 mb-2">Description</div>
        {clip.clipDescription.trim() ? (
          <div
            className="whitespace-pre-wrap"
            style={{ fontFamily: '"Caveat", cursive', fontSize: '1.15rem', lineHeight: 1.4 }}
          >
            {clip.clipDescription}
          </div>
        ) : (
          <div className="text-sm opacity-60 italic">No description.</div>
        )}
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div className="pretty-card">
          <div className="text-xs uppercase tracking-wider opacity-60 mb-2">At a glance</div>
          <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
            <div>
              <dt className="text-[11px] uppercase tracking-wider opacity-60">Price</dt>
              <dd className="font-mono">{fmtMoneyCents(clip.priceCents)}</dd>
            </div>
            <div>
              <dt className="text-[11px] uppercase tracking-wider opacity-60">Sales #</dt>
              <dd className="font-mono">{clip.salesCount == null ? '—' : clip.salesCount.toLocaleString()}</dd>
            </div>
            <div>
              <dt className="text-[11px] uppercase tracking-wider opacity-60">Income (6mo)</dt>
              <dd className="font-mono">{fmtMoneyCents(clip.income6moCents)}</dd>
            </div>
            <div>
              <dt className="text-[11px] uppercase tracking-wider opacity-60">Performers</dt>
              <dd>{clip.performers || '—'}</dd>
            </div>
            <div className="col-span-2">
              <dt className="text-[11px] uppercase tracking-wider opacity-60">Tracking Tag</dt>
              <dd className="font-mono">{clip.clipTrackingTag || '—'}</dd>
            </div>
          </dl>
        </div>

        <div className="pretty-card">
          <div className="text-xs uppercase tracking-wider opacity-60 mb-2">Files</div>
          <dl className="space-y-2 text-sm">
            <div>
              <dt className="text-[11px] uppercase tracking-wider opacity-60">Clip filename</dt>
              <dd className="font-mono break-all">{clip.clipFilename || '—'}</dd>
            </div>
            <div>
              <dt className="text-[11px] uppercase tracking-wider opacity-60">Thumbnail</dt>
              <dd className="font-mono break-all">{clip.clipThumbnail || '—'}</dd>
            </div>
            <div>
              <dt className="text-[11px] uppercase tracking-wider opacity-60">Preview</dt>
              <dd className="font-mono break-all">{clip.clipPreview || '—'}</dd>
            </div>
          </dl>
        </div>
      </div>

      <div className="pretty-card">
        <div className="text-xs uppercase tracking-wider opacity-60 mb-2">Categories</div>
        <Chips raw={clip.categories} />
      </div>

      <div className="pretty-card">
        <div className="text-xs uppercase tracking-wider opacity-60 mb-2">Keywords</div>
        <Chips raw={clip.keywords} />
      </div>

      <div className="text-xs opacity-50 font-mono">imported {clip.importedAt}</div>
    </div>
  );
}
