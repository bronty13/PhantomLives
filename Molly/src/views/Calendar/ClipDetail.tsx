import { useEffect, useState } from 'react';
import { getClip, updateClipNotes, deleteClip, type Clip } from '../../data/clips';
import type { Persona as PersonaRow } from '../../data/personas';
import {
  listClipTags,
  listContentTags,
  setClipTags,
  type ContentTag,
} from '../../data/contentTags';
import { ContentTagPicker } from '../Bundles/components/ContentTagPicker';
import { RichTextNotes } from '../../components/RichTextNotes';
import { ConfirmButton } from '../../components/ConfirmButton';

interface Props {
  clipId: string;
  personas: PersonaRow[];
  onClose: () => void | Promise<void>;
}

export function ClipDetail({ clipId, personas, onClose }: Props) {
  const [clip, setClip] = useState<Clip | null>(null);
  const [notes, setNotes] = useState('');
  const [dirty, setDirty] = useState(false);
  const [status, setStatus] = useState('');
  const [contentTags, setContentTags] = useState<ContentTag[]>([]);
  const [selectedTagIds, setSelectedTagIds] = useState<number[]>([]);

  useEffect(() => {
    let alive = true;
    Promise.all([getClip(clipId), listContentTags(), listClipTags(clipId)])
      .then(([c, t, ids]) => {
        if (!alive) return;
        setClip(c);
        setNotes(c?.mollyNotesHtml ?? '');
        setContentTags(t);
        setSelectedTagIds(ids);
        setDirty(false);
      })
      .catch((e) => alive && setStatus(String(e)));
    return () => { alive = false; };
  }, [clipId]);

  async function onTagsChange(next: number[]) {
    setSelectedTagIds(next);
    try {
      await setClipTags(clipId, next);
    } catch (e) {
      setStatus(`Couldn't save tags: ${String(e)}`);
    }
  }

  async function save() {
    if (!clip) return;
    try {
      await updateClipNotes(clip.id, notes);
      setStatus('Saved.');
      setDirty(false);
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    }
  }

  async function removeAndClose() {
    if (!clip) return;
    try {
      await deleteClip(clip.id);
      await onClose();
    } catch (e) {
      setStatus(`Couldn't delete: ${String(e)}`);
    }
  }

  if (!clip) return null;

  const persona = clip.personaCode ? personas.find((p) => p.code === clip.personaCode) : null;

  return (
    <div className="fixed inset-0 z-30 flex items-center justify-center bg-black/30 backdrop-blur-sm p-4" onClick={onClose}>
      <div
        className="bg-white rounded-3xl max-w-2xl w-full max-h-[90vh] overflow-y-auto p-6 shadow-2xl"
        style={{ borderTop: `8px solid ${persona?.primaryColor ?? '#A16D9C'}` }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between gap-3">
          <div>
            <div className="text-xs font-mono opacity-60">{clip.id}</div>
            <h3 className="display-font text-xl font-bold persona-accent mt-0.5">{clip.title || '(untitled)'}</h3>
            <div className="flex items-center gap-2 mt-1">
              {persona && (
                <span className="px-2 py-0.5 rounded-md text-xs font-semibold" style={{ background: persona.primaryColor, color: persona.textColor }}>
                  {persona.code}
                </span>
              )}
              {clip.status && <span className="text-xs opacity-70">{clip.status}</span>}
              {clip.length && <span className="text-xs opacity-70 font-mono">{clip.length}</span>}
            </div>
          </div>
          <button type="button" className="pretty-button secondary" onClick={onClose}>Close</button>
        </div>

        <dl className="mt-4 grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
          {[
            ['Go-live',       clip.goLiveDate ?? '—'],
            ['Content date',  clip.contentDate ?? '—'],
            ['Price',         clip.price || '—'],
            ['Categories',    clip.categories || '—'],
            ['Imported',      clip.importedAt],
          ].map(([k, v]) => (
            <div key={k}>
              <dt className="text-[11px] uppercase tracking-wider opacity-60">{k}</dt>
              <dd className="font-mono">{v}</dd>
            </div>
          ))}
        </dl>

        {clip.notes && (
          <div className="mt-4">
            <div className="text-xs uppercase tracking-wider opacity-60 mb-1">MasterClipper notes</div>
            <div className="text-sm whitespace-pre-wrap p-3 rounded-xl border border-black/5 bg-white">{clip.notes}</div>
          </div>
        )}

        <div className="mt-4">
          <ContentTagPicker
            tags={contentTags}
            selected={selectedTagIds}
            onChange={onTagsChange}
          />
        </div>

        <div className="mt-4">
          <div className="text-xs uppercase tracking-wider opacity-60 mb-1">Molly notes (preserved across re-imports)</div>
          <RichTextNotes
            value={notes}
            onChange={(html) => { setNotes(html); setDirty(true); }}
            placeholder="What worked, what didn't, who liked it…"
          />
        </div>

        <div className="mt-4 flex items-center justify-end gap-2">
          <ConfirmButton label="Delete clip" confirmLabel="Confirm?" onConfirm={removeAndClose} />
          <button type="button" className="pretty-button" onClick={save} disabled={!dirty}>
            {dirty ? '💾 Save notes' : 'Saved'}
          </button>
        </div>
        {status && <div className="text-xs opacity-70 mt-2">{status}</div>}
      </div>
    </div>
  );
}
