import { resolve } from 'node:path';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { viteSingleFile } from 'vite-plugin-singlefile';

// Player build. Emits a single self-contained dist-player/index.html that reads
// its quiz from window.__QUIZ__ (never fetch — must work under file://).
// scripts/embed-player.mjs then turns that HTML into a string the creator imports.
export default defineConfig({
  root: resolve(__dirname, 'src/player'),
  base: './',
  plugins: [react(), viteSingleFile()],
  server: {
    port: 1501,
    fs: { allow: [resolve(__dirname)] },
  },
  build: {
    target: 'es2020',
    outDir: resolve(__dirname, 'dist-player'),
    emptyOutDir: true,
    cssCodeSplit: false,
    assetsInlineLimit: 100_000_000,
    modulePreload: false,
    reportCompressedSize: false,
  },
});
