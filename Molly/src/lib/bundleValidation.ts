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

// ---------------------------------------------------------------------------
// Custom-bundle rules (mirror src-tauri/src/bundles.rs::validate_custom_*)
// ---------------------------------------------------------------------------

export function validateCustomDelivery(bundle: Bundle): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  const kind = bundle.deliveryKind;
  if (kind == null) {
    issues.push({
      fieldPath: 'delivery',
      message: 'Pick a delivery method (Site or URL link).',
      severity: 'error',
      jumpToFieldId: 'bundle-delivery',
    });
  } else if (kind === 'site' && bundle.deliverySiteId == null) {
    issues.push({
      fieldPath: 'delivery',
      message: 'Pick a site for this persona.',
      severity: 'error',
      jumpToFieldId: 'bundle-delivery-site',
    });
  }
  // kind === 'url' needs no further input — Robert fills the URL in via
  // the SideMolly return-file flow once the bundle has been delivered.
  if (bundle.deliveryRecipient.trim().length === 0) {
    issues.push({
      fieldPath: 'delivery.recipient',
      message: 'Who is this for? Add a recipient name / username.',
      severity: 'error',
      jumpToFieldId: 'bundle-delivery-recipient',
    });
  }
  if (!bundle.handledInPlatform) {
    if (bundle.priceCents == null) {
      issues.push({
        fieldPath: 'price',
        message: 'Set a price (or tick "handled in delivery platform").',
        severity: 'error',
        jumpToFieldId: 'bundle-price',
      });
    } else if (bundle.priceCents < 0) {
      issues.push({
        fieldPath: 'price',
        message: "Price can't be negative.",
        severity: 'error',
        jumpToFieldId: 'bundle-price',
      });
    }
  }
  return issues;
}

export function validateCustomBundle(bundle: Bundle, ctx: ValidationCtx): ValidationIssue[] {
  return [
    ...validateTitle(bundle.summary.title),
    ...validatePersona(bundle.summary.personaCode),
    ...validateGoLiveDate(bundle.summary.goLiveDate, ctx.today),
    ...validateContentFiles(bundle.files),
    ...validateCustomDelivery(bundle),
  ];
}

// ---------------------------------------------------------------------------
// FanSite rules (mirror src-tauri/src/bundles.rs::validate_fansite_*)
// ---------------------------------------------------------------------------

export function daysInMonth(year: number, month: number): number {
  if (month < 1 || month > 12) return 0;
  // Date(year, month, 0) → last day of (month-1+1) = month, JS month 0-indexed.
  return new Date(year, month, 0).getDate();
}

export function validateFanSiteCompletion(bundle: Bundle): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  if (bundle.fansiteYear == null || bundle.fansiteMonth == null) {
    issues.push({
      fieldPath: 'fansiteMonth',
      message: 'Pick a month and year to plan posts for.',
      severity: 'error',
      jumpToFieldId: 'bundle-fansite-month',
    });
    return issues;
  }
  const total = daysInMonth(bundle.fansiteYear, bundle.fansiteMonth);
  if (total === 0) {
    issues.push({
      fieldPath: 'fansiteMonth',
      message: `Month ${bundle.fansiteMonth} doesn't look right (need 1-12).`,
      severity: 'error',
      jumpToFieldId: 'bundle-fansite-month',
    });
    return issues;
  }
  const byDay = new Map(bundle.fanDays.map((d) => [d.dayOfMonth, d]));
  for (let day = 1; day <= total; day++) {
    const entry = byDay.get(day);
    const hasMessage = !!entry && entry.message.trim().length > 0;
    const hasFile = !!entry && entry.fileCount >= 1;
    if (!hasMessage || !hasFile) {
      const missing = !hasMessage && !hasFile
        ? 'needs a message and a file'
        : !hasMessage
        ? 'needs a message'
        : 'needs a file';
      const dd = String(day).padStart(2, '0');
      issues.push({
        fieldPath: `fanDay.${dd}`,
        message: `Day ${dd} ${missing}.`,
        severity: 'error',
        jumpToFieldId: `bundle-fan-day-${dd}`,
      });
    }
  }
  return issues;
}

export function validateFanSiteBundle(bundle: Bundle): ValidationIssue[] {
  return [
    ...validateTitle(bundle.summary.title),
    ...validatePersona(bundle.summary.personaCode),
    ...validateFanSiteCompletion(bundle),
  ];
}

/** Public dispatch — picks the per-type rule set. */
export function validateBundle(bundle: Bundle, ctx: ValidationCtx): ValidationIssue[] {
  switch (bundle.summary.bundleType) {
    case 'content':
      return validateContentBundle(bundle, ctx);
    case 'custom':
      return validateCustomBundle(bundle, ctx);
    case 'fansite':
      return validateFanSiteBundle(bundle);
  }
}

export function hasBlockingIssues(issues: ValidationIssue[]): boolean {
  return issues.some((i) => i.severity === 'error');
}
