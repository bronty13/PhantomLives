import { useState } from 'react';
import type { GlobalSettings } from '../../shared/model';
import { formatDuration, parseDuration } from '../../shared/util';
import { saveSettings } from '../storage/db';

export function GlobalSettingsScreen({
  settings,
  onSaved,
}: {
  settings: GlobalSettings;
  onSaved: (s: GlobalSettings) => void;
}) {
  const [draft, setDraft] = useState<GlobalSettings>(settings);
  const [time, setTime] = useState(formatDuration(settings.defaultTimeLimitSec));

  function set<K extends keyof GlobalSettings>(key: K, val: GlobalSettings[K]) {
    setDraft((d) => ({ ...d, [key]: val }));
  }

  async function save() {
    const next = { ...draft, defaultTimeLimitSec: parseDuration(time) };
    await saveSettings(next);
    onSaved(next);
  }

  return (
    <div className="screen">
      <h1>Global Settings</h1>
      <p className="meta">Defaults applied to each new quiz. Existing quizzes keep their own values.</p>

      <div className="form-grid">
        <label className="field">
          <span className="field-label">Default time limit (H:MM:SS)</span>
          <input value={time} onChange={(e) => setTime(e.target.value)} />
        </label>
        <label className="field">
          <span className="field-label">Default attempts allowed</span>
          <input type="number" min={1} value={draft.defaultAttempts}
            onChange={(e) => set('defaultAttempts', Math.max(1, +e.target.value))} />
        </label>
        <label className="field">
          <span className="field-label">Default passing score (%)</span>
          <input type="number" min={0} max={100} value={draft.defaultPassingPct}
            onChange={(e) => set('defaultPassingPct', Math.min(100, Math.max(0, +e.target.value)))} />
        </label>
        <label className="field checkbox">
          <input type="checkbox" checked={draft.defaultRandomizeQuestions}
            onChange={(e) => set('defaultRandomizeQuestions', e.target.checked)} />
          <span>Randomize question order by default</span>
        </label>
        <label className="field full">
          <span className="field-label">Default "correct" feedback</span>
          <input value={draft.defaultCorrectText} onChange={(e) => set('defaultCorrectText', e.target.value)} />
        </label>
        <label className="field full">
          <span className="field-label">Default "incorrect" feedback</span>
          <input value={draft.defaultIncorrectText} onChange={(e) => set('defaultIncorrectText', e.target.value)} />
        </label>
      </div>

      <h2 style={{ marginTop: 28 }}>Spin-the-Wheel defaults</h2>
      <p className="meta">Defaults applied to each new wheel. Existing wheels keep their own values.</p>
      <div className="form-grid">
        <label className="field full">
          <span className="field-label">Default wheel description</span>
          <input value={draft.defaultWheelDescription}
            onChange={(e) => set('defaultWheelDescription', e.target.value)} />
        </label>
        <label className="field">
          <span className="field-label">Default result caption</span>
          <input value={draft.defaultResultLabel}
            onChange={(e) => set('defaultResultLabel', e.target.value)} />
        </label>
        <label className="field">
          <span className="field-label">Default spin length (seconds)</span>
          <input type="number" min={1} max={30} value={draft.defaultSpinSeconds}
            onChange={(e) => set('defaultSpinSeconds', Math.min(30, Math.max(1, +e.target.value)))} />
        </label>
        <label className="field">
          <span className="field-label">Default spins permitted (0 = unlimited)</span>
          <input type="number" min={0} value={draft.defaultSpinsPermitted}
            onChange={(e) => set('defaultSpinsPermitted', Math.max(0, +e.target.value))} />
        </label>
        <label className="field">
          <span className="field-label">Default PDF results (1 = latest, 0 = all)</span>
          <input type="number" min={0} value={draft.defaultPdfResultCount}
            onChange={(e) => set('defaultPdfResultCount', Math.max(0, +e.target.value))} />
        </label>
        <label className="field checkbox">
          <input type="checkbox" checked={draft.defaultWheelSoundOn}
            onChange={(e) => set('defaultWheelSoundOn', e.target.checked)} />
          <span>Wheel sound on by default</span>
        </label>
      </div>

      <div className="btn-row">
        <button className="btn" onClick={save}>Save Settings</button>
      </div>
    </div>
  );
}
