import { useCallback, useEffect, useRef, useState } from 'react';

// Ported from Molly. Reactive loader with race protection — each effect
// run gets its own `alive` flag flipped to false on cleanup, so late-
// arriving async results from a stale run can't clobber the new run.
// See Molly's src/lib/useAsyncRefresh.ts for the full rationale.
export function useAsyncRefresh(
  loader: (alive: () => boolean) => Promise<void>,
  deps: unknown[],
): { loading: boolean; error: string | null; refresh: () => Promise<void> } {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loaderRef = useRef(loader);
  loaderRef.current = loader;

  const currentAliveRef = useRef<{ current: boolean } | null>(null);

  const refresh = useCallback(async () => {
    if (currentAliveRef.current) currentAliveRef.current.current = false;
    const alive = { current: true };
    currentAliveRef.current = alive;
    setLoading(true);
    setError(null);
    try {
      await loaderRef.current(() => alive.current);
    } catch (e) {
      if (alive.current) setError(String(e));
    } finally {
      if (alive.current) setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (currentAliveRef.current) currentAliveRef.current.current = false;
    const alive = { current: true };
    currentAliveRef.current = alive;
    setLoading(true);
    setError(null);
    (async () => {
      try {
        await loaderRef.current(() => alive.current);
      } catch (e) {
        if (alive.current) setError(String(e));
      } finally {
        if (alive.current) setLoading(false);
      }
    })();
    return () => {
      alive.current = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  return { loading, error, refresh };
}

export function listPlaceholder(opts: {
  loading: boolean;
  error: string | null;
  isEmpty: boolean;
  emptyText?: string;
}): string | null {
  if (opts.loading) return 'Loading…';
  if (opts.error) return `Error: ${opts.error}`;
  if (opts.isEmpty) return opts.emptyText ?? 'Nothing here yet.';
  return null;
}
