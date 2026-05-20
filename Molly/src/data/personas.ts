import { db } from './db';

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

export async function listPersonas(): Promise<Persona[]> {
  const conn = await db();
  const rows = await conn.select<PersonaRow[]>(
    'SELECT code, name, description, primary_color, secondary_color, tint_color, accent_color, text_color, sort_order FROM personas WHERE archived = 0 ORDER BY sort_order, name',
  );
  return rows.map(rowToPersona);
}

export async function updatePersona(p: Persona): Promise<void> {
  const conn = await db();
  await conn.execute(
    `UPDATE personas SET name = $1, description = $2, primary_color = $3, secondary_color = $4, tint_color = $5, accent_color = $6, text_color = $7, sort_order = $8, updated_at = datetime('now') WHERE code = $9`,
    [
      p.name,
      p.description,
      p.primaryColor,
      p.secondaryColor,
      p.tintColor,
      p.accentColor,
      p.textColor,
      p.sortOrder,
      p.code,
    ],
  );
}
