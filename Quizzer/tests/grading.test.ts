import { describe, expect, it } from 'vitest';
import { gradeQuestion, gradeQuiz, normalize } from '../src/shared/grading';
import type {
  FillBlankQ,
  MultipleAnswerQ,
  MultipleChoiceQ,
  Question,
  ShortAnswerQ,
  TrueFalseQ,
} from '../src/shared/model';

const base = {
  promptHtml: '<p>q</p>',
  weight: 1,
  correctText: 'yes',
  incorrectText: 'no',
  showCorrectAnswer: true,
};

describe('normalize', () => {
  it('trims, collapses whitespace, lower-cases by default', () => {
    expect(normalize('  Hello   World  ')).toBe('hello world');
  });
  it('preserves case when case-sensitive', () => {
    expect(normalize('  Hello ', true)).toBe('Hello');
  });
});

describe('true/false', () => {
  const q: TrueFalseQ = { ...base, id: 'q', type: 'truefalse', correct: true };
  it('awards on match', () => {
    expect(gradeQuestion(q, { type: 'truefalse', value: true })).toMatchObject({ correct: true, awarded: 1 });
  });
  it('no credit on miss or null', () => {
    expect(gradeQuestion(q, { type: 'truefalse', value: false }).correct).toBe(false);
    expect(gradeQuestion(q, { type: 'truefalse', value: null }).correct).toBe(false);
  });
});

describe('multiple choice', () => {
  const q: MultipleChoiceQ = {
    ...base, id: 'q', type: 'mc', randomizeChoices: false,
    choices: [{ id: 'a', text: 'A' }, { id: 'b', text: 'B' }], correctChoiceId: 'b',
  };
  it('credits the right choice only', () => {
    expect(gradeQuestion(q, { type: 'mc', choiceId: 'b' }).correct).toBe(true);
    expect(gradeQuestion(q, { type: 'mc', choiceId: 'a' }).correct).toBe(false);
    expect(gradeQuestion(q, { type: 'mc', choiceId: null }).correct).toBe(false);
  });
});

describe('multiple answer (all-or-nothing)', () => {
  const q: MultipleAnswerQ = {
    ...base, id: 'q', type: 'multi', randomizeChoices: false, weight: 2,
    choices: [{ id: 'a', text: 'A' }, { id: 'b', text: 'B' }, { id: 'c', text: 'C' }],
    correctChoiceIds: ['a', 'c'],
  };
  it('full credit on exact set match (order-independent)', () => {
    expect(gradeQuestion(q, { type: 'multi', choiceIds: ['c', 'a'] })).toMatchObject({ correct: true, awarded: 2 });
  });
  it('zero on partial / superset / dupes', () => {
    expect(gradeQuestion(q, { type: 'multi', choiceIds: ['a'] }).awarded).toBe(0);
    expect(gradeQuestion(q, { type: 'multi', choiceIds: ['a', 'b', 'c'] }).awarded).toBe(0);
    expect(gradeQuestion(q, { type: 'multi', choiceIds: ['a', 'a'] }).awarded).toBe(0);
  });
});

describe('fill in the blank (proportional)', () => {
  const q: FillBlankQ = {
    ...base, id: 'q', type: 'fill', caseSensitive: false, weight: 2,
    blanks: [
      { id: 'b1', accepted: ['paris'] },
      { id: 'b2', accepted: ['france', 'the french republic'] },
    ],
  };
  it('full credit when all blanks match (trim/case/multi-accept)', () => {
    const r = gradeQuestion(q, { type: 'fill', answers: { b1: '  Paris ', b2: 'The French Republic' } });
    expect(r).toMatchObject({ correct: true, awarded: 2 });
  });
  it('proportional credit when some blanks match', () => {
    const r = gradeQuestion(q, { type: 'fill', answers: { b1: 'paris', b2: 'germany' } });
    expect(r.correct).toBe(false);
    expect(r.awarded).toBe(1); // 1 of 2 blanks * weight 2 / 2
  });
  it('respects case sensitivity', () => {
    const cs: FillBlankQ = { ...q, caseSensitive: true, blanks: [{ id: 'b1', accepted: ['Paris'] }] };
    expect(gradeQuestion(cs, { type: 'fill', answers: { b1: 'paris' } }).correct).toBe(false);
    expect(gradeQuestion(cs, { type: 'fill', answers: { b1: 'Paris' } }).correct).toBe(true);
  });
});

describe('short answer', () => {
  it('keyword grading needs minMatches', () => {
    const q: ShortAnswerQ = {
      ...base, id: 'q', type: 'short', mode: 'paragraph',
      grading: { kind: 'keyword', keywords: ['mitochondria', 'energy'], minMatches: 2 },
    };
    expect(gradeQuestion(q, { type: 'short', text: 'The mitochondria makes energy' }).correct).toBe(true);
    expect(gradeQuestion(q, { type: 'short', text: 'The mitochondria' }).correct).toBe(false);
  });
  it('manual grading is auto-credited and self-graded', () => {
    const q: ShortAnswerQ = { ...base, id: 'q', type: 'short', mode: 'text', grading: { kind: 'manual' } };
    expect(gradeQuestion(q, { type: 'short', text: 'anything' })).toMatchObject({ correct: true, awarded: 1, selfGraded: true });
    expect(gradeQuestion(q, undefined)).toMatchObject({ correct: true, selfGraded: true });
  });
});

describe('mismatched / missing responses', () => {
  const q: TrueFalseQ = { ...base, id: 'q', type: 'truefalse', correct: true };
  it('wrong-type response scores zero', () => {
    expect(gradeQuestion(q, { type: 'mc', choiceId: 'b' }).awarded).toBe(0);
    expect(gradeQuestion(q, undefined).awarded).toBe(0);
  });
});

describe('gradeQuiz', () => {
  const questions: Question[] = [
    { ...base, id: 'q1', type: 'truefalse', correct: true },
    { ...base, id: 'q2', type: 'mc', randomizeChoices: false, choices: [{ id: 'a', text: 'A' }, { id: 'b', text: 'B' }], correctChoiceId: 'a', weight: 3 },
  ];
  it('aggregates weighted score and pass/fail', () => {
    const score = gradeQuiz(questions, { q1: { type: 'truefalse', value: true }, q2: { type: 'mc', choiceId: 'b' } }, 80);
    expect(score.awarded).toBe(1);
    expect(score.max).toBe(4);
    expect(score.pct).toBe(25);
    expect(score.passed).toBe(false);
  });
  it('passes at threshold', () => {
    const score = gradeQuiz(questions, { q1: { type: 'truefalse', value: true }, q2: { type: 'mc', choiceId: 'a' } }, 80);
    expect(score.pct).toBe(100);
    expect(score.passed).toBe(true);
  });
});
