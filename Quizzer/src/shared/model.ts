// Quizzer data model — the single source of truth shared by the creator and the
// deployed player. Keep this dependency-free so both bundles can import it cheaply.

export type ID = string;

/** Schema version stamped into exported/deployed artifacts for forward-compat. */
export const SCHEMA_VERSION = 1;

// ---------------------------------------------------------------------------
// Assets
// ---------------------------------------------------------------------------

/**
 * A reference to a binary asset (logo, font, intro media).
 * - `inline` carries a base64 data-URI (single-file deploy, or stored in the creator).
 * - `file` carries a relative path (zip deploy externalizes large assets to assets/).
 * The player resolves either shape to a valid element `src` — never via fetch().
 */
export type AssetRef =
  | { kind: 'inline'; mime: string; dataUri: string; name?: string }
  | { kind: 'file'; mime: string; path: string; name?: string };

// ---------------------------------------------------------------------------
// Branding
// ---------------------------------------------------------------------------

export interface BrandColors {
  primary: string;
  secondary: string;
  accent: string;
  bg: string;
  text: string;
}

export type FontChoice =
  | { kind: 'builtin'; family: BuiltinFontName }
  | { kind: 'custom'; family: string; ttf: AssetRef };

/** The ten bundled, offline web fonts the user can pick without uploading a TTF. */
export type BuiltinFontName =
  | 'Inter'
  | 'Lora'
  | 'Roboto'
  | 'Merriweather'
  | 'Montserrat'
  | 'Open Sans'
  | 'Playfair Display'
  | 'Source Serif 4'
  | 'Nunito'
  | 'JetBrains Mono';

export const BUILTIN_FONT_NAMES: BuiltinFontName[] = [
  'Inter',
  'Lora',
  'Roboto',
  'Merriweather',
  'Montserrat',
  'Open Sans',
  'Playfair Display',
  'Source Serif 4',
  'Nunito',
  'JetBrains Mono',
];

export interface Branding {
  id: ID;
  name: string;
  colors: BrandColors;
  logo?: AssetRef;
  font: FontChoice;
  updatedAt: number;
}

// ---------------------------------------------------------------------------
// Global settings (defaults applied to new quizzes)
// ---------------------------------------------------------------------------

export interface GlobalSettings {
  defaultTimeLimitSec: number; // 1800 (00:30:00)
  defaultAttempts: number; // 3
  defaultRandomizeQuestions: boolean; // false
  defaultPassingPct: number; // 80
  defaultCorrectText: string;
  defaultIncorrectText: string;
}

export const DEFAULT_CORRECT_TEXT = "Correct, That's Right!";
export const DEFAULT_INCORRECT_TEXT = 'Incorrect. Sorry That is not the Correct Answer.';

export const DEFAULT_GLOBAL_SETTINGS: GlobalSettings = {
  defaultTimeLimitSec: 1800,
  defaultAttempts: 3,
  defaultRandomizeQuestions: false,
  defaultPassingPct: 80,
  defaultCorrectText: DEFAULT_CORRECT_TEXT,
  defaultIncorrectText: DEFAULT_INCORRECT_TEXT,
};

// ---------------------------------------------------------------------------
// Questions
// ---------------------------------------------------------------------------

export type QuestionType = 'truefalse' | 'mc' | 'multi' | 'fill' | 'short';

export interface QuestionBase {
  id: ID;
  promptHtml: string;
  /** Optional image shown between the question text and the answer choices. */
  image?: AssetRef;
  weight: number; // default 1
  correctText: string;
  incorrectText: string;
  showCorrectAnswer: boolean;
}

export interface Choice {
  id: ID;
  text: string;
}

export interface TrueFalseQ extends QuestionBase {
  type: 'truefalse';
  correct: boolean;
}

export interface MultipleChoiceQ extends QuestionBase {
  type: 'mc';
  choices: Choice[]; // 2..10
  correctChoiceId: ID;
  randomizeChoices: boolean;
}

export interface MultipleAnswerQ extends QuestionBase {
  type: 'multi';
  choices: Choice[]; // 2..10
  correctChoiceIds: ID[];
  randomizeChoices: boolean;
}

export interface FillBlank {
  id: ID;
  accepted: string[]; // 1+ accepted answers for this blank
}

export interface FillBlankQ extends QuestionBase {
  type: 'fill';
  blanks: FillBlank[]; // 1+ blanks
  caseSensitive: boolean;
}

export type ShortAnswerGrading =
  | { kind: 'keyword'; keywords: string[]; minMatches: number }
  | { kind: 'manual' };

export interface ShortAnswerQ extends QuestionBase {
  type: 'short';
  mode: 'text' | 'paragraph';
  grading: ShortAnswerGrading;
}

export type Question =
  | TrueFalseQ
  | MultipleChoiceQ
  | MultipleAnswerQ
  | FillBlankQ
  | ShortAnswerQ;

// ---------------------------------------------------------------------------
// Quiz
// ---------------------------------------------------------------------------

export interface Quiz {
  id: ID;
  name: string;
  introHtml: string;
  instructionsHtml?: string;
  introMedia?: AssetRef;
  timeLimitSec?: number; // undefined => no time limit
  attempts: number;
  randomizeQuestions: boolean;
  passingPct: number;
  certificateEnabled: boolean;
  brandingId: ID;
  questions: Question[];
  createdAt: number;
  updatedAt: number;
}

/** A quiz bundled with its resolved branding — the unit we export/import/deploy. */
export interface QuizBundle {
  schemaVersion: number;
  quiz: Quiz;
  branding: Branding;
}

// ---------------------------------------------------------------------------
// Grading-semantics constants (documented, testable defaults)
// ---------------------------------------------------------------------------

/** Multiple-answer questions award full credit only on an exact set match. */
export const MULTI_ALL_OR_NOTHING = true;
/** Fill-in-the-blank awards proportional credit across blanks. */
export const FILL_PROPORTIONAL = true;
/**
 * Short-answer `manual` grading has no human grader in a deployed quiz, so it is
 * auto-credited and surfaced to the respondent as "self-graded".
 */
export const SHORT_MANUAL_AUTO_CREDIT = true;
