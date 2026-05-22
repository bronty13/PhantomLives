import { useEffect, useState } from 'react';
import { open } from '@tauri-apps/plugin-dialog';
import { invoke } from '@tauri-apps/api/core';
import type { BundleFileInfo } from '../../../data/bundles';

interface Props {
  bundleUid: string;
  mode: 'audio' | 'text' | null;
  text: string;
  audioRelpath: string | null;
  audioOriginalName: string | null;
  prohibitedWords: string[];
  onChangeMode: (mode: 'audio' | 'text' | null) => Promise<void>;
  onCommitText: (s: string) => Promise<void>;
  onAudioSaved: (info: BundleFileInfo) => Promise<void>;
  onAudioRemoved: () => Promise<void>;
  disabled?: boolean;
}

/** Content bundle description — toggle between typing text OR uploading an
 * audio file. Switching mode warns first if the other side has data.
 * The audio file is stored on the bundles row (not bundle_files) — it's
 * "the description," not a media file. */
export function DescriptionField({
  bundleUid, mode, text, audioRelpath, audioOriginalName, prohibitedWords,
  onChangeMode, onCommitText, onAudioSaved, onAudioRemoved, disabled,
}: Props) {
  const [draft, setDraft] = useState(text);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { setDraft(text); }, [text]);

  const liveHits = prohibitedWords.filter((w) => {
    const wl = w.toLowerCase();
    return wl.length > 0 && draft.toLowerCase().includes(wl);
  });

  async function switchMode(next: 'audio' | 'text' | null) {
    if (mode === next) return;
    if (mode === 'text' && text.trim() && next === 'audio') {
      if (!confirm('Switch to audio? Your typed description will be discarded.')) return;
    }
    if (mode === 'audio' && audioRelpath && next === 'text') {
      if (!confirm('Switch to text? Your uploaded audio will be removed.')) return;
      await onAudioRemoved();
    }
    if (next !== 'text') await onCommitText('');
    await onChangeMode(next);
  }

  async function pickAudio() {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const picked = await open({
        multiple: false, directory: false, title: 'Pick audio description',
        filters: [{ name: 'Audio', extensions: ['mp3', 'm4a', 'wav', 'aac', 'flac', 'ogg'] }],
      });
      if (!picked || typeof picked !== 'string') return;
      const info = await invoke<BundleFileInfo>('save_bundle_file', {
        bundleUid, srcPath: picked, kind: 'audio', fansiteDayId: null,
      });
      // Lift to parent — the parent moves the relpath onto the bundle row
      // (not bundle_files) since it's the description, not a media file.
      await onAudioSaved(info);
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-2" id="bundle-description" tabIndex={-1}>
      <div className="text-xs font-semibold opacity-75">Description (text OR audio)</div>
      <div className="flex gap-2">
        <button
          type="button"
          onClick={() => switchMode('text')}
          className={`pretty-button ${mode === 'text' ? '' : 'secondary'}`}
          disabled={disabled}
        >📝 Type</button>
        <button
          type="button"
          onClick={() => switchMode('audio')}
          className={`pretty-button ${mode === 'audio' ? '' : 'secondary'}`}
          disabled={disabled}
        >🎙️ Upload audio</button>
        {mode && (
          <button type="button" onClick={() => switchMode(null)} className="pretty-button secondary" disabled={disabled}>
            Clear
          </button>
        )}
      </div>

      {mode === 'text' && (
        <div>
          <textarea
            id="bundle-description-text"
            className="pretty-input w-full"
            rows={4}
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onBlur={async () => { if (draft !== text) await onCommitText(draft); }}
            placeholder="Describe the content for Robert…"
            disabled={disabled}
          />
          {liveHits.length > 0 && (
            <div className="text-xs text-red-700 mt-1">
              Prohibited word{liveHits.length > 1 ? 's' : ''}: {liveHits.join(', ')}
            </div>
          )}
        </div>
      )}

      {mode === 'audio' && (
        <div className="space-y-1">
          {audioRelpath ? (
            <div className="flex items-center gap-2 text-sm">
              <span className="opacity-70 flex-1 font-mono truncate">🎙️ {audioOriginalName ?? audioRelpath.split('/').pop()}</span>
              <button type="button" onClick={onAudioRemoved} className="pretty-button danger" disabled={disabled}>Remove</button>
            </div>
          ) : (
            <button type="button" onClick={pickAudio} disabled={disabled || busy} className="pretty-button">
              {busy ? 'Saving…' : '＋ Pick audio file'}
            </button>
          )}
          {error && <div className="text-xs text-red-700">{error}</div>}
        </div>
      )}

      {!mode && (
        <div className="text-xs opacity-60 italic">
          Choose Type or Upload audio above. Either is required for a Content bundle.
        </div>
      )}
    </div>
  );
}
