import { resolve } from 'node:path';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { viteSingleFile } from 'vite-plugin-singlefile';

// NFEditor is a single self-contained SPA. `base: './'` + inline-everything lets
// dist/index.html run both from GitHub Pages (one bookmarkable URL, updates on
// refresh) and from a saved file:// copy. Same shape as the sibling CalendarMaker.
export default defineConfig({
  root: resolve(__dirname, 'src'),
  base: './',
  plugins: [react(), viteSingleFile()],
  server: {
    port: 1540,
    fs: { allow: [resolve(__dirname)] },
  },
  build: {
    target: 'es2020',
    outDir: resolve(__dirname, 'dist'),
    emptyOutDir: true,
    cssCodeSplit: false,
    assetsInlineLimit: 100_000_000,
    modulePreload: false,
    reportCompressedSize: false,
  },
});
