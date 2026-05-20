import { useEffect, useMemo, useState } from 'react';
import type { Persona } from '../../state/personas';
import { createPromo, updatePromo, type SocialPromo } from '../../data/socialPromos';
import type { SocialPlatform } from '../../data/socialPlatforms';
import type { Persona as PersonaRow } from '../../data/personas';
import { listClips, type Clip } from '../../data/clips';
import { RichTextNotes } from '../../components/RichTextNotes';

interface Props {
  initial: SocialPromo | null;
  active: Persona;
  platforms: SocialPlatform[];
  personas: PersonaRow[];
  onClose: () => void | Promise<void>;
}

function nowDateTimeLocal(): string {
  const d = new Date();
  const pad = (n: number) => n.toString().padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function isoFromInput(local: string): string {
  // local: "YYYY-MM-DDTHH:MM" → store as-is (interpreted as local time on read).
  return local && local.length >= 16 ? local + ':00' : local;
}

function inputFromIso(iso: string): string {
  if (!iso) return nowDateTimeLocal();
  // strip seconds if present
  return iso.length >= 16 ? iso.slice(0, 16) : iso;
}

const EMPTY = (personaCode: string | null, platformId: number): Omit<SocialPromo, 'id' | 'createdAt' | 'updatedAt'> => ({
  personaCode,
  platformId,
  handle: '',
  postedAt: nowDateTimeLocal() + ':00',
  url: '',
  title: '',
  body: '',
  clipId: null,
  notesHtml: '',
  archived: false,
});

export function PromoEditor({ initial, active, platforms, personas, onClose }: Props) {
  const defaultPersonaCode = initial?.personaCode ?? (active.code === 'ALL' ? null : active.code);
  const defaultPlatformId = initial?.platformId ?? platforms[0]?.id ?? 1;
  const [draft, setDraft] = useState<(Omit<SocialPromo, 'id' | 'createdAt' | 'updatedAt'> & { id?: number })>(
    initial
      ? { ...initial }
      : EMPTY(defaultPersonaCode, defaultPlatformId),
  );
  const [clips, setClips] = useState<Clip[]>([]);
  const [status, setStatus] = useState<string>('');
  const [dirty, setDirty] = useState(false);

  useEffect(() => {
    // Pull a recent slice of clips for the optional link. Tip: filtered by
    // persona if set; otherwise all.
    listClips({ personaCode: draft.personaCode ?? 'ALL', limit: 200 })
      .then(setClips)
      .catch((e) => setStatus(String(e)));
  }, [draft.personaCode]);

  function patch(p: Partial<typeof draft>) {
    setDraft((d) => ({ ...d, ...p }));
    setDirty(true);
  }

  async function save() {
    try {
      const payload = { ...draft, postedAt: isoFromInput(inputFromIso(draft.postedAt)) };
      if (draft.id) {
        await updatePromo({ ...payload, id: draft.id, createdAt: '', updatedAt: '' } as SocialPromo);
      } else {
        await createPromo(payload);
      }
      setStatus('Saved.');
      setDirty(false);
      await onClose();
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    }
  }

  const platformsById = useMemo(() => new Map(platforms.map((p) => [p.id, p])), [platforms]);
  const selectedPlatform = platformsById.get(draft.platformId);
  const selectedPersona = draft.personaCode ? personas.find((p) => p.code === draft.personaCode) : null;

  return (
    <div className="p-8 max-w-3xl space-y-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h2 className="display-font text-2xl font-bold persona-accent">
            {initial ? 'Edit promo' : 'New promo'}
          </h2>
          <div className="opacity-70 text-sm flex items-center gap-2 mt-1">
            {selectedPlatform && (
              <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-[11px] font-semibold" style={{ background: selectedPlatform.color, color: 'white' }}>
                <span>{selectedPlatform.icon}</span><span>{selectedPlatform.name}</span>
              </span>
            )}
            {selectedPersona && (
              <span className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold" style={{ background: selectedPersona.primaryColor, color: selectedPersona.textColor }}>
                {selectedPersona.code}
              </span>
            )}
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button type="button" className="pretty-button secondary" onClick={onClose}>← Back</button>
          <button type="button" className="pretty-button" onClick={save} disabled={!dirty}>
            {dirty ? '💾 Save' : 'Saved'}
          </button>
        </div>
      </div>

      <div className="pretty-card space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <label className="flex flex-col gap-1">
            <span className="text-xs uppercase tracking-wider opacity-60">Persona</span>
            <select className="pretty-input" value={draft.personaCode ?? ''} onChange={(e) => patch({ personaCode: e.target.value || null })}>
              <option value="">(unassigned)</option>
              {personas.map((p) => <option key={p.code} value={p.code}>{p.code} — {p.name}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-xs uppercase tracking-wider opacity-60">Platform</span>
            <select className="pretty-input" value={draft.platformId} onChange={(e) => patch({ platformId: Number(e.target.value) })}>
              {platforms.map((p) => <option key={p.id} value={p.id}>{p.icon} {p.name}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-xs uppercase tracking-wider opacity-60">Handle</span>
            <input className="pretty-input" placeholder="u/curseofcurves, @coc, …" value={draft.handle} onChange={(e) => patch({ handle: e.target.value })} />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-xs uppercase tracking-wider opacity-60">Posted at</span>
            <input
              type="datetime-local"
              className="pretty-input"
              value={inputFromIso(draft.postedAt)}
              onChange={(e) => patch({ postedAt: isoFromInput(e.target.value) })}
            />
          </label>
        </div>
        <label className="flex flex-col gap-1">
          <span className="text-xs uppercase tracking-wider opacity-60">URL</span>
          <input className="pretty-input" placeholder="https://…" value={draft.url} onChange={(e) => patch({ url: e.target.value })} />
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-xs uppercase tracking-wider opacity-60">Title</span>
          <input className="pretty-input" placeholder="Post title or short summary" value={draft.title} onChange={(e) => patch({ title: e.target.value })} />
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-xs uppercase tracking-wider opacity-60">Body / caption</span>
          <textarea className="pretty-input" rows={3} value={draft.body} onChange={(e) => patch({ body: e.target.value })} />
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-xs uppercase tracking-wider opacity-60">Linked clip (optional)</span>
          <select className="pretty-input" value={draft.clipId ?? ''} onChange={(e) => patch({ clipId: e.target.value || null })}>
            <option value="">(none)</option>
            {clips.map((c) => (
              <option key={c.id} value={c.id}>
                {c.id} — {c.title || '(untitled)'}{c.goLiveDate ? ` · ${c.goLiveDate}` : ''}
              </option>
            ))}
          </select>
        </label>
      </div>

      <div className="pretty-card">
        <div className="text-xs uppercase tracking-wider opacity-60 mb-2">Notes</div>
        <RichTextNotes
          value={draft.notesHtml}
          onChange={(html) => patch({ notesHtml: html })}
          placeholder="What hashtags worked, what time of day, what comments came in…"
        />
      </div>

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}
    </div>
  );
}
