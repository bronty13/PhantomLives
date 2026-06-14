import { useCallback, useEffect, useState } from 'react';
import { BundleSummaryReport } from '../../components/BundleSummaryReport';
import { db } from '../../data/db';
import {
  type Bundle,
  type BundleFileInfo,
  deleteBundleDraft,
  deleteBundleFile,
  getBundle,
  listProhibitedWords,
  reorderBundleFiles,
  saveBundleFile,
  updateBundleFields,
} from '../../data/bundles';
import { listPersonas, type Persona } from '../../data/personas';
import { listContentTags, setBundleTags, type ContentTag } from '../../data/contentTags';
import { ContentTagPicker } from './components/ContentTagPicker';
import { DescriptionField } from './components/DescriptionField';
import { GoLiveDatePicker } from './components/GoLiveDatePicker';
import { OrderedFileList } from './components/OrderedFileList';
import { PreviewAssetField } from './components/PreviewAssetField';
import { SpecialInstructionsField } from './components/SpecialInstructionsField';
import { TitleField } from './components/TitleField';
import { FrameGrabber } from '../GifStudio/FrameGrabber';

interface Props {
  uid: string;
  onPublishRequested: () => void;
  onClose: () => void;                    // back to bundles list (also refreshes parent list)
  onDeleted?: () => void;                  // fires after a successful draft delete
  onUnlock?: () => void;                   // unpublish + reopen for editing (only set when locked)
  locked?: boolean;          // published bundles render read-only until ZIP deleted
}

/** YouTube bundle editor. Mirrors the Content bundle (title + persona +
 *  text/audio description + go-live + special instructions + content tags)
 *  but drops categories and locks the file list to video clips only. */
