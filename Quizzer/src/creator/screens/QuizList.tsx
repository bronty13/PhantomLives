import { useRef, useState } from 'react';
import type { Branding, Quiz } from '../../shared/model';
import { newId } from '../../shared/factory';
import { deleteQuiz, getBranding, saveQuiz } from '../storage/db';
import { exportBundleJson } from '../storage/bundle';
import { downloadText } from '../deploy/download';
import { slugify } from '../../shared/util';
import { DeployDialog } from './DeployDialog';

export function QuizList({
  quizzes,
  brandings,
  onOpen,
  onNew,
  onImport,
  reload,
}: {
  quizzes: Quiz[];
  brandings: Branding[];
  onOpen: (q: Quiz) => void;
  onNew: () => void;
  onImport: (file: File) => void;
  reload: () => void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [deploy, setDeploy] = useState<{ quiz: Quiz; branding: Branding } | null>(null);

  async function duplicate(q: Quiz) {
    const copy: Quiz = { ...q, id: newId(), name: `${q.name} (copy)`, createdAt: Date.now(), updatedAt: Date.now() };
    await saveQuiz(copy);
    reload();
  }

  async function remove(q: Quiz) {
    if (!confirm(`Delete "${q.name}"? This cannot be undone.`)) return;
    await deleteQuiz(q.id);
    reload();
  }

  async function exportBundle(q: Quiz) {
    const branding = (await getBranding(q.brandingId)) ?? brandings[0];
    if (!branding) return;
    downloadText(`${slugify(q.name)}.quizzer.json`, exportBundleJson(q, branding), 'application/json');
  }

  async function openDeploy(q: Quiz) {
    const branding = (await getBranding(q.brandingId)) ?? brandings[0];
    if (!branding) {
      alert('Create a branding profile first.');
      return;
    }
    setDeploy({ quiz: q, branding });
  }

  return (
    <div className="screen">
      <div className="screen-head">
        <h1 className="grow">My Quizzes</h1>
        <button className="btn secondary" onClick={() => fileRef.current?.click()}>Import…</button>
        <button className="btn" onClick={onNew}>+ New Quiz</button>
        <input ref={fileRef} type="file" accept=".json,application/json" hidden
          onChange={(e) => { const f = e.target.files?.[0]; if (f) onImport(f); e.target.value = ''; }} />
      </div>

      {quizzes.length === 0 && (
        <p className="empty">No quizzes yet. Click <strong>New Quiz</strong> to build your first one.</p>
      )}

      <div className="card-list">
        {quizzes.map((q) => (
          <div key={q.id} className="list-card">
            <div className="grow">
              <strong>{q.name}</strong>
              <div className="meta">
                {q.questions.length} question{q.questions.length === 1 ? '' : 's'} · pass {q.passingPct}% · {q.attempts} attempt{q.attempts === 1 ? '' : 's'}
              </div>
            </div>
            <div className="row-actions">
              <button className="btn small" onClick={() => onOpen(q)}>Edit</button>
              <button className="btn small accent" onClick={() => openDeploy(q)}>Deploy</button>
              <button className="btn small secondary" onClick={() => duplicate(q)}>Duplicate</button>
              <button className="btn small secondary" onClick={() => exportBundle(q)}>Export</button>
              <button className="btn small danger" onClick={() => remove(q)}>Delete</button>
            </div>
          </div>
        ))}
      </div>

      {deploy && (
        <DeployDialog quiz={deploy.quiz} branding={deploy.branding} onClose={() => setDeploy(null)} />
      )}
    </div>
  );
}
