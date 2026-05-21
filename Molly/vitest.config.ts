import { defineConfig } from 'vitest/config';

// Vitest config kept separate from vite.config.ts so the app build
// doesn't pull in the test runner. Run with `pnpm test` (one-shot) or
// `pnpm test:watch` (interactive).
//
// Default environment is `node` — every test file in this repo so far
// exercises pure functions (money, phone, cadence, uid date helper).
// If we ever add component tests that need a DOM, flip the env to
// `jsdom` and add `@testing-library/react` then.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts', 'src/**/*.test.tsx'],
    // Exclude the rest of the world; vitest's default also walks
    // node_modules slowly without this.
    exclude: ['node_modules', 'dist', 'src-tauri', '.git'],
  },
});
