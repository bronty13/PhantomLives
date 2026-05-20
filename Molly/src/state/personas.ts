import { useEffect, useState } from 'react';
import Database from '@tauri-apps/plugin-sql';

export interface Persona {
  code: string;
  name: string;
  description: string;
  primaryColor: string;
  secondaryColor: string;
  tintColor: string;
  accentColor: string;
  textColor: string;
  sortOrder: number;
}

/** Sentinel for the "ALL personas" view. */
export const ALL_PERSONAS: Persona = {
  code: 'ALL',
  name: 'All Personas',
  description: 'A unified view across every persona.',
  primaryColor: '#E8B8D9',
  secondaryColor: '#F5E2F0',
  tintColor: '#FCF5FA',
  accentColor: '#A16D9C',
  textColor: '#3C283C',
  sortOrder: 0,
};

let dbPromise: Promise<Database> | null = null;
export function db(): Promise<Database> {
  if (!dbPromise) dbPromise = Database.load('sqlite:molly.db');
  return dbPromise;
}

interface PersonaRow {
  code: string;
  name: string;
  description: string;
  primary_color: string;
  secondary_color: string;
  tint_color: string;
  accent_color: string;
  text_color: string;
  sort_order: number;
}

function rowToPersona(r: PersonaRow): Persona {
  return {
    code: r.code,
    name: r.name,
    description: r.description,
    primaryColor: r.primary_color,
    secondaryColor: r.secondary_color,
    tintColor: r.tint_color,
    accentColor: r.accent_color,
    textColor: r.text_color,
    sortOrder: r.sort_order,
  };
}

export async function loadPersonas(): Promise<Persona[]> {
  const conn = await db();
  const rows = await conn.select<PersonaRow[]>(
    'SELECT code, name, description, primary_color, secondary_color, tint_color, accent_color, text_color, sort_order FROM personas WHERE archived = 0 ORDER BY sort_order, name',
  );
  return rows.map(rowToPersona);
}

export function usePersonas() {
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [active, setActive] = useState<Persona>(ALL_PERSONAS);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    loadPersonas()
      .then((p) => {
        if (!alive) return;
        setPersonas(p);
        const lastCode = localStorage.getItem('molly.activePersonaCode') ?? 'ALL';
        const match = lastCode === 'ALL' ? ALL_PERSONAS : p.find((x) => x.code === lastCode) ?? ALL_PERSONAS;
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

  return { personas, active, choose, loading, error } as const;
}
