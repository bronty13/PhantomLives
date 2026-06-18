import { useEffect, useState } from 'react';
import { APP_VERSION } from '../../shared/model';
import { isNewer } from '../../shared/update/version';

/**
 * On load, best-effort fetch a `version.json` next to the app (written at deploy
 * time) and, if it advertises a newer version, show a one-tap "update" banner.
 * Silent on failure (offline / opened from a file) so it never gets in the way.
 * The fetch is path-relative, so it reads NFEditor's own version.json — never the
 * sibling CalendarMaker's.
 */
export function UpdateBanner() {
  const [latest, setLatest] = useState<string | null>(null);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
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
    return () => {
      cancelled = true;
    };
  }, []);

  if (!latest || dismissed) return null;

  return (
    <div className="update-banner" role="alert">
      <span>✨ A newer version of NFEditor is ready.</span>
      <button className="primary" onClick={() => window.location.reload()}>
        Update now
      </button>
      <button className="ghost light" onClick={() => setDismissed(true)}>
        Later
      </button>
    </div>
  );
}
