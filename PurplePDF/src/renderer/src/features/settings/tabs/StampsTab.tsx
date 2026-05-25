/**
 * @file StampsTab.tsx — Settings → Stamps. Lets users
 *
 * - Hide / show built-in stamps.
 * - Create / edit / delete custom text stamps.
 * - Create custom image stamps (logo, scanned rubber stamp, …).
 * - Reorder customs.
 * - Import / export the entire custom collection (JSON or ZIP).
 */

import { useMemo, useRef, useState } from 'react';
import { useStampLibrary } from '../useStampLibrary';
import {
  type CustomImageStamp,
  type CustomStamp,
  type CustomTextStamp,
  base64ToBytes,
  bytesToBase64
} from '../prefs';
import { normalizeImage } from '../../annotate/imageNormalize';
import { exportBundle, importBundle, mergeImported, type ConflictResolution } from '../stampIO';

function newId(prefix: string): string {
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`;
}

const DEFAULT_NEW_TEXT: Omit<CustomTextStamp, 'id'> = {
  kind: 'text',
  label: 'CUSTOM',
  style: 'rect',
  color: '#7C3AED',
  width: 200,
  height: 60,
  subtitleMode: 'both'
};

export default function StampsTab(): JSX.Element {
  const lib = useStampLibrary();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const importFileRef = useRef<HTMLInputElement>(null);

  const customs = lib.prefs?.customStamps ?? [];
  const hiddenIds = useMemo(
    () => new Set(lib.prefs?.hiddenBuiltinStampIds ?? []),
    [lib.prefs]
  );
  const selected = customs.find((s) => s.id === selectedId) ?? null;

  const toggleBuiltinHidden = async (id: string): Promise<void> => {
    const next = new Set(hiddenIds);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    await lib.saveHiddenBuiltins(Array.from(next));
  };

  const addText = async (): Promise<void> => {
    const id = newId('txt');
    const next: CustomStamp[] = [...customs, { ...DEFAULT_NEW_TEXT, id }];
    await lib.saveCustoms(next);
    setSelectedId(id);
  };

  const addImageFromFile = async (file: File): Promise<void> => {
    setBusy(true);
    setError(null);
    try {
      const ab = await file.arrayBuffer();
      const norm = await normalizeImage(new Uint8Array(ab), file.name.split('.').pop() ?? '');
      const id = newId('img');
      const ratio = norm.height / Math.max(1, norm.width);
      const width = 200;
      const stamp: CustomImageStamp = {
        id,
        kind: 'image',
        label: file.name.replace(/\.[^.]+$/, '').slice(0, 40) || 'Image stamp',
        imageBytesB64: bytesToBase64(norm.bytes),
        mime: norm.mime,
        naturalWidth: norm.width,
        naturalHeight: norm.height,
        width,
        height: Math.round(width * ratio),
        defaultIncludeSubtitle: false
      };
      await lib.saveCustoms([...customs, stamp]);
      setSelectedId(id);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const updateSelected = async (patch: Partial<CustomStamp>): Promise<void> => {
    if (!selected) return;
    const next = customs.map((s) =>
      s.id === selected.id ? ({ ...s, ...patch } as CustomStamp) : s
    );
    await lib.saveCustoms(next);
  };

  const duplicateSelected = async (): Promise<void> => {
    if (!selected) return;
    const id = newId(selected.kind === 'image' ? 'img' : 'txt');
    const copy: CustomStamp = { ...selected, id, label: `${selected.label} copy` } as CustomStamp;
    await lib.saveCustoms([...customs, copy]);
    setSelectedId(id);
  };

  const deleteSelected = async (): Promise<void> => {
    if (!selected) return;
    if (!window.confirm(`Delete custom stamp "${selected.label}"?`)) return;
    await lib.saveCustoms(customs.filter((s) => s.id !== selected.id));
    setSelectedId(null);
  };

  const move = async (id: string, dir: -1 | 1): Promise<void> => {
    const idx = customs.findIndex((s) => s.id === id);
    if (idx < 0) return;
    const j = idx + dir;
    if (j < 0 || j >= customs.length) return;
    const next = [...customs];
    [next[idx], next[j]] = [next[j], next[idx]];
    await lib.saveCustoms(next);
  };

  const handleExport = async (scope: 'selected' | 'all'): Promise<void> => {
    setError(null);
    try {
      const toExport =
        scope === 'selected' && selected ? [selected] : customs;
      if (toExport.length === 0) throw new Error('No custom stamps to export.');
      const { bytes, ext } = await exportBundle(toExport);
      const api = (window as unknown as {
        purplePDF?: { stampsExportDialog: (defaultName: string) => Promise<string | null> };
      }).purplePDF;
      const defaultName = `stamps-${new Date().toISOString().slice(0, 10)}.${ext}`;
      const dest = api?.stampsExportDialog ? await api.stampsExportDialog(defaultName) : null;
      if (!dest) return;
      // Use Node fs through the main process; reuse the export dialog return
      // path by writing via a synthetic anchor download as a fallback.
      const ok = await writeFileViaMain(dest, bytes);
      if (!ok) {
        // Fallback: download via anchor
        const ab = new ArrayBuffer(bytes.byteLength);
        new Uint8Array(ab).set(bytes);
        const blob = new Blob([ab], {
          type: ext === 'purplestamps' ? 'application/zip' : 'application/json'
        });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = defaultName;
        a.click();
        URL.revokeObjectURL(url);
      }
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const handleImportClick = async (): Promise<void> => {
    setError(null);
    try {
      const api = (window as unknown as {
        purplePDF?: {
          stampsImportDialog: () => Promise<{ path: string; bytes: ArrayBuffer; ext: string } | null>;
        };
      }).purplePDF;
      if (!api?.stampsImportDialog) {
        importFileRef.current?.click();
        return;
      }
      const picked = await api.stampsImportDialog();
      if (!picked) return;
      const imported = await importBundle(new Uint8Array(picked.bytes));
      const resolution = await askResolution(customs, imported);
      if (!resolution) return;
      await lib.saveCustoms(mergeImported(customs, imported, resolution));
    } catch (err) {
      setError((err as Error).message);
    }
  };

  return (
    <div className="stamps-tab">
      {error && (
        <div className="stamps-error" role="alert">
          ⚠ {error}
        </div>
      )}

      <section className="stamps-section">
        <h4>Built-in stamps</h4>
        <p className="stamps-help">
          Built-ins can be hidden but not edited or deleted, so future updates
          won&apos;t collide with your customizations.
        </p>
        <ul className="stamps-builtin-list">
          {lib.allBuiltins.map((b) => {
            const hidden = hiddenIds.has(b.id);
            return (
              <li key={b.id}>
                <label>
                  <input
                    type="checkbox"
                    checked={!hidden}
                    onChange={() => void toggleBuiltinHidden(b.id)}
                  />
                  <span className="stamps-preset-chip" style={{ borderColor: b.color, color: b.color }}>
                    {b.label}
                  </span>
                </label>
              </li>
            );
          })}
        </ul>
      </section>

      <section className="stamps-section">
        <div className="stamps-section-head">
          <h4>Custom stamps</h4>
          <div className="stamps-toolbar">
            <button type="button" onClick={() => void addText()} disabled={busy}>
              + Text
            </button>
            <label className="stamps-image-btn">
              + Image
              <input
                type="file"
                accept="image/png,image/jpeg,image/gif,image/webp,image/svg+xml,image/heic,image/heif,.heic,.heif"
                style={{ display: 'none' }}
                onChange={(e) => {
                  const f = e.target.files?.[0];
                  e.target.value = '';
                  if (f) void addImageFromFile(f);
                }}
              />
            </label>
            <button
              type="button"
              onClick={() => void duplicateSelected()}
              disabled={!selected || busy}
            >
              Duplicate
            </button>
            <button
              type="button"
              onClick={() => void deleteSelected()}
              disabled={!selected || busy}
              className="danger"
            >
              Delete
            </button>
            <span className="stamps-toolbar-spacer" />
            <button type="button" onClick={() => void handleImportClick()} disabled={busy}>
              Import…
            </button>
            <button
              type="button"
              onClick={() => void handleExport('all')}
              disabled={busy || customs.length === 0}
            >
              Export all…
            </button>
            <button
              type="button"
              onClick={() => void handleExport('selected')}
              disabled={busy || !selected}
            >
              Export selected…
            </button>
          </div>
        </div>

        <div className="stamps-split">
          <ul className="stamps-list" role="listbox" aria-label="Custom stamps">
            {customs.length === 0 && (
              <li className="stamps-empty">
                No custom stamps yet. Click <em>+ Text</em> or <em>+ Image</em>.
              </li>
            )}
            {customs.map((s, i) => (
              <li key={s.id}>
                <button
                  type="button"
                  role="option"
                  aria-selected={selectedId === s.id}
                  className={`stamps-list-item${selectedId === s.id ? ' active' : ''}`}
                  onClick={() => setSelectedId(s.id)}
                >
                  <span className="stamps-list-kind">{s.kind === 'image' ? '🖼' : '✪'}</span>
                  <span className="stamps-list-label">{s.label}</span>
                </button>
                <div className="stamps-list-ops">
                  <button
                    type="button"
                    onClick={() => void move(s.id, -1)}
                    disabled={i === 0}
                    aria-label="Move up"
                  >
                    ▲
                  </button>
                  <button
                    type="button"
                    onClick={() => void move(s.id, 1)}
                    disabled={i === customs.length - 1}
                    aria-label="Move down"
                  >
                    ▼
                  </button>
                </div>
              </li>
            ))}
          </ul>

          <div className="stamps-editor">
            {!selected && (
              <div className="stamps-editor-empty">
                Select a custom stamp on the left, or create a new one to begin editing.
              </div>
            )}
            {selected?.kind === 'text' && (
              <TextStampForm stamp={selected} onChange={updateSelected} />
            )}
            {selected?.kind === 'image' && (
              <ImageStampForm stamp={selected} onChange={updateSelected} />
            )}
          </div>
        </div>
      </section>
    </div>
  );
}

// Fallback file input used when the main-process import dialog is unavailable.
function noopFallback(): null {
  return null;
}
void noopFallback;

/** Editor for a single text stamp. */
function TextStampForm({
  stamp,
  onChange
}: {
  stamp: CustomTextStamp;
  onChange: (patch: Partial<CustomTextStamp>) => void | Promise<void>;
}): JSX.Element {
  return (
    <form className="stamp-form" onSubmit={(e) => e.preventDefault()}>
      <label>
        Label
        <input
          type="text"
          value={stamp.label}
          onChange={(e) => void onChange({ label: e.target.value })}
          maxLength={40}
        />
      </label>
      <label>
        Style
        <select
          value={stamp.style}
          onChange={(e) => void onChange({ style: e.target.value as 'rect' | 'mark' })}
        >
          <option value="rect">Box (APPROVED, DENIED, …)</option>
          <option value="mark">Mark (✓ / ✗ / single glyph)</option>
        </select>
      </label>
      <label>
        Color
        <input
          type="color"
          value={stamp.color}
          onChange={(e) => void onChange({ color: e.target.value })}
        />
      </label>
      <div className="stamp-form-row">
        <label>
          Width (pt)
          <input
            type="number"
            min={20}
            max={600}
            value={stamp.width}
            onChange={(e) => void onChange({ width: Number(e.target.value) })}
          />
        </label>
        <label>
          Height (pt)
          <input
            type="number"
            min={20}
            max={400}
            value={stamp.height}
            onChange={(e) => void onChange({ height: Number(e.target.value) })}
          />
        </label>
      </div>
      <label>
        Default subtitle
        <select
          value={stamp.subtitleMode}
          onChange={(e) =>
            void onChange({
              subtitleMode: e.target.value as 'none' | 'date' | 'user' | 'both'
            })
          }
        >
          <option value="none">None</option>
          <option value="date">Date / time</option>
          <option value="user">User</option>
          <option value="both">User + date</option>
        </select>
      </label>
      <div
        className="stamp-preview"
        style={{
          width: Math.min(stamp.width, 260),
          height: Math.min(stamp.height, 90),
          color: stamp.color,
          border: stamp.style === 'rect' ? `2px solid ${stamp.color}` : 'none',
          fontSize: stamp.style === 'mark' ? Math.min(stamp.height * 0.8, 60) : 20
        }}
      >
        {stamp.label}
      </div>
    </form>
  );
}

/** Editor for a single image stamp. */
function ImageStampForm({
  stamp,
  onChange
}: {
  stamp: CustomImageStamp;
  onChange: (patch: Partial<CustomImageStamp>) => void | Promise<void>;
}): JSX.Element {
  const href = useMemo(() => {
    try {
      const bytes = base64ToBytes(stamp.imageBytesB64);
      const blob = new Blob([bytes.slice().buffer], { type: stamp.mime });
      return URL.createObjectURL(blob);
    } catch {
      return '';
    }
  }, [stamp.imageBytesB64, stamp.mime]);

  return (
    <form className="stamp-form" onSubmit={(e) => e.preventDefault()}>
      <label>
        Label
        <input
          type="text"
          value={stamp.label}
          onChange={(e) => void onChange({ label: e.target.value })}
          maxLength={40}
        />
      </label>
      <div className="stamp-form-row">
        <label>
          Width (pt)
          <input
            type="number"
            min={20}
            max={600}
            value={stamp.width}
            onChange={(e) => void onChange({ width: Number(e.target.value) })}
          />
        </label>
        <label>
          Height (pt)
          <input
            type="number"
            min={20}
            max={600}
            value={stamp.height}
            onChange={(e) => void onChange({ height: Number(e.target.value) })}
          />
        </label>
      </div>
      <label>
        <input
          type="checkbox"
          checked={stamp.defaultIncludeSubtitle}
          onChange={(e) => void onChange({ defaultIncludeSubtitle: e.target.checked })}
        />
        Overlay user + date/time subtitle when placing
      </label>
      <div className="stamp-preview stamp-preview-image">
        {href ? <img src={href} alt={stamp.label} /> : <span>(no image bytes)</span>}
      </div>
      <p className="stamps-help">
        Source: {stamp.naturalWidth}×{stamp.naturalHeight}px · stored as {stamp.mime} ·{' '}
        {(stamp.imageBytesB64.length * 0.75).toLocaleString()} bytes
      </p>
    </form>
  );
}

/** Write a Uint8Array to disk via the main process (electron's fs). */
async function writeFileViaMain(path: string, bytes: Uint8Array): Promise<boolean> {
  const api = (window as unknown as {
    purplePDF?: { writeFileBytes?: (p: string, b: ArrayBuffer) => Promise<boolean> };
  }).purplePDF;
  if (!api?.writeFileBytes) return false;
  const ab = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(ab).set(bytes);
  return await api.writeFileBytes(path, ab);
}

/** Synchronous prompt — three buttons rendered as a window.confirm fallback. */
async function askResolution(
  current: CustomStamp[],
  imported: CustomStamp[]
): Promise<ConflictResolution | null> {
  if (current.length === 0) return 'append';
  const conflictIds = new Set(current.map((s) => s.id));
  const conflicts = imported.filter((s) => conflictIds.has(s.id));
  if (conflicts.length === 0) return 'append';
  const msg =
    `${imported.length} stamps imported, ${conflicts.length} conflict with existing IDs:\n` +
    conflicts.map((s) => `  • ${s.label} (${s.id})`).join('\n') +
    '\n\nClick OK to replace conflicting stamps, or Cancel to append (rename conflicts).';
  return window.confirm(msg) ? 'replace-conflicts' : 'append';
}
