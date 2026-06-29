import { useState } from 'react';
import { open } from '@tauri-apps/plugin-dialog';
import { invoke } from '@tauri-apps/api/core';
import { probeVideo } from '../../data/gifStudio';
import { shrinkVideo, type ShrinkResult } from '../../data/shrink';
import { formatBytes, savingsPercent } from '../../lib/fileSize';

// 🫧 Squish — pick a chonky video, and Molly shrinks it small enough to upload
// to Slack (under 1 GB) while keeping it as pretty as she can. All local; the
// heavy lifting is the bundled ffmpeg engine via the `shrink_video` command.

interface PickedFile {
  absolutePath: string;
  name: string;
  bytes: number;
  width: number;
  height: number;
  durationSec: number;
}

type Stage = 'idle' | 'ready' | 'squishing' | 'done' | 'error';

/** Slack's hard limit, for the "already small enough?" hint. */
const ONE_GB = 1_000_000_000;

function fmtDuration(sec: number): string {
  if (!Number.isFinite(sec) || sec <= 0) return '';
  const total = Math.round(sec);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${String(s).padStart(2, '0')}`;
}

/** Cute commentary that changes as the squish progresses. */
function squishSaying(fraction: number): string {
  if (fraction < 0.05) return 'warming up the squish machine… 🫧';
  if (fraction < 0.3) return 'squishing your clip all small… 🫧';
  if (fraction < 0.6) return 'squeezing out the extra megabytes… 💪🫧';
  if (fraction < 0.85) return 'smoothing it all pretty… ✨';
  return 'almost teeny — just a sec! 🫧';
}

export function SquishView() {
  const [stage, setStage] = useState<Stage>('idle');
  const [file, setFile] = useState<PickedFile | null>(null);
  const [progress, setProgress] = useState(0);
  const [result, setResult] = useState<ShrinkResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function pickFile() {
    try {
      const picked = await open({
        multiple: false,
        directory: false,
        title: 'Pick a video to squish',
        filters: [{ name: 'Video', extensions: ['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi'] }],
      });
      if (!picked || typeof picked !== 'string') return;
      const name = picked.split(/[\\/]/).pop() ?? picked;
      setError(null);
      setResult(null);
      // Probe for size + dimensions so Molly can react before squishing.
      const [probe, bytes] = await Promise.all([
        probeVideo(picked),
        invoke<number>('file_size', { path: picked }).catch(() => 0),
      ]);
      setFile({
        absolutePath: picked,
        name,
        bytes,
        width: probe.width,
        height: probe.height,
        durationSec: probe.durationSec,
      });
      setStage('ready');
    } catch (e) {
      setError(String(e));
      setStage('error');
    }
  }

  async function runSquish() {
    if (!file) return;
    setStage('squishing');
    setProgress(0);
    setError(null);
    try {
      const r = await shrinkVideo({ absolutePath: file.absolutePath }, (f) => setProgress(f));
      setResult(r);
      setStage('done');
    } catch (e) {
      const msg = e && typeof e === 'object' && 'message' in e ? String((e as { message: unknown }).message) : String(e);
      setError(msg);
      setStage('error');
    }
  }

  async function showInFolder(path: string) {
    try {
      await invoke('reveal_path', { path });
    } catch {
      /* best-effort */
    }
  }

  function reset() {
    setStage('idle');
    setFile(null);
    setProgress(0);
    setResult(null);
    setError(null);
  }

  const alreadySmall = file ? file.bytes > 0 && file.bytes <= ONE_GB : false;

  return (
    <div className="p-8 space-y-5 max-w-3xl">
      <header className="space-y-1">
        <h2 className="display-font text-2xl font-bold persona-accent">🫧 Squish</h2>
        <p className="opacity-70 text-sm">
          Got a clip that's too big to upload? Drop it here and I'll squish it small
          enough for Slack (under 1&nbsp;GB) while keeping it as gorgeous as I can. 💕
          Everything happens right here on your computer — nothing leaves it.
        </p>
      </header>

      {/* Pick / file card */}
      {(stage === 'idle' || stage === 'ready') && (
        <div
          className="rounded-3xl p-8 text-center space-y-4"
          style={{
            background: 'rgb(var(--persona-secondary) / 0.35)',
            border: '2px dashed rgb(var(--persona-primary) / 0.4)',
          }}
        >
          {!file ? (
            <>
              <div className="text-5xl">🎬🫧</div>
              <p className="opacity-80">Pick a big video and I'll get to squishing!</p>
              <button type="button" className="pretty-button text-base" onClick={pickFile}>
                📁 Pick a video
              </button>
            </>
          ) : (
            <div className="space-y-3">
              <div className="text-4xl">{file.bytes > ONE_GB ? '🫢' : '🎬'}</div>
              <div className="font-semibold display-font text-lg break-all">{file.name}</div>
              <div className="text-sm opacity-75 space-x-2">
                <span className="font-bold">{formatBytes(file.bytes)}</span>
                {file.width > 0 && (
                  <span>· {file.width}×{file.height}</span>
                )}
                {file.durationSec > 0 && <span>· {fmtDuration(file.durationSec)}</span>}
              </div>
              <p className="text-sm opacity-80">
                {file.bytes > ONE_GB
                  ? 'Ooh, that’s a chonky one — let’s get you Slack-ready! 💖'
                  : alreadySmall
                    ? 'This one’s already under 1 GB, but I can still squish it smaller if you like. 🫧'
                    : 'Let’s squish it! 🫧'}
              </p>
              <div className="flex items-center justify-center gap-2 pt-1">
                <button type="button" className="pretty-button text-base" onClick={runSquish}>
                  🫧 Squish it under 1 GB!
                </button>
                <button type="button" className="pretty-button secondary" onClick={pickFile}>
                  Pick a different one
                </button>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Squishing — progress */}
      {stage === 'squishing' && (
        <div
          className="rounded-3xl p-8 space-y-3"
          style={{ background: 'rgb(var(--persona-secondary) / 0.35)' }}
        >
          <div className="text-center text-4xl">🫧✨</div>
          <div className="text-center font-semibold display-font">{squishSaying(progress)}</div>
          <div className="h-4 rounded-full overflow-hidden" style={{ background: 'rgb(var(--persona-primary) / 0.15)' }}>
            <div
              className="h-full bg-pink-400 transition-all"
              style={{ width: `${Math.max(2, progress * 100)}%` }}
            />
          </div>
          <div className="text-center text-sm opacity-70">{Math.round(progress * 100)}%</div>
          <p className="text-center text-xs opacity-60">
            Big videos can take a few minutes — feel free to go sip your coffee ☕, I’ve got this.
          </p>
        </div>
      )}

      {/* Done */}
      {stage === 'done' && result && (
        <div
          className="rounded-3xl p-8 space-y-3 text-center"
          style={{ background: 'rgb(var(--persona-secondary) / 0.45)', border: '1px solid rgb(var(--persona-primary) / 0.4)' }}
        >
          <div className="text-5xl">🎉🫧</div>
          <div className="display-font text-xl font-bold persona-accent">Squished!</div>
          <div className="text-lg">
            <span className="opacity-70">{formatBytes(result.inputBytes)}</span>
            <span className="mx-2">→</span>
            <span className="font-bold">{formatBytes(result.outputBytes)}</span>
          </div>
          <div className="text-sm opacity-80">
            {savingsPercent(result.inputBytes, result.outputBytes)}% smaller — looks just as cute, I promise. 💕
            {result.outputBytes <= ONE_GB && ' Ready to drop into Slack! 🩷'}
          </div>
          <div className="text-xs opacity-60 break-all">Saved to: {result.outputPath}</div>
          <div className="flex items-center justify-center gap-2 pt-1">
            <button type="button" className="pretty-button" onClick={() => showInFolder(result.outputPath)}>
              📂 Show in folder
            </button>
            <button type="button" className="pretty-button secondary" onClick={reset}>
              🫧 Squish another
            </button>
          </div>
        </div>
      )}

      {/* Error */}
      {stage === 'error' && (
        <div className="rounded-3xl p-6 space-y-3 text-center bg-rose-50 border border-rose-200">
          <div className="text-4xl">🥺</div>
          <div className="font-semibold text-rose-900">Oh no — I couldn’t squish that one.</div>
          <div className="text-sm text-rose-800 break-words">{error}</div>
          <p className="text-xs text-rose-700/80">
            If this keeps happening, yell at me through Robert + Claude Code and we’ll sort it out. 💌
          </p>
          <div className="flex items-center justify-center gap-2 pt-1">
            <button type="button" className="pretty-button secondary" onClick={reset}>
              Try another video
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
