// Build the 9 descriptive classification axes from a ScoringOutput.
//
// These are a multi-axis *descriptive research profile only* — never a
// diagnosis, risk label, or any of the prohibited uses. Two axes are
// deliberately label-free:
//   • Stigma/disclosure strain (SDS) — continuous score only, avoid labels.
//   • Restricted sensitive module (SRI) — aggregate research analysis only;
//     it is NEVER emitted as an individual profile axis. We surface it here as
//     an explicit "withheld" entry so a reader sees it was intentionally not
//     computed, not merely forgotten.

import { ScoringOutput } from './engine'

export interface AxisResult {
  axis: string
  basis: string
  /** 0–100 where applicable, else null. */
  value: number | null
  /** Human-readable tag, or null when the axis is intentionally label-free. */
  tag: string | null
  note?: string
}

export function classify(s: ScoringOutput): AxisResult[] {
  const axes: AxisResult[] = []

  axes.push({
    axis: 'Interest breadth',
    basis: 'CIB count and percent',
    value: s.cib.value,
    tag: s.cib.eligible ? s.cib.tag : null,
    note: s.cib.eligible ? `${s.cib.count} theme(s) ≥ 2.0` : s.cib.note,
  })

  axes.push({
    axis: 'Interest intensity',
    basis: 'CII',
    value: s.cii.value,
    tag: s.cii.tag,
    note: s.cii.eligible ? undefined : s.cii.note,
  })

  axes.push({
    axis: 'Consensual practice',
    basis: 'CAP and max practice code',
    value: s.cap.value,
    tag: s.cap.eligible ? s.cap.tag : null,
    note: s.cap.eligible ? undefined : s.cap.note,
  })

  axes.push({
    axis: 'Role orientation',
    basis: 'TOP##_ROLE only',
    value: null,
    tag: s.role.tag,
  })

  axes.push({
    axis: 'Identity/community salience',
    basis: 'KIS plus contextual labels',
    value: s.kis.value,
    tag: s.kis.tag,
    note:
      s.noIdentityContext !== null && s.noIdentityContext >= 3
        ? 'Participant also endorsed a non-identity-oriented stance (contextual only).'
        : s.kis.eligible
          ? undefined
          : s.kis.note,
  })

  axes.push({
    axis: 'Consent-communication resources',
    basis: 'CCS',
    value: s.ccs.value,
    tag: s.ccs.tag,
    note: s.ccs.eligible ? undefined : s.ccs.note,
  })

  axes.push({
    axis: 'Personal impact',
    basis: 'DFI',
    value: s.dfi.value,
    tag: s.dfi.tag,
    note: s.dfi.eligible ? undefined : s.dfi.note,
  })

  axes.push({
    axis: 'Stigma/disclosure strain',
    basis: 'SDS',
    value: s.sds.value,
    tag: null, // continuous score only; avoid labels in participant view
    note: 'Continuous score only — not shame, pathology, or maladjustment.',
  })

  axes.push({
    axis: 'Restricted sensitive module',
    basis: 'SRI',
    value: null,
    tag: null,
    note: 'Withheld by design: aggregate research analysis only; never an individual profile axis.',
  })

  return axes
}
