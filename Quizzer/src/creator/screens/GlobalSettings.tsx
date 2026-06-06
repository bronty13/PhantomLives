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

      <div className="btn-row">
        <button className="btn" onClick={save}>Save Settings</button>
      </div>
    </div>
  );
}
