import { resolve } from 'node:path';
import { defineConfig, externalizeDepsPlugin } from 'electron-vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  main: {
    // d3-hierarchy and xxhash-wasm are ESM-only; the main bundle is CJS and
    // cannot require() them. Exclude them from externalization so Vite bundles
    // (and transpiles) them into the output instead.
    plugins: [externalizeDepsPlugin({ exclude: ['d3-hierarchy', 'xxhash-wasm'] })],
    build: {
      rollupOptions: {
        // Two entry points: the main process (`index`) and the filesystem
        // scan worker (`scanWorker`). electron-vite emits each as its own
        // file under out/main/, so the worker is spawnable via
        // `new Worker(join(__dirname, 'scanWorker.js'))`.
        input: {
          index: resolve(__dirname, 'src/main/index.ts'),
          scanWorker: resolve(__dirname, 'src/main/scan/scanWorker.ts')
        }
      }
    }
  },
  preload: {
    plugins: [externalizeDepsPlugin()],
    build: {
      rollupOptions: {
        input: { index: resolve(__dirname, 'src/preload/index.ts') }
      }
    }
  },
  renderer: {
    root: resolve(__dirname, 'src/renderer'),
    resolve: {
      alias: { '@': resolve(__dirname, 'src/renderer/src') }
    },
    plugins: [react()],
    build: {
      rollupOptions: {
        input: { index: resolve(__dirname, 'src/renderer/index.html') }
      }
    }
  }
});
