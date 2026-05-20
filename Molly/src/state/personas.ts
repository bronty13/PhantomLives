import { useCallback, useEffect, useState } from 'react';
import { ALL_PERSONAS, listPersonas, type Persona } from '../data/personas';

export { ALL_PERSONAS };
export type { Persona };

export function usePersonas() {
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [active, setActive] = useState<Persona>(ALL_PERSONAS);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    const list = await listPersonas();
    setPersonas(list);
    setActive((prev) => {
      if (prev.code === 'ALL') return ALL_PERSONAS;
      return list.find((p) => p.code === prev.code) ?? ALL_PERSONAS;
    });
  }, []);

  useEffect(() => {
    let alive = true;
    listPersonas()
      .then((list) => {
        if (!alive) return;
        setPersonas(list);
        const lastCode = localStorage.getItem('molly.activePersonaCode') ?? 'ALL';
        const match = lastCode === 'ALL' ? ALL_PERSONAS : list.find((x) => x.code === lastCode) ?? ALL_PERSONAS;
        setActive(match);
        setLoading(false);
      })
      .catch((e: unknown) => {
        setError(String(e));
        setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, []);

  const choose = (p: Persona) => {
    setActive(p);
    localStorage.setItem('molly.activePersonaCode', p.code);
  };

  return { personas, active, choose, loading, error, refresh } as const;
}
