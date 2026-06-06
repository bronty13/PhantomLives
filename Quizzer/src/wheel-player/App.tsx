import { useEffect, useMemo, useState, type CSSProperties } from 'react';
import { brandingCss } from '../shared/branding';
import { resolveAsset } from '../shared/assets';
import { sanitizeHtml } from '../shared/sanitize';
import { slugify } from '../shared/util';
import { wheelResultBlob, type WheelResultEntry } from '../shared/wheelResult';
import type { WheelData } from './bootstrap';
import { getSpinsUsed, recordSpin } from './spins';
import { SpinWheel } from './SpinWheel';

function historyKey(id: string, token: string): string {
  return `quizzer-wheel:${id}:${token}:history`;
}
function soundKey(id: string): string {
  return `quizzer-wheel:${id}:sound`;
}

function loadHistory(id: string, token: string): WheelResultEntry[] {
  try {
    const raw = localStorage.getItem(historyKey(id, token));
    if (raw) return JSON.parse(raw) as WheelResultEntry[];
  } catch {
    /* ignore */
  }
  return [];
}
function saveHistory(id: string, token: string, history: WheelResultEntry[]): void {
  try {
    localStorage.setItem(historyKey(id, token), JSON.stringify(history));
  } catch {
    /* in-memory only */
  }
}
function loadSoundPref(id: string, fallback: boolean): boolean {
  try {
    const raw = localStorage.getItem(soundKey(id));
    if (raw === 'on') return true;
    if (raw === 'off') return false;
  } catch {
    /* ignore */
  }
  return fallback;
}

export function App({ data }: { data: WheelData }) {
  const { wheel, branding, generatedAt } = data;
  const css = useMemo(() => brandingCss(branding), [branding]);

  const [used, setUsed] = useState(() => getSpinsUsed(wheel.id, generatedAt));
  const [soundOn, setSoundOn] = useState(() => loadSoundPref(wheel.id, wheel.soundDefaultOn));
  const [history, setHistory] = useState<WheelResultEntry[]>(() => loadHistory(wheel.id, generatedAt));
  const [result, setResult] = useState<{ text: string; nonce: number } | null>(null);

  const unlimited = wheel.spinsPermitted === 0;
  const spinsLeft = unlimited ? Infinity : Math.max(0, wheel.spinsPermitted - used);
  const canSpin = spinsLeft > 0;

  useEffect(() => {
    document.title = wheel.name || 'Spin the Wheel';
  }, [wheel.name]);

  function toggleSound() {
    setSoundOn((on) => {
      const next = !on;
      try {
        localStorage.setItem(soundKey(wheel.id), next ? 'on' : 'off');
      } catch {
        /* ignore */
      }
      return next;
    });
  }

  function handleResult(index: number) {
    const text = wheel.choices[index]?.text || `Option ${index + 1}`;
    setResult({ text, nonce: Date.now() });
    setUsed(recordSpin(wheel.id, generatedAt));
    const entry: WheelResultEntry = { label: text, at: new Date().toLocaleString() };
    setHistory((prev) => {
      const next = [...prev, entry];
      saveHistory(wheel.id, generatedAt, next);
      return next;
    });
  }

  function downloadResult() {
    const ordered = [...history].reverse(); // newest first
    const n = wheel.pdfResultCount;
    const results = n > 0 ? ordered.slice(0, n) : ordered;
    if (results.length === 0) return;
    const logo = resolveAsset(branding.logo);
    const blob = wheelResultBlob({
      wheelName: wheel.name,
      caption: resultLabel,
      results,
      colors: branding.colors,
      logoDataUri: logo && logo.startsWith('data:') ? logo : undefined,
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `spin-result-${slugify(wheel.name)}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  const logo = resolveAsset(branding.logo);
  const media = resolveAsset(wheel.media);
  const isVideo = wheel.media?.mime?.startsWith('video');
  const description = sanitizeHtml(wheel.descriptionHtml || '');
  const resultLabel = wheel.resultLabel ?? 'You won';

  return (
    <div className="wheel-app" style={css.vars as CSSProperties}>
      {css.faceCss && <style dangerouslySetInnerHTML={{ __html: css.faceCss }} />}

      <div className="brandbar">
        {logo && <img src={logo} alt="" />}
        <span className="qname">{wheel.name}</span>
        <button
          className="sound-toggle"
          onClick={toggleSound}
          aria-pressed={soundOn}
          title={soundOn ? 'Sound on' : 'Sound off'}
        >
          {soundOn ? '🔊' : '🔇'}
        </button>
      </div>

      <main className="wheel-main">
        <h1>{wheel.name}</h1>
        {description.trim() && (
          <div className="rich" dangerouslySetInnerHTML={{ __html: description }} />
        )}

        {media && (
          <div className="wheel-media">
            {isVideo ? <video src={media} controls playsInline /> : <img src={media} alt="" />}
          </div>
        )}

        <SpinWheel
          choices={wheel.choices}
          colors={branding.colors}
          fontFamily={css.fontFamily}
          soundOn={soundOn}
          canSpin={canSpin}
          spinSeconds={wheel.spinSeconds || 6}
          onResult={handleResult}
          onSpinStart={() => setResult(null)}
        />

        {result && (
          <div className="wheel-result" key={result.nonce}>
            {resultLabel.trim() && <div className="result-label">{resultLabel}</div>}
            <div className="result-prize">{result.text}</div>
          </div>
        )}

        <div className="wheel-foot">
          {!unlimited && (
            <span className="meta">
              Spins remaining: <strong>{spinsLeft}</strong> of {wheel.spinsPermitted}
            </span>
          )}
          {history.length > 0 && (
            <button className="btn secondary" onClick={downloadResult}>
              Download Result (PDF)
            </button>
          )}
        </div>
      </main>
    </div>
  );
}
