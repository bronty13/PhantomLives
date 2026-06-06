import type {
  Choice,
  FillBlankQ,
  MultipleAnswerQ,
  MultipleChoiceQ,
  Question,
  QuestionType,
  ShortAnswerQ,
  TrueFalseQ,
} from '../../shared/model';
import { resolveAsset } from '../../shared/assets';
import { newId } from '../../shared/factory';
import { Wysiwyg } from '../components/Wysiwyg';
import { fileToAssetRef } from '../components/uploadAsset';

const TYPE_LABELS: Record<QuestionType, string> = {
  truefalse: 'True / False',
  mc: 'Multiple Choice',
  multi: 'Multiple Answer',
  fill: 'Fill in the Blank',
  short: 'Short Answer',
};

export function QuestionEditor({
  question,
  index,
  onChange,
  onDelete,
  onMove,
}: {
  question: Question;
  index: number;
  onChange: (q: Question) => void;
  onDelete: () => void;
  onMove: (dir: -1 | 1) => void;
}) {
  const q = question;

  function changeType(type: QuestionType) {
    if (type === q.type) return;
    onChange(convertType(q, type));
  }

  return (
    <div className="question-card">
      <div className="q-head">
        <span className="q-num">Q{index + 1}</span>
        <select value={q.type} onChange={(e) => changeType(e.target.value as QuestionType)}>
          {(Object.keys(TYPE_LABELS) as QuestionType[]).map((t) => (
            <option key={t} value={t}>{TYPE_LABELS[t]}</option>
          ))}
        </select>
        <span className="grow" />
        <button className="btn small secondary" onClick={() => onMove(-1)} title="Move up">↑</button>
        <button className="btn small secondary" onClick={() => onMove(1)} title="Move down">↓</button>
        <button className="btn small danger" onClick={onDelete}>Delete</button>
      </div>

      <span className="field-label">Question text</span>
      <Wysiwyg value={q.promptHtml} onChange={(html) => onChange({ ...q, promptHtml: html })} />

      <div className="field full">
        <span className="field-label">Question image (optional — shown above the answers)</span>
        <div className="upload-row">
          {resolveAsset(q.image) && <img className="logo-thumb" src={resolveAsset(q.image)} alt="" />}
          <input type="file" accept="image/*"
            onChange={async (e) => {
              const f = e.target.files?.[0];
              if (f) onChange({ ...q, image: await fileToAssetRef(f) });
              e.target.value = '';
            }} />
          {q.image && <button className="btn small secondary" onClick={() => onChange({ ...q, image: undefined })}>Remove</button>}
        </div>
      </div>

      <div className="type-fields">{renderTypeFields()}</div>

      <details className="advanced">
        <summary>Scoring & feedback</summary>
        <div className="form-grid">
          <label className="field">
            <span className="field-label">Weight (points)</span>
            <input type="number" min={0} step={0.5} value={q.weight}
              onChange={(e) => onChange({ ...q, weight: Math.max(0, +e.target.value) })} />
          </label>
          <label className="field checkbox">
            <input type="checkbox" checked={q.showCorrectAnswer}
              onChange={(e) => onChange({ ...q, showCorrectAnswer: e.target.checked })} />
            <span>Reveal correct answer after submit</span>
          </label>
          <label className="field full">
            <span className="field-label">Correct feedback</span>
            <input value={q.correctText} onChange={(e) => onChange({ ...q, correctText: e.target.value })} />
          </label>
          <label className="field full">
            <span className="field-label">Incorrect feedback</span>
            <input value={q.incorrectText} onChange={(e) => onChange({ ...q, incorrectText: e.target.value })} />
          </label>
        </div>
      </details>
    </div>
  );

  function renderTypeFields() {
    switch (q.type) {
      case 'truefalse':
        return <TrueFalseFields q={q} onChange={onChange} />;
      case 'mc':
        return <ChoiceFields q={q} onChange={onChange} multi={false} />;
      case 'multi':
        return <ChoiceFields q={q} onChange={onChange} multi />;
      case 'fill':
        return <FillFields q={q} onChange={onChange} />;
      case 'short':
        return <ShortFields q={q} onChange={onChange} />;
    }
  }
}

