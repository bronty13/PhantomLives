import { resolve } from 'node:path';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { viteSingleFile } from 'vite-plugin-singlefile';

// Creator app build. Emits a single self-contained dist/index.html.
// `base: './'` + inline-everything is what lets the result run from file://.
export default defineConfig({
  root: resolve(__dirname, 'src/creator'),
  base: './',
  plugins: [react(), viteSingleFile()],
  server: {
    port: 1500,
    // shared/ lives outside the creator root — allow the whole subproject.
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
