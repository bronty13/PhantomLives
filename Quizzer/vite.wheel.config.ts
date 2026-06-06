import { resolve } from 'node:path';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { viteSingleFile } from 'vite-plugin-singlefile';

// Spin-the-Wheel player build. Emits a single self-contained dist-wheel/index.html
// that reads its wheel from window.__QUIZ__ (never fetch — must work under file://).
// scripts/embed-wheel.mjs then turns that HTML into a string the creator imports.
export default defineConfig({
  root: resolve(__dirname, 'src/wheel-player'),
  base: './',
  plugins: [react(), viteSingleFile()],
  server: {
    port: 1502,
    fs: { allow: [resolve(__dirname)] },
  },
  build: {
    target: 'es2020',
    outDir: resolve(__dirname, 'dist-wheel'),
    emptyOutDir: true,
    cssCodeSplit: false,
    assetsInlineLimit: 100_000_000,
    modulePreload: false,
    reportCompressedSize: false,
  },
});
