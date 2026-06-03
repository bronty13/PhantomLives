import { useCallback, useEffect, useState } from 'react';
import { db } from '../../data/db';
import {
  type Bundle,
  type BundleFileInfo,
  deleteBundleDraft,
  deleteBundleFile,
  getBundle,
  listProhibitedWords,
  readMasterClipperCategories,
  reorderBundleFiles,
  saveBundleFile,
  setBundleCategories,
  updateBundleFields,
} from '../../data/bundles';
import { listPersonas, type Persona } from '../../data/personas';
import { listContentTags, setBundleTags, type ContentTag } from '../../data/contentTags';
import { CategoryChipPicker } from './components/CategoryChipPicker';
import { ContentTagPicker } from './components/ContentTagPicker';
import { DescriptionField } from './components/DescriptionField';
import { GoLiveDatePicker } from './components/GoLiveDatePicker';
import { OrderedFileList } from './components/OrderedFileList';
import { PreviewAssetField } from './components/PreviewAssetField';
import { SpecialInstructionsField } from './components/SpecialInstructionsField';
import { TitleField } from './components/TitleField';
import { GifCreator } from '../GifStudio/GifCreator';
import { FrameGrabber } from '../GifStudio/FrameGrabber';

interface Props {
  uid: string;
  onPublishRequested: () => void;
  onClose: () => void;                    // back to bundles list (also refreshes parent list)
  onDeleted?: () => void;                  // fires after a successful draft delete
  onUnlock?: () => void;                   // unpublish + reopen for editing (only set when locked)
  locked?: boolean;          // published bundles render read-only until ZIP deleted
}

