import { useEffect, useState } from 'react';
import { open } from '@tauri-apps/plugin-dialog';
import {
  clearPersonaClip, listPersonaClips, setPersonaClipEnabled, uploadPersonaClip,
  type PersonaClip, type PersonaClipRole,
} from '../../data/bundles';

// Per-persona intro/outro bumpers for ▶️ YouTube master assembly. Mirrors
// the Watermark pane: one card per persona, with an Intro and an Outro
// row. Personas match the hardcoded set used by Watermark + Platforms.
const PERSONA_LABEL: Record<string, string> = {
  '':    'Default (no persona)',
  CoC:   'Curse of Curves',
  PoA:   'Princess of Addiction',
  Sa:    'Sheer Attraction',
};
const PERSONAS = Object.keys(PERSONA_LABEL);
const ROLES: PersonaClipRole[] = ['intro', 'outro'];

export function IntroOutroSettings() {
  const [clips, setClips] = useState<PersonaClip[]>([]);
  const [status, setStatus] = useState<string>('');
  const [busy, setBusy] = useState(false);

  const refresh = async () => {
    try {
      setClips(await listPersonaClips());
    } catch (e) {
      setStatus(`Failed to load: ${e}`);
    }
  };
  useEffect(() => { refresh(); }, []);

  // Find the stored row for a persona+role (may be absent → treated as
  // "none, disabled").
  const clipFor = (persona: string, role: PersonaClipRole): PersonaClip | undefined =>
    clips.find((c) => c.personaCode === persona && c.role === role);

  const upload = async (persona: string, role: PersonaClipRole) => {
    const picked = await open({
      multiple: false,
      filters: [{ name: 'Video', extensions: ['mp4', 'mov', 'm4v', 'webm'] }],
    });
    if (typeof picked !== 'string' || !picked) return;
    setBusy(true);
    try {
      await uploadPersonaClip(persona, role, picked);
      setStatus(`Uploaded ${role} for ${PERSONA_LABEL[persona] ?? persona}`);
      await refresh();
    } catch (e) {
      setStatus(`Upload failed: ${e}`);
    } finally {
      setBusy(false);
    }
  };

  const toggle = async (persona: string, role: PersonaClipRole, enabled: boolean) => {
    setBusy(true);
    try {
      await setPersonaClipEnabled(persona, role, enabled);
      await refresh();
    } catch (e) {
      setStatus(`Update failed: ${e}`);
    } finally {
      setBusy(false);
    }
  };

  const remove = async (persona: string, role: PersonaClipRole) => {
    setBusy(true);
    try {
      await clearPersonaClip(persona, role);
      setStatus(`Removed ${role} for ${PERSONA_LABEL[persona] ?? persona}`);
      await refresh();
    } catch (e) {
      setStatus(`Remove failed: ${e}`);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="flex flex-col gap-4">
      <div className="sm-card">
        <div className="font-semibold mb-1">▶️ Intro / Outro clips</div>
        <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
          Per-persona intro and outro bumpers. <strong>Only applies to ▶️ YouTube
          bundles</strong> — the master becomes <em>intro → clips → outro</em>
          with cross-dissolves between every segment, and the intro replaces the
          generated title card. Each is off until you upload a clip and turn it
          on; the same clip is reused for every bundle of that persona until you
          change it. Clips are resized to the bundle's format and get the persona
          watermark + audio polish, same as the content clips.
        </div>
      </div>

      {PERSONAS.map((persona) => (
        <div key={persona || 'default'} className="sm-card flex flex-col gap-3">
          <div className="font-semibold">
            {PERSONA_LABEL[persona] ?? (persona || '(no persona)')}
            <span className="ml-2 text-xs font-normal" style={{ color: 'rgb(var(--surface-muted))' }}>
              {persona || '(default for null-persona bundles)'}
            </span>
          </div>

          {ROLES.map((role) => {
            const clip = clipFor(persona, role);
            const hasFile = !!clip && clip.clipPath !== '';
            const filename = hasFile ? clip!.clipPath.split(/[/\\]/).pop() : 'None';
            return (
              <div
                key={role}
                className="flex items-center gap-3 flex-wrap"
                style={{ borderTop: '1px solid rgb(var(--surface-border) / 0.5)', paddingTop: 10 }}
              >
                <span className="text-sm font-medium" style={{ width: 56 }}>
                  {role === 'intro' ? '⏮ Intro' : 'Outro ⏭'}
                </span>
                <span
                  className="font-mono text-xs flex-1 min-w-0 truncate"
                  style={{ color: hasFile ? 'rgb(var(--surface-text))' : 'rgb(var(--surface-muted))' }}
                  title={hasFile ? clip!.clipPath : undefined}
                >
                  {filename}
                </span>
                <label
                  className="flex items-center gap-1.5 text-xs cursor-pointer"
                  title={hasFile ? '' : 'Upload a clip first'}
                >
                  <input
                    type="checkbox"
                    disabled={busy || !hasFile}
                    checked={!!clip?.enabled}
                    onChange={(e) => toggle(persona, role, e.target.checked)}
                  />
                  Enabled
                </label>
                <button
                  type="button"
                  className="sm-button secondary text-xs"
                  disabled={busy}
                  onClick={() => upload(persona, role)}
                >
                  {hasFile ? 'Replace…' : 'Upload…'}
                </button>
                {hasFile && (
                  <button
                    type="button"
                    className="sm-button secondary text-xs"
                    disabled={busy}
                    onClick={() => remove(persona, role)}
                  >
                    Remove
                  </button>
                )}
              </div>
            );
          })}
        </div>
      ))}

      {status && (
        <div className="text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>{status}</div>
      )}
    </div>
  );
}
