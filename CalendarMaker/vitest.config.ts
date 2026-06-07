import { defineConfig } from 'vitest/config';

// jsdom so jsPDF / btoa / DOM measurement work; tests exercise the pure core
// (grid math, holiday resolution incl. easter, fit/overflow, bundle IO, PDF build).
export default defineConfig({
  test: {
    globals: true,
    environment: 'jsdom',
    include: ['tests/**/*.test.ts', 'tests/**/*.test.tsx'],
  },
});
