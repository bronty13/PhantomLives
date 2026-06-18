import { defineConfig } from 'vitest/config';

// jsdom so DOMPurify and the round-trip import (DOMParser) work. Tests exercise the
// pure core: serializers, font-mark coalescing, button URL matchers, emoji
// detection, char counting, and version comparison.
export default defineConfig({
  test: {
    globals: true,
    environment: 'jsdom',
    include: ['tests/**/*.test.ts', 'tests/**/*.test.tsx'],
  },
});
