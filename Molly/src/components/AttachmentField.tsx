import { useRef, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';

interface Props {
  value: string | null;             // relative path or null
  onChange: (rel: string | null) => void;
  category: string;                  // e.g. "expenses"
}

interface AttachmentInfo {
  relativePath: string;
  absolutePath: string;
  sizeBytes: number;
}

export function AttachmentField({ value, onChange, category }: Props) {
  const fileInput = useRef<HTMLInputElement | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onFilePicked(file: File) {
    setBusy(true);
    setError(null);
    try {
      // Browser File doesn't expose absolute path; route through a hidden
      // download-to-temp dance: write to OS temp via Blob → can't get path
      // back. Instead use the Tauri dialog plugin for picking, which DOES
      // give us a real path.
      //
      // We get here only if the user clicked the fallback hidden input;
      // in practice they'll see the "Pick file…" button which uses
      // tauri.dialog directly (see picking flow in onClickPick).
      void file;
      setError('Please use the Pick file… button.');
    } finally {
      setBusy(false);
    }
  }

  async function onClickPick() {
    setBusy(true);
    setError(null);
    try {
      const { open } = await import('@tauri-apps/plugin-dialog');
      const picked = await open({ multiple: false, directory: false, title: 'Pick a receipt or document' });
      if (!picked || typeof picked !== 'string') return;
      const info = await invoke<AttachmentInfo>('save_attachment', { srcPath: picked, category });
      onChange(info.relativePath);
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  async function onReveal() {
    if (!value) return;
    try {
      await invoke('reveal_attachment', { relativePath: value });
    } catch (e) {
      setError(String(e));
    }
  }

  async function onOpen() {
    if (!value) return;
    try {
      await invoke('open_attachment', { relativePath: value });
    } catch (e) {
      setError(String(e));
    }
  }

  async function onDelete() {
    if (!value) return;
    setBusy(true);
    try {
      await invoke('delete_attachment', { relativePath: value });
      onChange(null);
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-1">
      <input ref={fileInput} type="file" className="hidden" onChange={(e) => {
        const f = e.target.files?.[0]; if (f) onFilePicked(f);
        e.target.value = '';
      }} />
      {value ? (
        <div className="flex items-center gap-2 text-sm">
          <span className="text-xs font-mono opacity-70 truncate flex-1" title={value}>📎 {value.split('/').pop()}</span>
          <button type="button" className="pretty-button secondary" onClick={onOpen} disabled={busy}>Open</button>
          <button type="button" className="pretty-button secondary" onClick={onReveal} disabled={busy}>Reveal</button>
          <button type="button" className="pretty-button danger" onClick={onDelete} disabled={busy}>Remove</button>
        </div>
      ) : (
        <button type="button" className="pretty-button secondary" onClick={onClickPick} disabled={busy}>
          📎 Pick file…
        </button>
      )}
      {error && <div className="text-xs text-red-700">{error}</div>}
    </div>
  );
}
