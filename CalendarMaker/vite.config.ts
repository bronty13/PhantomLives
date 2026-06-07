import { resolve } from 'node:path';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { viteSingleFile } from 'vite-plugin-singlefile';

// CalendarMaker is a single self-contained SPA: editor + PDF exporter in one file.
// `base: './'` + inline-everything is what lets dist/index.html run from file://
// (browsers block fetch() of sibling files from file://, so all data/fonts inline).
export default defineConfig({
  root: resolve(__dirname, 'src'),
  base: './',
  plugins: [react(), viteSingleFile()],
  server: {
    port: 1530,
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
