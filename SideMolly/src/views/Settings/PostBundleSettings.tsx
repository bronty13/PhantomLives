import { useEffect, useState } from 'react';
import { open } from '@tauri-apps/plugin-dialog';
import { getPostBundleSettings, revealPostBundleDir, setPostBundleDir,
         type PostBundleSettings as PostBundleSettingsT } from '../../data/bundles';

// Settings → Post-bundles. Lets Robert pick where "Send to Molly" drops the
// composed <UID>-post.zip (and its browsable sidecar folder). Mirrors the
// Watched-folder pane's path-picker pattern exactly.
export function PostBundleSettings() {
  const [settings, setSettings] = useState<PostBundleSettingsT | null>(null);
  const [status, setStatus] = useState<string>('');

  const refresh = async () => {
    try {
      setSettings(await getPostBundleSettings());
    } catch (e) {
      setStatus(`Failed to load: ${e}`);
    }
  };

  useEffect(() => { refresh(); }, []);

  const pickFolder = async () => {
    try {
      const picked = await open({ directory: true, multiple: false });
      if (typeof picked === 'string') {
        const next = await setPostBundleDir(picked);
        setSettings(next);
        setStatus(`Post-bundles will be saved to ${picked}`);
      }
    } catch (e) {
      setStatus(`Pick failed: ${e}`);
    }
  };

  const useDefault = async () => {
    try {
      const next = await setPostBundleDir(null);
      setSettings(next);
      setStatus('Reverted to the default post-bundles folder.');
    } catch (e) {
      setStatus(`Reset failed: ${e}`);
    }
  };

  const reveal = async () => {
    try { await revealPostBundleDir(); }
    catch (e) { setStatus(`Reveal failed: ${e}`); }
  };

  if (!settings) return <div className="sm-card">Loading…</div>;

  return (
    <div className="flex flex-col gap-4">
      <div className="sm-card">
        <div className="font-semibold mb-2">Post-bundles folder</div>
        <div className="text-xs mb-2" style={{ color: 'rgb(var(--surface-muted))' }}>
          Where <strong>Send to Molly</strong> writes the composed{' '}
          <code>&lt;date&gt;-post-&lt;title&gt;.zip</code> (plus a plain,
          browsable folder of the same name). This is the file you hand back
          to Molly.
        </div>
        <div className="font-mono text-xs sm-card mt-2" style={{ background: 'rgb(var(--surface-base))' }}>
          {settings.resolvedPath}
        </div>
        <div className="text-xs mt-1" style={{ color: 'rgb(var(--surface-muted))' }}>
          {settings.usingDefault ? '(using default ~/Downloads/Molly post-bundles/)' : '(custom path)'}
        </div>
        <div className="flex gap-2 mt-3 flex-wrap">
          <button type="button" className="sm-button" onClick={pickFolder}>
            📂 Choose folder…
          </button>
          {!settings.usingDefault && (
            <button type="button" className="sm-button secondary" onClick={useDefault}>
              ↺ Use default
            </button>
          )}
          <button type="button" className="sm-button secondary" onClick={reveal}>
            📁 Reveal
          </button>
        </div>
      </div>

      {status && (
        <div className="text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
          {status}
        </div>
      )}
    </div>
  );
}
