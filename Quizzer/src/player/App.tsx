import { useEffect, useMemo, useState, type CSSProperties } from 'react';
import type { ID, Question } from '../shared/model';
import type { QuestionResponse, QuizScore } from '../shared/grading';
import { gradeQuestion, gradeQuiz } from '../shared/grading';
import { brandingCss } from '../shared/branding';
import { shuffle } from '../shared/util';
import type { PlayerData } from './bootstrap';
import { getAttemptsUsed, recordAttempt } from './attempts';
import { BrandBar } from './flow/BrandBar';
import { Timer } from './flow/Timer';
import { IntroScreen } from './flow/IntroScreen';
import { QuestionView } from './flow/QuestionView';
import { SummaryScreen } from './flow/SummaryScreen';

type Phase = 'intro' | 'quiz' | 'summary';

interface Attempt {
  questions: Question[];
  choiceOrders: Record<ID, ID[]>;
  responses: Record<ID, QuestionResponse | undefined>;
  submitted: Set<ID>;
  index: number;
  name: string;
  attemptNo: number;
}

export function App({ data }: { data: PlayerData }) {
  const { quiz, branding, questions } = data;
  const [phase, setPhase] = useState<Phase>('intro');
  const [used, setUsed] = useState(() => getAttemptsUsed(quiz.id));
  const [attempt, setAttempt] = useState<Attempt | null>(null);
  const [score, setScore] = useState<QuizScore | null>(null);

  const css = useMemo(() => brandingCss(branding), [branding]);
  const attemptsLeft = Math.max(0, quiz.attempts - used);

  useEffect(() => {
    document.title = quiz.name || 'Quiz';
  }, [quiz.name]);

  function startAttempt(name: string) {
    if (attemptsLeft <= 0) return;
    const ordered = quiz.randomizeQuestions ? shuffle(questions) : questions;
    const choiceOrders: Record<ID, ID[]> = {};
    for (const q of ordered) {
      if (q.type === 'mc' || q.type === 'multi') {
        const ids = q.choices.map((c) => c.id);
        choiceOrders[q.id] = q.randomizeChoices ? shuffle(ids) : ids;
      }
    }
    setAttempt({
      questions: ordered,
      choiceOrders,
      responses: {},
      submitted: new Set(),
      index: 0,
      name,
      attemptNo: used + 1,
    });
    setScore(null);
    setPhase('quiz');
  }

  function finish(a: Attempt) {
    const result = gradeQuiz(questions, a.responses, quiz.passingPct);
    setScore(result);
    setUsed(recordAttempt(quiz.id));
    setPhase('summary');
  }

  return (
    <div className="player" style={css.vars as CSSProperties}>
      {css.faceCss && <style dangerouslySetInnerHTML={{ __html: css.faceCss }} />}
      <BrandBar branding={branding} quizName={quiz.name} />

      {phase === 'intro' && (
        <IntroScreen quiz={quiz} attemptsLeft={attemptsLeft} onStart={startAttempt} />
      )}

      {phase === 'quiz' && attempt && (
        <QuizRunner
          attempt={attempt}
          quiz={quiz}
          onUpdate={setAttempt}
          onFinish={() => finish(attempt)}
        />
      )}

      {phase === 'summary' && score && attempt && (
        <SummaryScreen
          quiz={quiz}
          branding={branding}
          score={score}
          respondentName={attempt.name}
          attemptsLeft={attemptsLeft}
          onRetry={() => startAttempt(attempt.name)}
        />
      )}
    </div>
  );
}

function QuizRunner({
  attempt,
  quiz,
  onUpdate,
  onFinish,
}: {
  attempt: Attempt;
  quiz: { timeLimitSec?: number };
  onUpdate: (a: Attempt) => void;
  onFinish: () => void;
}) {
  const q = attempt.questions[attempt.index];
  const total = attempt.questions.length;
  const isSubmitted = attempt.submitted.has(q.id);
  const isLast = attempt.index === total - 1;
  const result = isSubmitted ? gradeQuestion(q, attempt.responses[q.id]) : undefined;

  const setResponse = (r: QuestionResponse) =>
    onUpdate({ ...attempt, responses: { ...attempt.responses, [q.id]: r } });

  const submit = () => {
    const next = new Set(attempt.submitted);
    next.add(q.id);
    onUpdate({ ...attempt, submitted: next });
  };

  const advance = () => {
    if (isLast) onFinish();
    else onUpdate({ ...attempt, index: attempt.index + 1 });
  };

  const answered = attempt.responses[q.id] !== undefined;

  return (
    <>
      {quiz.timeLimitSec != null && (
        <Timer key={attempt.attemptNo} seconds={quiz.timeLimitSec} onExpire={onFinish} />
      )}
      <div className="card">
        <div className="progress"><span style={{ width: `${((attempt.index + 1) / total) * 100}%` }} /></div>
        <div className="meta" style={{ marginBottom: 12 }}>
          Question {attempt.index + 1} of {total}
        </div>

        <QuestionView
          question={q}
          response={attempt.responses[q.id]}
          onChange={setResponse}
          submitted={isSubmitted}
          result={result}
          choiceOrder={attempt.choiceOrders[q.id] ?? []}
        />

        <div className="btn-row">
          {!isSubmitted ? (
            <button className="btn" disabled={!answered} onClick={submit}>Submit</button>
          ) : (
            <button className="btn" onClick={advance}>{isLast ? 'See Results' : 'Next Question'}</button>
          )}
        </div>
      </div>
    </>
  );
}
