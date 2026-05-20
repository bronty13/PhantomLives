import { useCallback, useEffect, useRef, useState } from 'react';

/**
 * Reactive loader with race protection.
 *
 * Wraps the very common pattern of `useEffect → refresh()` we'd been
 * hand-rolling in every list view, adding two things:
 *
 *   1. **Race protection.** Each effect run gets its own `alive` flag,
 *      flipped to false in the effect's cleanup. The loader must check
 *      `alive()` before every setState. So if the user switches the
 *      active persona faster than SQLite returns, the previous run's
 *      late-arriving writes are suppressed instead of clobbering the
 *      new persona's data.
 *
 *   2. **Loading state.** `loading` is `true` for the initial fetch
 *      AND any subsequent re-runs (deps change or manual `refresh()`).
 *      Views can render "Loading…" instead of the misleading "No X yet"
 *      empty-state message while a fetch is in flight.
 *
 * Usage:
 *
 *   const { loading, error, refresh } = useAsyncRefresh(async (alive) => {
 *     const [a, b] = await Promise.all([listA(), listB()]);
 *     if (!alive()) return;
 *     setA(a);
 *     setB(b);
 *   }, [active.code]);
 *
 * `refresh()` is exposed for manual reloads (e.g. after saving a form);
 * it carries the same alive-guard semantics so it stays safe across
 * unmount and persona-switch boundaries.
 */
export function useAsyncRefresh(
  loader: (alive: () => boolean) => Promise<void>,
  deps: unknown[],
): { loading: boolean; error: string | null; refresh: () => Promise<void> } {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Keep the latest closure value so manual refresh() reads up-to-date state.
  const loaderRef = useRef(loader);
  loaderRef.current = loader;

  // Track the most recently created alive flag so refresh() invalidates
  // any in-flight effect run before starting its own.
  const currentAliveRef = useRef<{ current: boolean } | null>(null);

  const refresh = useCallback(async () => {
    // Invalidate any in-flight run before starting our own.
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

/**
 * Small render helper: returns a friendly label for the three states a
 * loaded list view can be in. Use:
 *
 *   const placeholder = listPlaceholder({ loading, error, isEmpty: rows.length === 0 });
 *   if (placeholder) return <div className="…">{placeholder}</div>;
 */
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
