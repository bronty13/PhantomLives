import React from 'react';
import { createRoot } from 'react-dom/client';
import './player.css';
import { App } from './App';
import { loadPlayerData } from './bootstrap';

const data = loadPlayerData();

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App data={data} />
  </React.StrictMode>,
);
