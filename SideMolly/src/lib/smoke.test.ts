import { describe, it, expect } from 'vitest';

// Phase 0 — keeps the vitest counter > 0 so `pnpm test` reports a number
// instead of "no tests found." First real tests land alongside Phase 1
// (bundle ingest + hashes.json verification).
describe('phase 0 smoke', () => {
  it('runs', () => {
    expect(1 + 1).toBe(2);
  });
});
