import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { viteSingleFile } from 'vite-plugin-singlefile'

// Builds a single self-contained dist/index.html (all JS/CSS + the embedded
// instrument JSON inlined) so the SPA can be distributed and run offline by
// double-clicking — no server, no external asset requests.
export default defineConfig({
  plugins: [react(), viteSingleFile()],
  test: {
    globals: true,
    environment: 'node',
  },
})