export function YouTubeBundleForm({ uid, onPublishRequested, onClose, onDeleted, onUnlock, locked }: Props) {
  const [bundle, setBundle] = useState<Bundle | null>(null);
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [prohibited, setProhibited] = useState<string[]>([]);
  const [contentTags, setContentTags] = useState<ContentTag[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [frameOpen, setFrameOpen] = useState(false);

  // reload depends only on `uid` — see the ContentBundleForm note about the
  // infinite-reload trap if a parent callback sneaks into the dep list.
  const reload = useCallback(async () => {
    const b = await getBundle(uid);
    setBundle(b);
  }, [uid]);

  useEffect(() => {
    let alive = true;
    Promise.all([reload(), listPersonas(), listProhibitedWords(), listContentTags()])
      .then(([_, p, pw, tags]) => {
        if (!alive) return;
        setPersonas(p);
        setProhibited(pw);
        setContentTags(tags);
      })
      .catch((e) => alive && setError(String(e)));
    return () => { alive = false; };
  }, [reload]);

  async function onTagsChange(next: number[]) {
    await withBusy(async () => { await setBundleTags(uid, next); await reload(); });
  }

  async function withBusy<T>(fn: () => Promise<T>): Promise<T | null> {
    setBusy(true); setError(null);
    try { return await fn(); }
    catch (e) { setError(stringifyError(e)); return null; }
    finally { setBusy(false); }
  }

  async function setPersona(code: string | null) {
    await withBusy(async () => {
      const conn = await db();
      await conn.execute('UPDATE bundles SET persona_code = $1, updated_at = datetime(\'now\') WHERE uid = $2', [code, uid]);
      await reload();
    });
  }

  async function commitTitle(s: string) {
    await withBusy(async () => { await updateBundleFields(uid, { title: s }); await reload(); });
  }
  async function commitGoLive(s: string | null) {
    await withBusy(async () => { await updateBundleFields(uid, { goLiveDate: s }); await reload(); });
  }
  async function commitSpecial(s: string) {
    await withBusy(async () => { await updateBundleFields(uid, { specialInstructions: s }); await reload(); });
  }
  async function commitMakePrivate(v: boolean) {
    await withBusy(async () => {
      // Turning private ON clears any go-live date — a private video goes live
      // when Sallie publishes it, so the date is meaningless (and the picker
      // disappears). Done in one patch so the row never lands half-updated.
      await updateBundleFields(uid, v ? { makePrivate: true, goLiveDate: null } : { makePrivate: false });
      await reload();
    });
  }
  async function commitAlsoPostManyvids(v: boolean) {
    await withBusy(async () => { await updateBundleFields(uid, { alsoPostSfwManyvids: v }); await reload(); });
  }
  async function commitDescriptionMode(mode: 'audio' | 'text' | null) {
    await withBusy(async () => { await updateBundleFields(uid, { descriptionMode: mode }); await reload(); });
  }
  async function commitDescriptionText(s: string) {
    await withBusy(async () => { await updateBundleFields(uid, { descriptionText: s }); await reload(); });
  }
  async function onAudioSaved(info: BundleFileInfo) {
    // Lift the saved file off bundle_files and onto bundles.description_audio_*.
    await withBusy(async () => {
      const conn = await db();
      await conn.execute(
        `UPDATE bundles SET description_audio_relpath = $1, description_audio_sha256 = $2,
                            description_mode = 'audio', updated_at = datetime('now')
         WHERE uid = $3`,
        [info.relpath, info.sha256, uid],
      );
      await conn.execute('DELETE FROM bundle_files WHERE id = $1', [info.id]);
      await reload();
    });
  }
  async function onAudioRemoved() {
    await withBusy(async () => {
      const conn = await db();
      const rows = await conn.select<{ description_audio_relpath: string | null }[]>(
        'SELECT description_audio_relpath FROM bundles WHERE uid = $1',
        [uid],
      );
      const rel = rows[0]?.description_audio_relpath;
      await conn.execute(
        `UPDATE bundles
         SET description_audio_relpath = NULL, description_audio_sha256 = NULL,
             description_mode = NULL, updated_at = datetime('now')
         WHERE uid = $1`,
        [uid],
      );
      if (rel) {
        const { invoke } = await import('@tauri-apps/api/core');
        try { await invoke('delete_attachment', { relativePath: rel }); } catch { /* tolerate missing file */ }
      }
      await reload();
    });
  }

  // --- Required thumbnail (single-slot, same lift pattern as the audio
  // description and the Content bundle's preview assets) -----------------
  async function onThumbnailSaved(info: BundleFileInfo) {
    await withBusy(async () => {
      const conn = await db();
      await conn.execute(
        `UPDATE bundles SET thumbnail_relpath = $1, thumbnail_sha256 = $2, updated_at = datetime('now') WHERE uid = $3`,
        [info.relpath, info.sha256, uid],
      );
      await conn.execute('DELETE FROM bundle_files WHERE id = $1', [info.id]);
      await reload();
    });
  }
  async function onThumbnailRemoved() {
    await withBusy(async () => {
      const conn = await db();
      const rows = await conn.select<{ thumbnail_relpath: string | null }[]>(
        'SELECT thumbnail_relpath FROM bundles WHERE uid = $1',
        [uid],
      );
      const rel = rows[0]?.thumbnail_relpath;
      await conn.execute(
        `UPDATE bundles SET thumbnail_relpath = NULL, thumbnail_sha256 = NULL, updated_at = datetime('now') WHERE uid = $1`,
        [uid],
      );
      if (rel) {
        const { invoke } = await import('@tauri-apps/api/core');
        try { await invoke('delete_attachment', { relativePath: rel }); } catch { /* tolerate missing file */ }
      }
      await reload();
    });
  }

  async function onPickFiles(srcPaths: string[]) {
    await withBusy(async () => {
      for (const src of srcPaths) {
        // YouTube bundles are video-only — the picker is locked to video
        // extensions, so every pick is saved as a video clip.
        await saveBundleFile(uid, src, 'video', null);
      }
      await reload();
    });
  }
  async function onRemoveFile(id: number) {
    await withBusy(async () => { await deleteBundleFile(id); await reload(); });
  }
  async function onReorderFiles(orderedIds: number[]) {
    await withBusy(async () => { await reorderBundleFiles(uid, orderedIds); await reload(); });
  }

  if (!bundle) {
    return <div className="p-8 opacity-60 italic">Loading bundle…</div>;
  }

  async function onDeleteDraft() {
    if (locked) return;
    if (!confirm('Delete this draft and all uploaded files? This cannot be undone.')) return;
    const ok = await withBusy(async () => { await deleteBundleDraft(uid); });
    if (ok !== null) {
      onDeleted?.();
      onClose();
    }
  }

  return (
    <div className="p-8 space-y-5 max-w-3xl">
      <div className="flex items-center justify-between gap-2 -mt-2 mb-1">
        <button type="button" onClick={onClose} className="pretty-button secondary">
          ← Bundles
        </button>
        {!locked && (
          <button type="button" onClick={onDeleteDraft} className="pretty-button danger text-xs" disabled={busy}>
            🗑 Delete draft
          </button>
        )}
      </div>
      <BundleSummaryReport bundleUid={uid} />
      <header className="space-y-2">
        <div className="flex items-baseline justify-between gap-3">
          <h2 className="display-font text-2xl font-bold persona-accent">
            ▶️ YouTube Bundle
          </h2>
          <span className="text-xs font-mono opacity-60">{uid}</span>
        </div>
        <p className="opacity-70 text-sm">
          A bundle of video clips for YouTube. Save as you go — drafts persist until you delete them.
        </p>
        {locked && onUnlock && (
          <div className="flex items-center gap-3 bg-pink-50 border border-pink-200 rounded-xl px-3 py-2 text-sm">
            <span className="flex-1">🔒 This bundle is <strong>published</strong> — fields are read-only.</span>
            <button type="button" onClick={onUnlock} className="pretty-button text-xs">📝 Unlock to edit</button>
          </div>
        )}
        {error && (
          <div className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2">
            {error}
          </div>
        )}
      </header>

      <fieldset disabled={locked} className="space-y-5">
        <PersonaPicker personas={personas} value={bundle.summary.personaCode} onChange={setPersona} />

        <TitleField value={bundle.summary.title} onCommit={commitTitle} disabled={busy || locked} />

        <DescriptionField
          bundleUid={uid}
          mode={bundle.descriptionMode}
          text={bundle.descriptionText}
          audioRelpath={bundle.descriptionAudioRelpath}
          audioOriginalName={bundle.descriptionAudioOriginalName}
          prohibitedWords={prohibited}
          onChangeMode={commitDescriptionMode}
          onCommitText={commitDescriptionText}
          onAudioSaved={onAudioSaved}
          onAudioRemoved={onAudioRemoved}
          disabled={busy || locked}
        />

        <PreviewAssetField
          bundleUid={uid}
          label="Thumbnail Image"
          emoji="🖼️"
          hint="The cover image YouTube shows for this video (JPG/PNG, max 5 MB)."
          accept={['jpg', 'jpeg', 'png']}
          pickTitle="Pick a thumbnail image"
          filterName="Image"
          maxBytes={5 * 1024 * 1024}
          required
          relpath={bundle.thumbnailRelpath}
          absolutePath={bundle.thumbnailAbsolutePath}
          originalName={bundle.thumbnailOriginalName}
          onSaved={onThumbnailSaved}
          onRemoved={onThumbnailRemoved}
          disabled={busy || locked}
          accessory={
            <button type="button" className="pretty-button secondary" disabled={busy || locked} onClick={() => setFrameOpen(true)}>
              ✨ Grab a frame from a video
            </button>
          }
        />

        <ContentTagPicker
          tags={contentTags}
          selected={bundle.summary.tagIds}
          onChange={onTagsChange}
          disabled={busy || locked}
        />

        <div className="space-y-2">
          <label className="flex items-center gap-2 text-sm cursor-pointer">
            <input
              id="bundle-make-private"
              type="checkbox"
              className="w-5 h-5"
              checked={bundle.makePrivate}
              onChange={(e) => commitMakePrivate(e.target.checked)}
              disabled={busy || locked}
            />
            <span className="font-semibold">🔒 Make private</span>
            <span className="opacity-60 text-xs">goes live when you publish — no go-live date needed</span>
          </label>
          {bundle.makePrivate ? (
            <div className="text-xs opacity-60 italic pl-7">
              This video will be uploaded <strong>private</strong> and go live the moment you publish. 💕
            </div>
          ) : (
            <GoLiveDatePicker
              value={bundle.summary.goLiveDate}
              onChange={commitGoLive}
              disabled={busy || locked}
            />
          )}
        </div>

        <OrderedFileList
          files={bundle.files.filter((f) => f.fansiteDayId === null)}
          pickTitle="Pick video clips for this YouTube bundle"
          allowedKinds={['video']}
          busy={busy}
          onPick={onPickFiles}
          onRemove={onRemoveFile}
          onReorder={onReorderFiles}
        />

        <SpecialInstructionsField
          value={bundle.specialInstructions}
          onCommit={commitSpecial}
          disabled={busy || locked}
        />

        <div className="space-y-1" id="bundle-also-post-manyvids">
          <div className="text-xs font-semibold opacity-75">Also Post SFW ManyVids</div>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => commitAlsoPostManyvids(true)}
              className={`pretty-button ${bundle.alsoPostSfwManyvids ? '' : 'secondary'}`}
              disabled={busy || locked}
            >Yes</button>
            <button
              type="button"
              onClick={() => commitAlsoPostManyvids(false)}
              className={`pretty-button ${bundle.alsoPostSfwManyvids ? 'secondary' : ''}`}
              disabled={busy || locked}
            >No</button>
          </div>
          <div className="text-xs opacity-60">
            When <strong>Yes</strong>, Robert also posts a SFW cut to ManyVids. It rides along in the bundle's notes.
          </div>
        </div>
      </fieldset>

      <div className="flex justify-end gap-2 pt-2 border-t border-black/5">
        <button type="button" onClick={onPublishRequested} className="pretty-button">
          ▶️ Review &amp; Publish…
        </button>
      </div>

      {frameOpen && (
        <FrameGrabber
          bundleVideos={bundle.files
            .filter((f) => f.kind === 'video')
            .map((f) => ({ absolutePath: f.absolutePath, name: f.originalName }))}
          onUseAsThumbnail={async (bytes, name) => {
            const { saveBundleFrame } = await import('../../data/bundles');
            const info = await saveBundleFrame(uid, bytes, name);
            await onThumbnailSaved(info);
          }}
          onClose={() => setFrameOpen(false)}
        />
      )}
    </div>
  );
}

function PersonaPicker({
  personas, value, onChange,
}: { personas: Persona[]; value: string | null; onChange: (code: string | null) => void; }) {
  return (
    <div className="space-y-1">
      <label htmlFor="bundle-persona" className="text-xs font-semibold opacity-75">Persona</label>
      <select
        id="bundle-persona"
        className="pretty-input"
        value={value ?? ''}
        onChange={(e) => onChange(e.target.value || null)}
      >
        <option value="">— required —</option>
        {personas.map((p) => (
          <option key={p.code} value={p.code}>{p.name}</option>
        ))}
      </select>
    </div>
  );
}

function stringifyError(e: unknown): string {
  if (typeof e === 'string') return e;
  if (e && typeof e === 'object') {
    const obj = e as { message?: string; kind?: string };
    if (obj.message) return obj.message;
    if (obj.kind === 'validationFailed') return 'Some required fields aren’t filled in yet — open the wizard to see the checklist.';
  }
  return String(e);
}
