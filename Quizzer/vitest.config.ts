import { defineConfig } from 'vitest/config';

// Tests run in jsdom so DOMPurify / jsPDF / btoa all work, and exercise the pure
// shared core (grading, obfuscation, deploy injection, zip assembly).
export default defineConfig({
  test: {
    globals: true,
    environment: 'jsdom',
    include: ['tests/**/*.test.ts', 'tests/**/*.test.tsx'],
  },
});
