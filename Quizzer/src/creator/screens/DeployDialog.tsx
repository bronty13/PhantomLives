import { useState } from 'react';
import type { Branding, Quiz } from '../../shared/model';
import { assetByteSize, INLINE_LIMIT_BYTES } from '../../shared/assets';
import type { DeployFormat } from '../../shared/payload';
import { deployAndDownload } from '../deploy';

export function DeployDialog({
  quiz,
  branding,
  onClose,
}: {
  quiz: Quiz;
  branding: Branding;
  onClose: () => void;
}) {
  const [format, setFormat] = useState<DeployFormat>('single');
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const bigMedia =
    quiz.introMedia?.kind === 'inline' && assetByteSize(quiz.introMedia) > INLINE_LIMIT_BYTES;

  async function run() {
    setBusy(true);
    setError(null);
    try {
      const filename = await deployAndDownload(quiz, branding, format);
      setDone(filename);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h2>Deploy “{quiz.name}”</h2>
        <p className="meta">
          Produces a self-contained quiz that runs offline in any browser. Saves to your
          browser's download folder (set it to <code>~/Downloads/Quizzer/</code> to match the
          Quizzer convention).
        </p>

        <label className={`deploy-opt ${format === 'single' ? 'sel' : ''}`}>
          <input type="radio" checked={format === 'single'} onChange={() => setFormat('single')} />
          <div>
            <strong>Single HTML file</strong>
            <div className="meta">One <code>.html</code> — email it or open it anywhere. Best for most quizzes.</div>
          </div>
        </label>

        <label className={`deploy-opt ${format === 'zip' ? 'sel' : ''}`}>
          <input type="radio" checked={format === 'zip'} onChange={() => setFormat('zip')} />
          <div>
            <strong>Zip (HTML + assets/)</strong>
            <div className="meta">Keeps large media as separate files. Unzip, then open <code>index.html</code>.</div>
          </div>
        </label>

        {bigMedia && format === 'single' && (
          <p className="warn">This quiz has a large intro video. Embedding it inline makes a big HTML file that may be slow on phones — the Zip format is recommended.</p>
        )}

        {error && <p className="warn">Deploy failed: {error}</p>}
        {done && <p className="ok">Downloaded <strong>{done}</strong>.</p>}

        <div className="btn-row">
          <button className="btn secondary" onClick={onClose}>Close</button>
          <button className="btn" disabled={busy} onClick={run}>{busy ? 'Building…' : 'Deploy & Download'}</button>
        </div>
      </div>
    </div>
  );
}
