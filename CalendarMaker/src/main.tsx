import React from 'react';
import ReactDOM from 'react-dom/client';
import { App } from './app/App';
import { allFontFaceCss } from './data/fonts';
import './app.css';

// Inject @font-face rules for every embedded font (offline, base64) so the
// on-screen preview uses the exact same glyphs the PDF will embed.
const fontStyle = document.createElement('style');
fontStyle.textContent = allFontFaceCss();
document.head.appendChild(fontStyle);

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
