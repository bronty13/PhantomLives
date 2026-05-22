// Phase 9 — frontend validation rules for the Content Bundler.
//
// Mirrors src-tauri/src/bundles.rs::validate_* (the server is authoritative
// on publish). Used in two places on the JS side:
//   1. Live feedback under each form field as Sallie types.
//   2. The PublishWizard's pre-publish checklist (it also re-runs server
//      validation; this just gives a smoother UX before the round trip).

import type { Bundle, BundleCategory, BundleFileInfo, Severity } from '../data/bundles';

export interface ValidationIssue {
  fieldPath: string;
  message: string;
  severity: Severity;
  jumpToFieldId: string;
}

export interface ValidationCtx {
  today: Date;
  prohibitedWords: string[]; // lowercase preferred but we lowercase anyway
}

const PLACEHOLDER_TITLES = ['none', 'blank', 'custom'];

export function validateTitle(title: string): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  const trimmed = title.trim();
  if (trimmed.length === 0) {
    issues.push({
      fieldPath: 'title',
      message: "Title can't be blank.",
      severity: 'error',
      jumpToFieldId: 'bundle-title',
    });
    return issues;
  }
  const lower = trimmed.toLowerCase();
  if (PLACEHOLDER_TITLES.includes(lower)) {
    issues.push({
      fieldPath: 'title',
      message: `Title can't be a placeholder (${trimmed}).`,
      severity: 'error',
      jumpToFieldId: 'bundle-title',
    });
  }
  const words = trimmed.split(/\s+/).filter((s) => s.length > 0).length;
  if (words < 2) {
    issues.push({
      fieldPath: 'title',
      message: 'Title needs at least two words.',
      severity: 'error',
      jumpToFieldId: 'bundle-title',
    });
  }
  return issues;
}

export function validatePersona(persona: string | null | undefined): ValidationIssue[] {
  if (!persona) {
    return [
      {
        fieldPath: 'persona',
        message: 'Persona is required.',
        severity: 'error',
        jumpToFieldId: 'bundle-persona',
      },
    ];
  }
  return [];
}

function isoDate(d: Date): string {
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

function parseIsoDate(s: string): Date | null {
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!m) return null;
  // Local midnight; we compare as dates not instants.
  const d = new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10));
  // Sanity-check that the input round-trips (Sep 31 → Oct 1, etc.)
  return isoDate(d) === s ? d : null;
}

function daysBetween(a: Date, b: Date): number {
  const ms = b.getTime() - a.getTime();
  return Math.floor(ms / (1000 * 60 * 60 * 24));
}

export function validateGoLiveDate(
  goLive: string | null | undefined,
  today: Date,
): ValidationIssue[] {
  if (!goLive) {
    return [
      {
        fieldPath: 'goLiveDate',
        message: 'Go-live date is required.',
        severity: 'error',
        jumpToFieldId: 'bundle-go-live',
      },
    ];
  }
  const parsed = parseIsoDate(goLive);
  if (!parsed) {
    return [
      {
        fieldPath: 'goLiveDate',
        message: "Go-live date isn't a valid YYYY-MM-DD.",
        severity: 'error',
        jumpToFieldId: 'bundle-go-live',
      },
    ];
  }
  const todayOnly = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const diff = daysBetween(todayOnly, parsed);
  if (diff < 0) {
    return [
      {
        fieldPath: 'goLiveDate',
        message: "Go-live date can't be in the past.",
        severity: 'error',
        jumpToFieldId: 'bundle-go-live',
      },
    ];
  }
  if (diff <= 5) {
    return [
      {
        fieldPath: 'goLiveDate',
        message: 'Are you allowing enough time for editing?',
        severity: 'warn',
        jumpToFieldId: 'bundle-go-live',
      },
    ];
  }
  return [];
}

export function validateContentDescription(
  text: string,
  audioRelpath: string | null | undefined,
  prohibitedWords: string[],
): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  const hasText = text.trim().length > 0;
  const hasAudio = !!audioRelpath;
  if (!hasText && !hasAudio) {
    issues.push({
      fieldPath: 'description',
      message: 'Add a text description or upload an audio file.',
      severity: 'error',
      jumpToFieldId: 'bundle-description',
    });
  }
  if (hasText && hasAudio) {
    issues.push({
      fieldPath: 'description',
      message: 'Pick one — text or audio, not both.',
      severity: 'error',
      jumpToFieldId: 'bundle-description',
    });
  }
  if (hasText) {
    const lower = text.toLowerCase();
    for (const word of prohibitedWords) {
      const w = word.toLowerCase();
      if (w.length === 0) continue;
      if (lower.includes(w)) {
        issues.push({
          fieldPath: 'description.text',
          message: `Description contains prohibited word: '${word}'.`,
          severity: 'error',
          jumpToFieldId: 'bundle-description-text',
        });
      }
    }
  }
  return issues;
}

export function validateCategories(categories: BundleCategory[]): ValidationIssue[] {
  if (categories.length < 3) {
    return [
      {
        fieldPath: 'categories',
        message: `Pick at least 3 categories (you have ${categories.length}).`,
        severity: 'error',
        jumpToFieldId: 'bundle-categories',
      },
    ];
  }
  return [];
}

export function validateContentFiles(files: BundleFileInfo[]): ValidationIssue[] {
  const media = files.filter((f) => f.kind === 'video' || f.kind === 'image');
  if (media.length === 0) {
    return [
      {
        fieldPath: 'files',
        message: 'Upload at least one video or image.',
        severity: 'error',
        jumpToFieldId: 'bundle-files',
      },
    ];
  }
  return [];
}

/** Validate a Content bundle against all rules. Returns full issue list. */
export function validateContentBundle(bundle: Bundle, ctx: ValidationCtx): ValidationIssue[] {
  return [
    ...validateTitle(bundle.summary.title),
    ...validatePersona(bundle.summary.personaCode),
    ...validateGoLiveDate(bundle.summary.goLiveDate, ctx.today),
    ...validateContentDescription(
      bundle.descriptionText,
      bundle.descriptionAudioRelpath,
      ctx.prohibitedWords,
    ),
    ...validateCategories(bundle.categories),
    ...validateContentFiles(bundle.files),
  ];
}

/** Public dispatch — picks the per-type rule set. PR2 will add Custom + FanSite. */
export function validateBundle(bundle: Bundle, ctx: ValidationCtx): ValidationIssue[] {
  switch (bundle.summary.bundleType) {
    case 'content':
      return validateContentBundle(bundle, ctx);
    case 'custom':
    case 'fansite':
      // Defer to PR2. For now we return a single advisory issue so the UI
      // surfaces something useful when someone tries to publish.
      return [
        {
          fieldPath: 'bundleType',
          message: `Publishing for '${bundle.summary.bundleType}' bundles arrives in a later release.`,
          severity: 'error',
          jumpToFieldId: 'bundle-type',
        },
      ];
  }
}

export function hasBlockingIssues(issues: ValidationIssue[]): boolean {
  return issues.some((i) => i.severity === 'error');
}
