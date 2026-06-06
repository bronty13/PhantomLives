import type { ID, Question } from '../../shared/model';
import type { GradeResult, QuestionResponse } from '../../shared/grading';
import { resolveAsset } from '../../shared/assets';
import { RichText } from './RichText';

interface Props {
  question: Question;
  response: QuestionResponse | undefined;
  onChange: (r: QuestionResponse) => void;
  submitted: boolean;
  result: GradeResult | undefined;
  /** Display order of choice ids for mc/multi (may be shuffled). */
  choiceOrder: ID[];
}

export function QuestionView({ question: q, response, onChange, submitted, result, choiceOrder }: Props) {
  const image = resolveAsset(q.image);

  return (
    <div>
      <RichText html={q.promptHtml} />
      {image && (
        <div className="question-image">
          <img src={image} alt="" />
        </div>
      )}
      <div style={{ marginTop: 12 }}>
        {renderInput()}
      </div>
      {submitted && result && <Feedback q={q} result={result} />}
    </div>
  );

  function renderInput() {
    switch (q.type) {
      case 'truefalse': {
        const value = response?.type === 'truefalse' ? response.value : null;
        return [true, false].map((opt) => {
          const selected = value === opt;
          const isCorrect = q.correct === opt;
          const cls = choiceClass(selected, submitted, isCorrect, q.showCorrectAnswer);
          return (
            <label key={String(opt)} className={`choice ${cls}`}>
              <input type="radio" name={q.id} disabled={submitted} checked={selected}
                onChange={() => onChange({ type: 'truefalse', value: opt })} />
              {opt ? 'True' : 'False'}
            </label>
          );
        });
      }
      case 'mc': {
        const sel = response?.type === 'mc' ? response.choiceId : null;
        return choiceOrder.map((cid) => {
          const choice = q.choices.find((c) => c.id === cid);
          if (!choice) return null;
          const selected = sel === cid;
          const isCorrect = q.correctChoiceId === cid;
          const cls = choiceClass(selected, submitted, isCorrect, q.showCorrectAnswer);
          return (
            <label key={cid} className={`choice ${cls}`}>
              <input type="radio" name={q.id} disabled={submitted} checked={selected}
                onChange={() => onChange({ type: 'mc', choiceId: cid })} />
              {choice.text}
            </label>
          );
        });
      }
      case 'multi': {
        const sel = response?.type === 'multi' ? response.choiceIds : [];
        return choiceOrder.map((cid) => {
          const choice = q.choices.find((c) => c.id === cid);
          if (!choice) return null;
          const selected = sel.includes(cid);
          const isCorrect = q.correctChoiceIds.includes(cid);
          const cls = choiceClass(selected, submitted, isCorrect, q.showCorrectAnswer);
          return (
            <label key={cid} className={`choice ${cls}`}>
              <input type="checkbox" disabled={submitted} checked={selected}
                onChange={(e) => {
                  const next = e.target.checked ? [...sel, cid] : sel.filter((x) => x !== cid);
                  onChange({ type: 'multi', choiceIds: next });
                }} />
              {choice.text}
            </label>
          );
        });
      }
      case 'fill': {
        const answers = response?.type === 'fill' ? response.answers : {};
        return q.blanks.map((b, i) => (
          <div key={b.id}>
            <span className="field-label">Blank {i + 1}</span>
            <input className="blank-input" type="text" disabled={submitted}
              value={answers[b.id] ?? ''}
              onChange={(e) => onChange({ type: 'fill', answers: { ...answers, [b.id]: e.target.value } })} />
          </div>
        ));
      }
      case 'short': {
        const text = response?.type === 'short' ? response.text : '';
        const common = {
          className: 'short-input',
          disabled: submitted,
          value: text,
          onChange: (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
            onChange({ type: 'short', text: e.target.value }),
        };
        return q.mode === 'paragraph'
          ? <textarea {...common} placeholder="Type your answer…" />
          : <input type="text" {...common} placeholder="Type your answer…" />;
      }
    }
  }
}

function choiceClass(selected: boolean, submitted: boolean, isCorrect: boolean, showCorrect: boolean): string {
  if (!submitted) return selected ? 'selected' : '';
  if (isCorrect && showCorrect) return 'correct';
  if (selected && !isCorrect) return 'incorrect';
  return selected ? 'selected' : '';
}

function Feedback({ q, result }: { q: Question; result: GradeResult }) {
  if (result.selfGraded) {
    return <div className="feedback neutral">Answer recorded — this question is self-graded.</div>;
  }
  return (
    <div className={`feedback ${result.correct ? 'correct' : 'incorrect'}`}>
      <div>{result.correct ? q.correctText : q.incorrectText}</div>
      {!result.correct && q.showCorrectAnswer && <CorrectAnswer q={q} />}
    </div>
  );
}

function CorrectAnswer({ q }: { q: Question }) {
  switch (q.type) {
    case 'truefalse':
      return <div className="meta">Correct answer: {q.correct ? 'True' : 'False'}</div>;
    case 'mc': {
      const c = q.choices.find((x) => x.id === q.correctChoiceId);
      return c ? <div className="meta">Correct answer: {c.text}</div> : null;
    }
    case 'multi': {
      const labels = q.correctChoiceIds
        .map((id) => q.choices.find((c) => c.id === id)?.text)
        .filter(Boolean)
        .join(', ');
      return <div className="meta">Correct answers: {labels}</div>;
    }
    case 'fill':
      return (
        <div className="meta">
          Accepted: {q.blanks.map((b, i) => `(${i + 1}) ${b.accepted.join(' / ')}`).join('  ')}
        </div>
      );
    case 'short':
      return q.grading.kind === 'keyword'
        ? <div className="meta">Looking for: {q.grading.keywords.join(', ')}</div>
        : null;
  }
}
