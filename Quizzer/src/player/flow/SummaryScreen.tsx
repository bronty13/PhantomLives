import type { Branding, Quiz } from '../../shared/model';
import type { QuizScore } from '../../shared/grading';
import { certificateBlob } from '../../shared/certificate';
import { resolveAsset } from '../../shared/assets';
import { slugify } from '../../shared/util';

export function SummaryScreen({
  quiz,
  branding,
  score,
  respondentName,
  attemptsLeft,
  onRetry,
}: {
  quiz: Quiz;
  branding: Branding;
  score: QuizScore;
  respondentName: string;
  attemptsLeft: number;
  onRetry: () => void;
}) {
  const pct = Math.round(score.pct);
  const canCertify = quiz.certificateEnabled && score.passed;

  function downloadCertificate() {
    const logo = resolveAsset(branding.logo);
    const blob = certificateBlob({
      respondentName: respondentName || 'Respondent',
      quizName: quiz.name,
      dateText: new Date().toLocaleString(),
      scorePct: score.pct,
      colors: branding.colors,
      logoDataUri: logo && logo.startsWith('data:') ? logo : undefined,
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `certificate-${slugify(quiz.name)}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  return (
    <div className="card" style={{ textAlign: 'center' }}>
      <h1>Quiz Complete</h1>
      <div className="score-big">{pct}%</div>
      <div className="meta" style={{ marginBottom: 16 }}>
        {score.awarded} of {score.max} points
      </div>
      <div className={`verdict ${score.passed ? 'pass' : 'fail'}`}>
        {score.passed ? 'PASS' : 'FAIL'}
      </div>

      {score.selfGradedCount > 0 && (
        <p className="meta" style={{ marginTop: 16 }}>
          {score.selfGradedCount} self-graded question{score.selfGradedCount > 1 ? 's were' : ' was'} credited
          automatically (no automatic grading available).
        </p>
      )}

      <div className="btn-row" style={{ justifyContent: 'center' }}>
        {canCertify && (
          <button className="btn accent" onClick={downloadCertificate}>
            Download Certificate (PDF)
          </button>
        )}
        {attemptsLeft > 0 && (
          <button className="btn secondary" onClick={onRetry}>
            Retry ({attemptsLeft} left)
          </button>
        )}
      </div>

      {!score.passed && quiz.certificateEnabled && (
        <p className="meta" style={{ marginTop: 16 }}>
          A certificate is available once you reach {quiz.passingPct}%.
        </p>
      )}
    </div>
  );
}
