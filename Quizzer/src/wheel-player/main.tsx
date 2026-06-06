import React from 'react';
import { createRoot } from 'react-dom/client';
import './wheel.css';
import { App } from './App';
import { loadWheelData } from './bootstrap';

const data = loadWheelData();

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App data={data} />
  </React.StrictMode>,
);
