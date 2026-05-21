import { db } from './db';

export interface TaxonomyItem {
  id: number;
  name: string;
  color: string;
  sortOrder: number;
  archived: boolean;
  description?: string;
  priceCents?: number;  // products only (migration 012)
  unit?: string;        // products only (migration 012)
}

interface Row {
  id: number;
  name: string;
  color: string;
  sort_order: number;
  archived: number;
  description?: string;
  price_cents?: number;
  unit?: string;
}

function row(r: Row): TaxonomyItem {
  return {
    id: r.id,
    name: r.name,
    color: r.color,
    sortOrder: r.sort_order,
    archived: r.archived !== 0,
    description: r.description ?? '',
    priceCents: r.price_cents ?? 0,
    unit: r.unit ?? '',
  };
}

async function list(table: 'products' | 'interests' | 'kinks'): Promise<TaxonomyItem[]> {
  const conn = await db();
  // Per-table column shape:
  //   kinks    has `description` (migration 011)
  //   products has `price_cents`, `unit` (migration 012)
  //   interests is the simple original.
  let cols = 'id, name, color, sort_order, archived';
  if (table === 'kinks') cols += ', description';
  if (table === 'products') cols += ', price_cents, unit';
  const rows = await conn.select<Row[]>(
    `SELECT ${cols} FROM ${table} WHERE archived = 0 ORDER BY sort_order, name`,
  );
  return rows.map(row);
}

async function create(table: 'products' | 'interests' | 'kinks', name: string, color: string, sortOrder: number): Promise<number> {
  const conn = await db();
  const result = await conn.execute(
    `INSERT INTO ${table} (name, color, sort_order) VALUES ($1, $2, $3)`,
    [name, color, sortOrder],
  );
  return Number(result.lastInsertId ?? 0);
}

async function update(table: 'products' | 'interests' | 'kinks', item: TaxonomyItem): Promise<void> {
  const conn = await db();
  if (table === 'products') {
    await conn.execute(
      `UPDATE products SET name = $1, color = $2, sort_order = $3, archived = $4,
              price_cents = $5, unit = $6, updated_at = datetime('now')
        WHERE id = $7`,
      [item.name, item.color, item.sortOrder, item.archived ? 1 : 0, item.priceCents ?? 0, item.unit ?? 'item', item.id],
    );
    return;
  }
  await conn.execute(
    `UPDATE ${table} SET name = $1, color = $2, sort_order = $3, archived = $4, updated_at = datetime('now') WHERE id = $5`,
    [item.name, item.color, item.sortOrder, item.archived ? 1 : 0, item.id],
  );
}

async function remove(table: 'products' | 'interests' | 'kinks', id: number): Promise<void> {
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

export const kinks = {
  list:   () => list('kinks'),
  create: (name: string, color: string, sortOrder: number) => create('kinks', name, color, sortOrder),
  update: (item: TaxonomyItem) => update('kinks', item),
  remove: (id: number) => remove('kinks', id),
};
