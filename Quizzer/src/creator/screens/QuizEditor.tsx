import { useState } from 'react';
import type { Branding, GlobalSettings, Question, Quiz } from '../../shared/model';
import { resolveAsset } from '../../shared/assets';
import { formatDuration, parseDuration } from '../../shared/util';
import { makeQuestion } from '../../shared/factory';
import { saveQuiz } from '../storage/db';
import { fileToAssetRef } from '../components/uploadAsset';
import { Wysiwyg } from '../components/Wysiwyg';
import { QuestionEditor } from './QuestionEditor';
import { DeployDialog } from './DeployDialog';

export function QuizEditor({
  initial,
  brandings,
  settings,
  onBack,
  onSaved,
}: {
  initial: Quiz;
  brandings: Branding[];
  settings: GlobalSettings;
  onBack: () => void;
  onSaved: () => void;
}) {
  const [quiz, setQuiz] = useState<Quiz>(initial);
  const [hasTime, setHasTime] = useState(initial.timeLimitSec != null);
  const [timeText, setTimeText] = useState(formatDuration(initial.timeLimitSec ?? settings.defaultTimeLimitSec));
  const [deploying, setDeploying] = useState(false);
  const [dirty, setDirty] = useState(false);

  function set<K extends keyof Quiz>(key: K, val: Quiz[K]) {
    setQuiz((q) => ({ ...q, [key]: val }));
    setDirty(true);
  }

  function setQuestion(id: string, q: Question) {
    set('questions', quiz.questions.map((x) => (x.id === id ? q : x)));
  }
  function addQuestion() {
    set('questions', [...quiz.questions, makeQuestion('mc', settings)]);
  }
  function deleteQuestion(id: string) {
    set('questions', quiz.questions.filter((x) => x.id !== id));
  }
  function moveQuestion(index: number, dir: -1 | 1) {
    const j = index + dir;
    if (j < 0 || j >= quiz.questions.length) return;
    const next = quiz.questions.slice();
    [next[index], next[j]] = [next[j], next[index]];
    set('questions', next);
  }

  async function uploadMedia(file: File | undefined) {
    if (!file) return;
    set('introMedia', await fileToAssetRef(file));
  }

  function effectiveQuiz(): Quiz {
    return { ...quiz, timeLimitSec: hasTime ? parseDuration(timeText) : undefined };
  }

  async function save() {
    const q = effectiveQuiz();
    await saveQuiz(q);
    setQuiz(q);
    setDirty(false);
    onSaved();
  }

  const branding = brandings.find((b) => b.id === quiz.brandingId) ?? brandings[0];
  const media = resolveAsset(quiz.introMedia);

  return (
    <div className="screen">
      <div className="screen-head">
        <button className="btn secondary" onClick={onBack}>← Back</button>
        <h1 className="grow">{quiz.name || 'Untitled Quiz'}</h1>
        <button className="btn secondary" disabled={!branding || quiz.questions.length === 0} onClick={() => setDeploying(true)}>Deploy…</button>
        <button className="btn" onClick={save}>{dirty ? 'Save*' : 'Save'}</button>
      </div>

      <section className="panel">
        <h2>Quiz details</h2>
        <label className="field full">
          <span className="field-label">Quiz name (also the bundle title)</span>
          <input value={quiz.name} onChange={(e) => set('name', e.target.value)} />
        </label>

        <label className="field full">
          <span className="field-label">Branding</span>
          <select value={quiz.brandingId} onChange={(e) => set('brandingId', e.target.value)}>
            {brandings.length === 0 && <option value="">No branding — create one first</option>}
            {brandings.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
          </select>
        </label>

        <span className="field-label">Introduction text</span>
        <Wysiwyg value={quiz.introHtml} onChange={(html) => set('introHtml', html)} />

        <div className="field full">
          <span className="field-label">Intro image or video (optional)</span>
          <div className="upload-row">
            {media && (quiz.introMedia?.mime.startsWith('video') ? <video src={media} style={{ maxHeight: 80 }} /> : <img className="logo-thumb" src={media} alt="" />)}
            <input type="file" accept="image/*,video/*" onChange={(e) => uploadMedia(e.target.files?.[0])} />
            {quiz.introMedia && <button className="btn small secondary" onClick={() => set('introMedia', undefined)}>Remove</button>}
          </div>
        </div>

        <span className="field-label">Additional instructions (optional)</span>
        <Wysiwyg value={quiz.instructionsHtml ?? ''} onChange={(html) => set('instructionsHtml', html)} />
      </section>

      <section className="panel">
        <h2>Rules</h2>
        <div className="form-grid">
          <label className="field checkbox">
            <input type="checkbox" checked={hasTime} onChange={(e) => { setHasTime(e.target.checked); setDirty(true); }} />
            <span>Time limit</span>
          </label>
          <label className="field">
            <span className="field-label">Time (H:MM:SS)</span>
            <input value={timeText} disabled={!hasTime} onChange={(e) => { setTimeText(e.target.value); setDirty(true); }} />
          </label>
          <label className="field">
            <span className="field-label">Attempts allowed</span>
            <input type="number" min={1} value={quiz.attempts} onChange={(e) => set('attempts', Math.max(1, +e.target.value))} />
          </label>
          <label className="field">
            <span className="field-label">Passing score (%)</span>
            <input type="number" min={0} max={100} value={quiz.passingPct} onChange={(e) => set('passingPct', Math.min(100, Math.max(0, +e.target.value)))} />
          </label>
          <label className="field checkbox">
            <input type="checkbox" checked={quiz.randomizeQuestions} onChange={(e) => set('randomizeQuestions', e.target.checked)} />
            <span>Randomize question order</span>
          </label>
          <label className="field checkbox">
            <input type="checkbox" checked={quiz.certificateEnabled} onChange={(e) => set('certificateEnabled', e.target.checked)} />
            <span>Offer completion certificate</span>
          </label>
        </div>
      </section>

      <section className="panel">
        <div className="screen-head">
          <h2 className="grow">Questions ({quiz.questions.length})</h2>
          <button className="btn" onClick={addQuestion}>+ Add Question</button>
        </div>
        {quiz.questions.length === 0 && <p className="empty">No questions yet. Add your first one.</p>}
        {quiz.questions.map((q, i) => (
          <QuestionEditor key={q.id} question={q} index={i}
            onChange={(nq) => setQuestion(q.id, nq)}
            onDelete={() => deleteQuestion(q.id)}
            onMove={(dir) => moveQuestion(i, dir)} />
        ))}
      </section>

      {deploying && branding && (
        <DeployDialog quiz={effectiveQuiz()} branding={branding} onClose={() => setDeploying(false)} />
      )}
    </div>
  );
}
