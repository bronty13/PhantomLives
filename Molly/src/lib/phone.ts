// US phone formatting + validation. International numbers (when the
// customer's country isn't US) bypass this — they're treated as free text.

/** Strip non-digits and drop a leading "1" country code if the rest is 10+ digits. */
export function usPhoneDigits(value: string): string {
  const digits = value.replace(/\D/g, '');
  return digits.length > 10 && digits.startsWith('1') ? digits.slice(1) : digits;
}

/**
 * Format a US phone as the user types. Returns canonical
 * `(XXX) XXX-XXXX` once 10 digits are present; partial inputs render
 * the prefix of that pattern. Anything beyond 10 digits is treated as
 * an extension and appended as ` xNNN`.
 */
export function formatUSPhone(input: string): string {
  const digits = input.replace(/\D/g, '');
  if (!digits) return '';
  // Drop leading 1 if the user pasted "1-555-..." or "+1 555 ...".
  const core = digits.length > 10 && digits.startsWith('1') ? digits.slice(1) : digits;
  const a = core.slice(0, 3);
  const b = core.slice(3, 6);
  const c = core.slice(6, 10);
  const ext = core.slice(10);
  if (core.length <= 3) return `(${a}`;
  if (core.length <= 6) return `(${a}) ${b}`;
  if (core.length <= 10) return `(${a}) ${b}${c ? `-${c}` : ''}`;
  return `(${a}) ${b}-${c} x${ext}`;
}

/** A US phone is valid when its digit-only form is exactly 10 digits. */
export function isValidUSPhone(value: string): boolean {
  return usPhoneDigits(value).length === 10;
}
