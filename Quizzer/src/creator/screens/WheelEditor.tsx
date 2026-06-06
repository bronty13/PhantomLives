import { useState } from 'react';
import type { Branding, Wheel, WheelChoice } from '../../shared/model';
import {
  DEFAULT_RESULT_LABEL,
  DEFAULT_SPIN_SECONDS,
  WHEEL_MAX_CHOICES,
  WHEEL_MIN_CHOICES,
} from '../../shared/model';
import { resolveAsset } from '../../shared/assets';
import { newId } from '../../shared/factory';
import { saveWheel } from '../storage/db';
import { fileToAssetRef } from '../components/uploadAsset';
import { Wysiwyg } from '../components/Wysiwyg';
import { WheelDeployDialog } from './WheelDeployDialog';

export function WheelEditor({
  initial,
  brandings,
  onBack,
  onSaved,
}: {
  initial: Wheel;
  brandings: Branding[];
  onBack: () => void;
  onSaved: () => void;
}) {
  // Backfill fields that pre-0.3.1 saved wheels may lack at runtime.
  const [wheel, setWheel] = useState<Wheel>(() => ({
    ...initial,
    resultLabel: initial.resultLabel ?? DEFAULT_RESULT_LABEL,
    spinSeconds: initial.spinSeconds || DEFAULT_SPIN_SECONDS,
  }));
  const [deploying, setDeploying] = useState(false);
  const [showOdds, setShowOdds] = useState(() => initial.choices.some((c) => c.weight !== 1));
  const [dirty, setDirty] = useState(false);

  function set<K extends keyof Wheel>(key: K, val: Wheel[K]) {
    setWheel((w) => ({ ...w, [key]: val }));
    setDirty(true);
  }

  function setChoice(id: string, patch: Partial<WheelChoice>) {
    set('choices', wheel.choices.map((c) => (c.id === id ? { ...c, ...patch } : c)));
  }
  function addChoice() {
    if (wheel.choices.length >= WHEEL_MAX_CHOICES) return;
    set('choices', [...wheel.choices, { id: newId(), text: '', weight: 1 }]);
  }
  function deleteChoice(id: string) {
    if (wheel.choices.length <= WHEEL_MIN_CHOICES) return;
    set('choices', wheel.choices.filter((c) => c.id !== id));
  }
  function moveChoice(index: number, dir: -1 | 1) {
    const j = index + dir;
    if (j < 0 || j >= wheel.choices.length) return;
    const next = wheel.choices.slice();
    [next[index], next[j]] = [next[j], next[index]];
    set('choices', next);
  }

  async function uploadMedia(file: File | undefined) {
    if (!file) return;
    set('media', await fileToAssetRef(file));
  }

  async function save() {
    await saveWheel(wheel);
    setDirty(false);
    onSaved();
  }

  const branding = brandings.find((b) => b.id === wheel.brandingId) ?? brandings[0];
  const media = resolveAsset(wheel.media);

  return (
    <div className="screen">
      <div className="screen-head">
        <button className="btn secondary" onClick={onBack}>← Back</button>
        <h1 className="grow">{wheel.name || 'Untitled Wheel'}</h1>
        <button className="btn secondary" disabled={!branding} onClick={() => setDeploying(true)}>Deploy…</button>
        <button className="btn" onClick={save}>{dirty ? 'Save*' : 'Save'}</button>
      </div>

      <section className="panel">
        <h2>Wheel details</h2>
        <label className="field full">
          <span className="field-label">Title (also the bundle title)</span>
          <input value={wheel.name} onChange={(e) => set('name', e.target.value)} />
        </label>

        <label className="field full">
          <span className="field-label">Branding</span>
          <select value={wheel.brandingId} onChange={(e) => set('brandingId', e.target.value)}>
            {brandings.length === 0 && <option value="">No branding — create one first</option>}
            {brandings.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
          </select>
        </label>

        <span className="field-label">Description (shown above the wheel)</span>
        <Wysiwyg value={wheel.descriptionHtml} onChange={(html) => set('descriptionHtml', html)} />

        <div className="field full">
          <span className="field-label">Image or video (optional, shown after the description)</span>
          <div className="upload-row">
            {media && (wheel.media?.mime.startsWith('video') ? <video src={media} style={{ maxHeight: 80 }} /> : <img className="logo-thumb" src={media} alt="" />)}
            <input type="file" accept="image/*,video/*" onChange={(e) => uploadMedia(e.target.files?.[0])} />
            {wheel.media && <button className="btn small secondary" onClick={() => set('media', undefined)}>Remove</button>}
          </div>
        </div>
      </section>

      <section className="panel">
        <div className="screen-head">
          <h2 className="grow">Wheel choices ({wheel.choices.length}/{WHEEL_MAX_CHOICES})</h2>
          <label className="field checkbox" style={{ marginRight: 12 }}>
            <input type="checkbox" checked={showOdds} onChange={(e) => setShowOdds(e.target.checked)} />
            <span>Advanced odds</span>
          </label>
          <button className="btn" disabled={wheel.choices.length >= WHEEL_MAX_CHOICES} onClick={addChoice}>+ Add Choice</button>
        </div>
        {showOdds && (
          <p className="meta">
            Weight sets relative landing odds (default 1 = fair). <strong>0 = never lands</strong>. Sectors
            still render equal-sized — only the odds change.
          </p>
        )}
        {wheel.choices.map((c, i) => (
          <div key={c.id} className="choice-row">
            <span className="choice-num">{i + 1}.</span>
            <input
              className="grow"
              value={c.text}
              placeholder={`Choice ${i + 1}`}
              onChange={(e) => setChoice(c.id, { text: e.target.value })}
            />
            {showOdds && (
              <label className="choice-weight" title="Relative landing odds (0 = never lands)">
                <span className="field-label">odds</span>
                <input
                  type="number"
                  min={0}
                  step={1}
                  value={c.weight}
                  onChange={(e) => setChoice(c.id, { weight: Math.max(0, +e.target.value) })}
                />
              </label>
            )}
            <button className="btn small secondary" onClick={() => moveChoice(i, -1)} disabled={i === 0}>↑</button>
            <button className="btn small secondary" onClick={() => moveChoice(i, 1)} disabled={i === wheel.choices.length - 1}>↓</button>
            <button className="btn small danger" onClick={() => deleteChoice(c.id)} disabled={wheel.choices.length <= WHEEL_MIN_CHOICES}>✕</button>
          </div>
        ))}
      </section>

      <section className="panel">
        <h2>Spin rules</h2>
        <div className="form-grid">
          <label className="field">
            <span className="field-label">Number of spins permitted</span>
            <input type="number" min={0} value={wheel.spinsPermitted}
              onChange={(e) => set('spinsPermitted', Math.max(0, +e.target.value))} />
            <span className="meta">0 = unlimited</span>
          </label>
          <label className="field">
            <span className="field-label">Spin length (seconds)</span>
            <input type="number" min={1} max={30} value={wheel.spinSeconds}
              onChange={(e) => set('spinSeconds', Math.min(30, Math.max(1, +e.target.value)))} />
            <span className="meta">how long the wheel spins before it stops</span>
          </label>
          <label className="field full">
            <span className="field-label">Result caption (shown above the prize)</span>
            <input value={wheel.resultLabel} placeholder={DEFAULT_RESULT_LABEL}
              onChange={(e) => set('resultLabel', e.target.value)} />
          </label>
          <label className="field">
            <span className="field-label">PDF results to list</span>
            <input type="number" min={0} value={wheel.pdfResultCount}
              onChange={(e) => set('pdfResultCount', Math.max(0, +e.target.value))} />
            <span className="meta">1 = latest only · 0 = all spins</span>
          </label>
          <label className="field checkbox">
            <input type="checkbox" checked={wheel.soundDefaultOn} onChange={(e) => set('soundDefaultOn', e.target.checked)} />
            <span>Sound on by default</span>
          </label>
        </div>
      </section>

      {deploying && branding && (
        <WheelDeployDialog wheel={wheel} branding={branding} onClose={() => setDeploying(false)} />
      )}
    </div>
  );
}