function TrueFalseFields({ q, onChange }: { q: TrueFalseQ; onChange: (q: Question) => void }) {
  return (
    <div>
      <span className="field-label">Correct answer</span>
      <div className="radio-row">
        {[true, false].map((v) => (
          <label key={String(v)}>
            <input type="radio" name={`tf-${q.id}`} checked={q.correct === v}
              onChange={() => onChange({ ...q, correct: v })} />
            {v ? 'True' : 'False'}
          </label>
        ))}
      </div>
    </div>
  );
}

function ChoiceFields({
  q,
  onChange,
  multi,
}: {
  q: MultipleChoiceQ | MultipleAnswerQ;
  onChange: (q: Question) => void;
  multi: boolean;
}) {
  const choices = q.choices;
  const correctIds = multi ? (q as MultipleAnswerQ).correctChoiceIds : [(q as MultipleChoiceQ).correctChoiceId];

  function update(next: Partial<MultipleChoiceQ> & Partial<MultipleAnswerQ>) {
    onChange({ ...q, ...next } as Question);
  }

  function setChoiceText(id: string, text: string) {
    update({ choices: choices.map((c) => (c.id === id ? { ...c, text } : c)) });
  }

  function addChoice() {
    if (choices.length >= 10) return;
    update({ choices: [...choices, { id: newId(), text: '' }] });
  }

  function removeChoice(id: string) {
    if (choices.length <= 2) return;
    const nextChoices = choices.filter((c) => c.id !== id);
    if (multi) {
      update({ choices: nextChoices, correctChoiceIds: (q as MultipleAnswerQ).correctChoiceIds.filter((x) => x !== id) });
    } else {
      const cc = (q as MultipleChoiceQ).correctChoiceId;
      update({ choices: nextChoices, correctChoiceId: cc === id ? '' : cc });
    }
  }

  function toggleCorrect(id: string) {
    if (multi) {
      const set = new Set((q as MultipleAnswerQ).correctChoiceIds);
      set.has(id) ? set.delete(id) : set.add(id);
      update({ correctChoiceIds: [...set] });
    } else {
      update({ correctChoiceId: id });
    }
  }

  return (
    <div>
      <span className="field-label">Answer choices — mark the {multi ? 'correct answers' : 'correct answer'}</span>
      {choices.map((c: Choice, i) => (
        <div key={c.id} className="choice-edit">
          <input type={multi ? 'checkbox' : 'radio'} name={`correct-${q.id}`}
            checked={correctIds.includes(c.id)} onChange={() => toggleCorrect(c.id)} title="Mark correct" />
          <input className="grow" placeholder={`Choice ${i + 1}`} value={c.text}
            onChange={(e) => setChoiceText(c.id, e.target.value)} />
          <button className="btn small secondary" disabled={choices.length <= 2} onClick={() => removeChoice(c.id)}>✕</button>
        </div>
      ))}
      <div className="btn-row">
        <button className="btn small secondary" disabled={choices.length >= 10} onClick={addChoice}>+ Add choice</button>
        <label className="field checkbox inline">
          <input type="checkbox" checked={q.randomizeChoices}
            onChange={(e) => update({ randomizeChoices: e.target.checked })} />
          <span>Randomize choice order</span>
        </label>
      </div>
    </div>
  );
}

