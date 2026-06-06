import { useState } from 'react';
import type { Branding, Wheel } from '../../shared/model';
import { assetByteSize, INLINE_LIMIT_BYTES } from '../../shared/assets';
import type { DeployFormat } from '../../shared/payload';
import { deployWheelAndDownload } from '../deploy/wheel';

export function WheelDeployDialog({
  wheel,
  branding,
  onClose,
}: {
  wheel: Wheel;
  branding: Branding;
  onClose: () => void;
}) {
  const [format, setFormat] = useState<DeployFormat>('single');
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const bigMedia =
    wheel.media?.kind === 'inline' && assetByteSize(wheel.media) > INLINE_LIMIT_BYTES;

  async function run() {
    setBusy(true);
    setError(null);
    try {
      const filename = await deployWheelAndDownload(wheel, branding, format);
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
        <h2>Deploy “{wheel.name}”</h2>
        <p className="meta">
          Produces a self-contained Spin-the-Wheel that runs offline in any browser, including
          phones. Saves to your browser's download folder (set it to <code>~/Downloads/Quizzer/</code>{' '}
          to match the Quizzer convention).
        </p>

        <label className={`deploy-opt ${format === 'single' ? 'sel' : ''}`}>
          <input type="radio" checked={format === 'single'} onChange={() => setFormat('single')} />
          <div>
            <strong>Single HTML file</strong>
            <div className="meta">One <code>.html</code> — email it or open it anywhere. Best for most wheels.</div>
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
          <p className="warn">This wheel has a large image/video. Embedding it inline makes a big HTML file that may be slow on phones — the Zip format is recommended.</p>
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