export function ContentBundleForm({ uid, onPublishRequested, onClose, onDeleted, onUnlock, locked }: Props) {
  const [bundle, setBundle] = useState<Bundle | null>(null);
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [prohibited, setProhibited] = useState<string[]>([]);
  const [suggestions, setSuggestions] = useState<string[]>([]);
  const [contentTags, setContentTags] = useState<ContentTag[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [gifOpen, setGifOpen] = useState(false);
  const [frameOpen, setFrameOpen] = useState(false);

  // reload depends only on `uid`; deliberately NOT on any parent callback,
  // since an unstable parent callback would cause this useCallback's
  // identity to change every render, retrigger the mount-time useEffect,
  // and create an infinite reload loop that overwrites Sallie's edits
  // before she can finish them. (Bug fixed once; don't reintroduce.)
  const reload = useCallback(async () => {
    const b = await getBundle(uid);
    setBundle(b);
  }, [uid]);

  useEffect(() => {
    let alive = true;
    Promise.all([reload(), listPersonas(), listProhibitedWords(), loadCategorySuggestions(), listContentTags()])
      .then(([_, p, pw, sug, tags]) => {
        if (!alive) return;
        setPersonas(p);
        setProhibited(pw);
        setSuggestions(sug);
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
      // persona_code lives on bundles row but is set via a separate
      // SQL path (no patch route for it today) — fall back to a direct
      // SQL exec via the shared db handle.
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
      // Remove the file row (we copied the bytes — they live at info.relpath; we
      // just don't want it counted as a media file).
      await conn.execute('DELETE FROM bundle_files WHERE id = $1', [info.id]);
      await reload();
    });
  }
  async function onAudioRemoved() {
    await withBusy(async () => {
      const conn = await db();
      // Capture the current relpath so we can delete the file too.
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
        // delete_attachment is the right primitive for "I have a relpath, delete the file"
        const { invoke } = await import('@tauri-apps/api/core');
        try { await invoke('delete_attachment', { relativePath: rel }); } catch { /* tolerate missing file */ }
      }
      await reload();
    });
  }

  // --- Optional preview assets (thumbnail + teaser GIF) ---------------
  // Same lift pattern as audio: save_bundle_file drops the bytes into the
  // bundle's files dir and returns a row; we move the relpath/sha onto the
  // bundles row and delete the stray bundle_files row so it isn't counted
  // as a media deliverable.
  async function liftSlot(info: BundleFileInfo, relCol: string, shaCol: string) {
    await withBusy(async () => {
      const conn = await db();
      await conn.execute(
        `UPDATE bundles SET ${relCol} = $1, ${shaCol} = $2, updated_at = datetime('now') WHERE uid = $3`,
        [info.relpath, info.sha256, uid],
      );
      await conn.execute('DELETE FROM bundle_files WHERE id = $1', [info.id]);
      await reload();
    });
  }
  async function clearSlot(relCol: string, shaCol: string) {
    await withBusy(async () => {
      const conn = await db();
      const rows = await conn.select<{ rel: string | null }[]>(
        `SELECT ${relCol} AS rel FROM bundles WHERE uid = $1`,
        [uid],
      );
      const rel = rows[0]?.rel;
      await conn.execute(
        `UPDATE bundles SET ${relCol} = NULL, ${shaCol} = NULL, updated_at = datetime('now') WHERE uid = $1`,
        [uid],
      );
      if (rel) {
        const { invoke } = await import('@tauri-apps/api/core');
        try { await invoke('delete_attachment', { relativePath: rel }); } catch { /* tolerate missing file */ }
      }
      await reload();
    });
  }
  const onThumbnailSaved = (info: BundleFileInfo) => liftSlot(info, 'thumbnail_relpath', 'thumbnail_sha256');
  const onThumbnailRemoved = () => clearSlot('thumbnail_relpath', 'thumbnail_sha256');
  const onTeaserSaved = (info: BundleFileInfo) => liftSlot(info, 'teaser_gif_relpath', 'teaser_gif_sha256');
  const onTeaserRemoved = () => clearSlot('teaser_gif_relpath', 'teaser_gif_sha256');

  async function onPickFiles(srcPaths: string[]) {
    await withBusy(async () => {
      for (const src of srcPaths) {
        const kind: 'video' | 'image' = guessKind(src);
        await saveBundleFile(uid, src, kind, null);
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

  async function onCategoriesChange(next: string[]) {
    await withBusy(async () => { await setBundleCategories(uid, next); await reload(); });
  }

  if (!bundle) {
    return <div className="p-8 opacity-60 italic">Loading bundle…</div>;
  }

  const selectedCategories = bundle.categories.map((c) => c.name);

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
      <header className="space-y-2">
        <div className="flex items-baseline justify-between gap-3">
          <h2 className="display-font text-2xl font-bold persona-accent">
            Content Bundle
          </h2>
          <span className="text-xs font-mono opacity-60">{uid}</span>
        </div>
        <p className="opacity-70 text-sm">
          Compose a delivery bundle for Robert. Save as you go — drafts persist until you delete them.
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
          hint="Optional cover image included in the bundle (jpg/png/webp)."
          accept={['jpg', 'jpeg', 'png', 'webp']}
          pickTitle="Pick a thumbnail image"
          filterName="Image"
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

        <PreviewAssetField
          bundleUid={uid}
          label="Teaser GIF"
          emoji="🎞️"
          hint="Optional animated teaser included in the bundle (.gif). Make one from a video with the button."
          accept={['gif']}
          pickTitle="Pick a teaser GIF"
          filterName="GIF"
          relpath={bundle.teaserGifRelpath}
          absolutePath={bundle.teaserGifAbsolutePath}
          originalName={bundle.teaserGifOriginalName}
          onSaved={onTeaserSaved}
          onRemoved={onTeaserRemoved}
          disabled={busy || locked}
          accessory={
            <button type="button" className="pretty-button secondary" disabled={busy || locked} onClick={() => setGifOpen(true)}>
              ✨ Make a GIF from a video
            </button>
          }
        />

        <CategoryChipPicker
          selected={selectedCategories}
          suggestions={suggestions}
          onChange={onCategoriesChange}
          disabled={busy || locked}
        />

        <ContentTagPicker
          tags={contentTags}
          selected={bundle.summary.tagIds}
          onChange={onTagsChange}
          disabled={busy || locked}
        />

        <GoLiveDatePicker
          value={bundle.summary.goLiveDate}
          onChange={commitGoLive}
          disabled={busy || locked}
        />

        <OrderedFileList
          files={bundle.files.filter((f) => f.fansiteDayId === null)}
          pickTitle="Pick videos / images for this bundle"
          allowedKinds={['video', 'image']}
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
      </fieldset>

      <div className="flex justify-end gap-2 pt-2 border-t border-black/5">
        <button type="button" onClick={onPublishRequested} className="pretty-button">
          🎁 Review &amp; Publish…
        </button>
      </div>

      {gifOpen && (
        <GifCreator
          bundleVideos={bundle.files
            .filter((f) => f.kind === 'video')
            .map((f) => ({ absolutePath: f.absolutePath, name: f.originalName }))}
          onUseAsTeaser={async (bytes, name) => {
            const { saveBundleGif } = await import('../../data/bundles');
            const info = await saveBundleGif(uid, bytes, name);
            await onTeaserSaved(info);
          }}
          onClose={() => setGifOpen(false)}
        />
      )}

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

function guessKind(path: string): 'video' | 'image' {
  const ext = (path.split('.').pop() ?? '').toLowerCase();
  const videoExts = ['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi'];
  return videoExts.includes(ext) ? 'video' : 'image';
}

async function loadCategorySuggestions(): Promise<string[]> {
  // Two sources:
  //   (a) categories Sallie has used on bundles already, recency-ordered.
  //       These show up first so muscle-memory works.
  //   (b) categories from MasterClipper's own DB (read-only, best-effort).
  //       Appended alphabetically after the bundle history, deduped
  //       against it case-insensitively. Seeds the picker from her
  //       parent-app vocabulary so the third Content bundle doesn't
  //       require retyping the same 50 names.
  const conn = await db();
  const bundleHistoryRows = await conn.select<{ name: string }[]>(`
    SELECT bc.name AS name
    FROM bundle_categories bc
    JOIN bundles b ON b.uid = bc.bundle_uid
    GROUP BY bc.name
    ORDER BY MAX(b.created_at) DESC
  `);
  const bundleHistory = bundleHistoryRows.map((r) => r.name.toUpperCase());

  const masterClipper = await readMasterClipperCategories();
  const seen = new Set(bundleHistory);
  const merged = [...bundleHistory];
  for (const name of masterClipper) {
    const upper = name.toUpperCase();
    if (!seen.has(upper)) {
      seen.add(upper);
      merged.push(upper);
    }
  }
  return merged;
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
