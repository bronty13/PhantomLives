import { db } from './db';

export interface TaxonomyItem {
  id: number;
  name: string;
  color: string;
  sortOrder: number;
  archived: boolean;
}

interface Row {
  id: number;
  name: string;
  color: string;
  sort_order: number;
  archived: number;
}

function row(r: Row): TaxonomyItem {
  return { id: r.id, name: r.name, color: r.color, sortOrder: r.sort_order, archived: r.archived !== 0 };
}

async function list(table: 'products' | 'interests'): Promise<TaxonomyItem[]> {
  const conn = await db();
  const rows = await conn.select<Row[]>(
    `SELECT id, name, color, sort_order, archived FROM ${table} WHERE archived = 0 ORDER BY sort_order, name`,
  );
  return rows.map(row);
}

async function create(table: 'products' | 'interests', name: string, color: string, sortOrder: number): Promise<number> {
  const conn = await db();
  const result = await conn.execute(
    `INSERT INTO ${table} (name, color, sort_order) VALUES ($1, $2, $3)`,
    [name, color, sortOrder],
  );
  return Number(result.lastInsertId ?? 0);
}

async function update(table: 'products' | 'interests', item: TaxonomyItem): Promise<void> {
  const conn = await db();
  await conn.execute(
    `UPDATE ${table} SET name = $1, color = $2, sort_order = $3, archived = $4, updated_at = datetime('now') WHERE id = $5`,
    [item.name, item.color, item.sortOrder, item.archived ? 1 : 0, item.id],
  );
}

async function remove(table: 'products' | 'interests', id: number): Promise<void> {
  const conn = await db();
  await conn.execute(`DELETE FROM ${table} WHERE id = $1`, [id]);
}

export const products = {
  list:   () => list('products'),
  create: (name: string, color: string, sortOrder: number) => create('products', name, color, sortOrder),
  update: (item: TaxonomyItem) => update('products', item),
  remove: (id: number) => remove('products', id),
};

export const interests = {
  list:   () => list('interests'),
  create: (name: string, color: string, sortOrder: number) => create('interests', name, color, sortOrder),
  update: (item: TaxonomyItem) => update('interests', item),
  remove: (id: number) => remove('interests', id),
};
