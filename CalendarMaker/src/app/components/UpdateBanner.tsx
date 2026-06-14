import { useEffect, useState } from 'react';
import { APP_VERSION } from '../../model/types';
import { isNewer } from '../../update/version';

/**
 * On load, best-effort fetch a `version.json` next to the app (written at deploy
 * time) and, if it advertises a newer version, show a big one-tap "update" banner.
 * Silent on failure (offline / opened from a file) so it never gets in the way.
 */
export function UpdateBanner() {
  const [latest, setLatest] = useState<string | null>(null);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        // Relative to the current page → resolves next to index.html when hosted.
        const url = new URL('version.json', window.location.href);
        url.searchParams.set('_', String(Date.now())); // bypass caches
        const ctrl = new AbortController();
        const timer = setTimeout(() => ctrl.abort(), 6000);
        const res = await fetch(url.toString(), { signal: ctrl.signal, cache: 'no-store' });
        clearTimeout(timer);
        if (!res.ok) return;
        const data = (await res.json()) as { version?: string };
        if (!cancelled && data?.version && isNewer(data.version, APP_VERSION)) {
          setLatest(data.version);
        }
      } catch {
        /* offline, file://, or no manifest — ignore */
      }
    })();
    return () => { cancelled = true; };
  }, []);

  if (!latest || dismissed) return null;

  return (
    <div
      role="alert"
      style={{
        background: '#1f6f43',
        color: '#fff',
        padding: '12px 16px',
        display: 'flex',
        alignItems: 'center',
        gap: 12,
        fontSize: 17,
        flexWrap: 'wrap',
        justifyContent: 'center',
      }}
    >
      <span>✨ A newer version of CalendarMaker is ready.</span>
      <button
        className="primary"
        style={{ fontSize: 17, padding: '8px 20px' }}
        onClick={() => window.location.reload()}
      >
        Update now
      </button>
      <button
        className="ghost"
        style={{ color: '#fff', textDecoration: 'underline' }}
        onClick={() => setDismissed(true)}
      >
        Later
      </button>
    </div>
  );
}
