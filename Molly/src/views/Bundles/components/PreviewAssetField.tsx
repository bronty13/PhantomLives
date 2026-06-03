import { useState, type ReactNode } from 'react';
import { open } from '@tauri-apps/plugin-dialog';
import { invoke } from '@tauri-apps/api/core';
import { convertFileSrc } from '@tauri-apps/api/core';
import type { BundleFileInfo } from '../../../data/bundles';

interface Props {
  bundleUid: string;
  /** e.g. "Thumbnail Image" / "Teaser GIF". */
  label: string;
  /** Short helper line under the label. */
  hint?: string;
  emoji: string;
  /** Lowercase extensions accepted by the file picker. */
  accept: string[];
  /** Dialog title + filter name. */
  pickTitle: string;
  filterName: string;
  relpath: string | null;
  absolutePath: string | null;
  originalName: string | null;
  onSaved: (info: BundleFileInfo) => Promise<void>;
  onRemoved: () => Promise<void>;
  /** Extra control rendered beside the pick button (e.g. "Make a GIF"). */
  accessory?: ReactNode;
  /** Reject a picked file larger than this many bytes (e.g. 5 MB thumbnail cap). */
  maxBytes?: number;
  disabled?: boolean;
}

/** A single optional preview asset on a Content bundle — a cover thumbnail
 * or a teaser GIF. Mirrors DescriptionField's audio sub-flow: pick a file →
 * save_bundle_file(kind='image') → lift to the parent, which moves the
 * relpath onto the bundles row (not bundle_files). Shows an inline preview. */
export function PreviewAssetField({
  bundleUid, label, hint, emoji, accept, pickTitle, filterName,
  relpath, absolutePath, originalName, onSaved, onRemoved, accessory, maxBytes, disabled,
}: Props) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function pick() {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const picked = await open({
        multiple: false, directory: false, title: pickTitle,
        filters: [{ name: filterName, extensions: accept }],
      });
      if (!picked || typeof picked !== 'string') return;
      const ext = picked.split('.').pop()?.toLowerCase() ?? '';
      if (!accept.includes(ext)) {
        setError(`Please pick a ${accept.join(' / ').toUpperCase()} file.`);
        return;
      }
      if (maxBytes != null) {
        const size = await invoke<number>('file_size', { path: picked });
        if (size > maxBytes) {
          setError(`That file is ${(size / (1024 * 1024)).toFixed(1)} MB — the limit is ${(maxBytes / (1024 * 1024)).toFixed(0)} MB. Pick a smaller one.`);
          return;
        }
      }
      const info = await invoke<BundleFileInfo>('save_bundle_file', {
        bundleUid, srcPath: picked, kind: 'image', fansiteDayId: null,
      });
      await onSaved(info);
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  const previewSrc = absolutePath ? convertFileSrc(absolutePath) : null;

  return (
    <div className="space-y-2" id={`bundle-preview-${label.replace(/\s+/g, '-').toLowerCase()}`} tabIndex={-1}>
      <div className="text-xs font-semibold opacity-75">{emoji} {label} <span className="opacity-50 font-normal">(optional)</span></div>
      {hint && <div className="text-xs opacity-60">{hint}</div>}
      {relpath ? (
        <div className="flex items-start gap-3">
          {previewSrc && (
            <img
              src={previewSrc}
              alt={`${label} preview`}
              className="rounded-lg border border-pink-200 object-cover"
              style={{ maxHeight: 120, maxWidth: 200 }}
            />
          )}
          <div className="flex flex-col gap-2 min-w-0">
            <span className="opacity-70 font-mono text-sm truncate">{originalName ?? relpath.split('/').pop()}</span>
            <button type="button" onClick={onRemoved} className="pretty-button danger text-xs self-start" disabled={disabled}>
              Remove
            </button>
          </div>
        </div>
      ) : (
        <div className="flex flex-wrap items-center gap-2">
          <button type="button" onClick={pick} disabled={disabled || busy} className="pretty-button">
            {busy ? 'Saving…' : `＋ Pick ${label.toLowerCase()}`}
          </button>
          {accessory}
        </div>
      )}
      {error && <div className="text-xs text-red-700">{error}</div>}
    </div>
  );
}