function FillFields({ q, onChange }: { q: FillBlankQ; onChange: (q: Question) => void }) {
  function setAccepted(blankId: string, text: string) {
    const accepted = text.split('|').map((s) => s.trim()).filter(Boolean);
    onChange({ ...q, blanks: q.blanks.map((b) => (b.id === blankId ? { ...b, accepted } : b)) });
  }
  return (
    <div>
      <span className="field-label">Blanks — separate multiple accepted answers with " | "</span>
      {q.blanks.map((b, i) => (
        <div key={b.id} className="choice-edit">
          <span className="q-num">{i + 1}</span>
          <input className="grow" placeholder="answer | alt answer" value={b.accepted.join(' | ')}
            onChange={(e) => setAccepted(b.id, e.target.value)} />
          <button className="btn small secondary" disabled={q.blanks.length <= 1}
            onClick={() => onChange({ ...q, blanks: q.blanks.filter((x) => x.id !== b.id) })}>✕</button>
        </div>
      ))}
      <div className="btn-row">
        <button className="btn small secondary"
          onClick={() => onChange({ ...q, blanks: [...q.blanks, { id: newId(), accepted: [''] }] })}>+ Add blank</button>
        <label className="field checkbox inline">
          <input type="checkbox" checked={q.caseSensitive}
            onChange={(e) => onChange({ ...q, caseSensitive: e.target.checked })} />
          <span>Case-sensitive</span>
        </label>
      </div>
    </div>
  );
}

function ShortFields({ q, onChange }: { q: ShortAnswerQ; onChange: (q: Question) => void }) {
  return (
    <div>
      <div className="form-grid">
        <label className="field">
          <span className="field-label">Input style</span>
          <select value={q.mode} onChange={(e) => onChange({ ...q, mode: e.target.value as 'text' | 'paragraph' })}>
            <option value="text">Single line</option>
            <option value="paragraph">Paragraph</option>
          </select>
        </label>
        <label className="field">
          <span className="field-label">Grading</span>
          <select value={q.grading.kind}
            onChange={(e) =>
              onChange({
                ...q,
                grading: e.target.value === 'keyword' ? { kind: 'keyword', keywords: [], minMatches: 1 } : { kind: 'manual' },
              })}>
            <option value="manual">Manual (auto-credit when deployed)</option>
            <option value="keyword">Keyword match</option>
          </select>
        </label>
      </div>
      {q.grading.kind === 'keyword' && (
        <div className="form-grid">
          <label className="field full">
            <span className="field-label">Keywords (separate with " | ")</span>
            <input value={q.grading.keywords.join(' | ')}
              onChange={(e) =>
                onChange({ ...q, grading: { kind: 'keyword', keywords: e.target.value.split('|').map((s) => s.trim()).filter(Boolean), minMatches: (q.grading as { minMatches: number }).minMatches } })} />
          </label>
          <label className="field">
            <span className="field-label">Minimum matches to pass</span>
            <input type="number" min={1} value={q.grading.minMatches}
              onChange={(e) => onChange({ ...q, grading: { kind: 'keyword', keywords: (q.grading as { keywords: string[] }).keywords, minMatches: Math.max(1, +e.target.value) } })} />
          </label>
        </div>
      )}
      {q.grading.kind === 'manual' && (
        <p className="meta">Manual questions can't be graded inside a deployed offline quiz, so the respondent is auto-credited and the answer is marked "self-graded".</p>
      )}
    </div>
  );
}

/** Convert a question to another type, preserving the shared base fields. */
function convertType(q: Question, type: QuestionType): Question {
  const base = {
    id: q.id,
    promptHtml: q.promptHtml,
    image: q.image,
    weight: q.weight,
    correctText: q.correctText,
    incorrectText: q.incorrectText,
    showCorrectAnswer: q.showCorrectAnswer,
  };
  switch (type) {
    case 'truefalse':
      return { ...base, type, correct: true };
    case 'mc':
      return { ...base, type, randomizeChoices: false, choices: [{ id: newId(), text: '' }, { id: newId(), text: '' }], correctChoiceId: '' };
    case 'multi':
      return { ...base, type, randomizeChoices: false, choices: [{ id: newId(), text: '' }, { id: newId(), text: '' }], correctChoiceIds: [] };
    case 'fill':
      return { ...base, type, caseSensitive: false, blanks: [{ id: newId(), accepted: [''] }] };
    case 'short':
      return { ...base, type, mode: 'paragraph', grading: { kind: 'manual' } };
  }
}
