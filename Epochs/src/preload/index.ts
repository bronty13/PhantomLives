import { contextBridge } from 'electron'

// Minimal, safe surface exposed to the renderer. Grow as the UI needs it.
contextBridge.exposeInMainWorld('epochs', {
  version: '0.3.0',
})
