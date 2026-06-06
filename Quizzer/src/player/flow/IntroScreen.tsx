import { useState } from 'react';
import type { Quiz } from '../../shared/model';
import { resolveAsset } from '../../shared/assets';
import { formatDuration } from '../../shared/util';
import { RichText } from './RichText';

export function IntroScreen({
  quiz,
  attemptsLeft,
  onStart,
}: {
  quiz: Quiz;
  attemptsLeft: number;
  onStart: (name: string) => void;
}) {
  const [name, setName] = useState('');
  const media = resolveAsset(quiz.introMedia);
  const isVideo = quiz.introMedia?.mime?.startsWith('video');

  return (
    <div className="card">
      <h1>{quiz.name}</h1>
      <RichText html={quiz.introHtml} />

      {media && (
        <div className="intro-media">
          {isVideo ? (
            <video src={media} controls playsInline />
          ) : (
            <img src={media} alt="" />
          )}
        </div>
      )}

      <RichText html={quiz.instructionsHtml ?? ''} />

      <label className="field-label" htmlFor="resp-name">Your name (for the certificate)</label>
      <input
        id="resp-name"
        className="short-input"
        type="text"
        placeholder="Enter your name"
        value={name}
        onChange={(e) => setName(e.target.value)}
      />

      <ul className="meta">
        {quiz.timeLimitSec != null && (
          <li>You have <strong>{formatDuration(quiz.timeLimitSec)}</strong> to complete this quiz.</li>
        )}
        <li>Passing score: <strong>{quiz.passingPct}%</strong></li>
        <li>Attempts remaining: <strong>{attemptsLeft}</strong> of {quiz.attempts}</li>
      </ul>

      <div className="btn-row">
        <button className="btn" disabled={attemptsLeft <= 0} onClick={() => onStart(name.trim())}>
          {attemptsLeft <= 0 ? 'No attempts remaining' : 'Start Quiz'}
        </button>
      </div>
    </div>
  );
}
