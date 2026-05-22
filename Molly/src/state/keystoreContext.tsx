import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';
import { listen } from '@tauri-apps/api/event';
import {
  type KeystoreStatus,
  getKeystoreStatus,
  lockKeystore as lockKeystoreCmd,
  unlockKeystore as unlockKeystoreCmd,
} from '../data/keystore';

interface KeystoreContextValue {
  status: KeystoreStatus | null;
  loading: boolean;
  refresh: () => Promise<void>;
  unlock: (passphrase: string) => Promise<void>;
  lock: () => Promise<void>;
}

const KeystoreContext = createContext<KeystoreContextValue | null>(null);

export function KeystoreProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<KeystoreStatus | null>(null);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    try {
      setStatus(await getKeystoreStatus());
    } catch (e) {
      console.warn('keystore_status failed', e);
    } finally {
      setLoading(false);
    }
  }, []);

  const unlock = useCallback(
    async (passphrase: string) => {
      const next = await unlockKeystoreCmd(passphrase);
      setStatus(next);
    },
    [],
  );

  const lock = useCallback(async () => {
    await lockKeystoreCmd();
    await refresh();
  }, [refresh]);

  useEffect(() => {
    refresh();
    // Re-poll on window focus + every 60s. Tauri also emits
    // 'keystore-locked' from the Rust idle-checker; subscribe.
    const onFocus = () => { void refresh(); };
    window.addEventListener('focus', onFocus);
    const interval = window.setInterval(() => { void refresh(); }, 60_000);
    const lockedUnlisten = listen('keystore-locked', () => { void refresh(); });
    const unlockedUnlisten = listen('keystore-unlocked', () => { void refresh(); });
    return () => {
      window.removeEventListener('focus', onFocus);
      window.clearInterval(interval);
      lockedUnlisten.then((fn) => fn()).catch(() => {});
      unlockedUnlisten.then((fn) => fn()).catch(() => {});
    };
  }, [refresh]);

  return (
    <KeystoreContext.Provider value={{ status, loading, refresh, unlock, lock }}>
      {children}
    </KeystoreContext.Provider>
  );
}

export function useKeystore(): KeystoreContextValue {
  const ctx = useContext(KeystoreContext);
  if (!ctx) throw new Error('useKeystore must be used inside <KeystoreProvider>');
  return ctx;
}
