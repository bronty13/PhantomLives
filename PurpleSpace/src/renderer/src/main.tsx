import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { ConvexProvider, ConvexReactClient } from 'convex/react';
import type { BackendStatus } from '../../shared/types';
import App from './App';

import '@fontsource/schibsted-grotesk/400.css';
import '@fontsource/schibsted-grotesk/500.css';
import '@fontsource/schibsted-grotesk/600.css';
import '@fontsource/newsreader/400.css';
import '@fontsource/newsreader/500.css';
import '@fontsource/newsreader/600.css';
import '@fontsource/newsreader/400-italic.css';
import '@fontsource/jetbrains-mono/400.css';
import '@fontsource/jetbrains-mono/500.css';
import './styles/tokens.css';
import './styles/app.css';

function Splash({ status }: { status: BackendStatus }): React.JSX.Element {
  return (
    <div className="splash">
      <div className="splash-glyph">Purple Space</div>
      {status.state === 'error' ? (
        <div className="splash-error">
          The workspace backend failed to start: {status.error}
          <br />
          Check ~/Library/Application Support/Purple Space/logs/convex-backend.log
        </div>
      ) : (
        <div className="splash-text">Opening your workspace…</div>
      )}
    </div>
  );
}

function Bootstrap(): React.JSX.Element {
  const [status, setStatus] = useState<BackendStatus | null>(null);
  const [client, setClient] = useState<ConvexReactClient | null>(null);

  useEffect(() => {
    let alive = true;
    const apply = (s: BackendStatus): void => {
      if (!alive) return;
      setStatus(s);
      if (s.state === 'ready') {
        setClient((prev) => prev ?? new ConvexReactClient(s.url));
      }
    };
    void window.purpleSpace.getBackendStatus().then(apply);
    const unsub = window.purpleSpace.onBackendStatus(apply);
    return () => {
      alive = false;
      unsub();
    };
  }, []);

  if (!client || !status || status.state !== 'ready') {
    return (
      <Splash
        status={status ?? { state: 'starting', url: '', siteUrl: '' }}
      />
    );
  }
  return (
    <ConvexProvider client={client}>
      <App />
    </ConvexProvider>
  );
}

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <Bootstrap />
  </React.StrictMode>
);
