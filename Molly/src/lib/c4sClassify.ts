/**
 * Map a Clips4Sale `Performers` value to a Molly persona code.
 *
 * Sallie's two stores hardcode their persona identity into the Performers
 * column: `CoC` for Curse Of Curves, `PrincessOFAddiction` for Princess of
 * Addiction. The export filenames also hint (`coc_clips-export-…`,
 * `poa_clips-export-…`) but the user-facing wizard prefers the column
 * value because it's the canonical signal — filenames get renamed.
 *
 * Returns null when the value doesn't match any known mapping; the
 * wizard surfaces that as an "I'm not sure which store this is" path and
 * asks the user to pick manually.
 */
export type PersonaCode = 'CoC' | 'PoA';

export function performersToPersonaCode(raw: string | undefined | null): PersonaCode | null {
  if (!raw) return null;
  const normalized = raw.trim().toLowerCase().replace(/[\s_-]/g, '');
  if (normalized === 'coc') return 'CoC';
  if (normalized === 'curseofcurves') return 'CoC';
  if (normalized === 'princessofaddiction') return 'PoA';
  if (normalized === 'poa') return 'PoA';
  return null;
}

/**
 * Guess a persona from the first row of a parsed C4S export. Looks at the
 * `Performers` field. Returns null when the column is missing or the
 * value isn't recognized.
 */
export function detectPersonaFromRows(
  rows: ReadonlyArray<Record<string, string>>,
): PersonaCode | null {
  for (const row of rows) {
    const guess = performersToPersonaCode(row['Performers']);
    if (guess) return guess;
  }
  return null;
}

export function personaDisplayName(code: PersonaCode): string {
  return code === 'CoC' ? 'Curse Of Curves' : 'Princess of Addiction';
}
