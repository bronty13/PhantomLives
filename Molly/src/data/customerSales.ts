import { db } from './db';

export interface Sale {
  id: number;
  customerUid: string;
  productId: number;
  saleDate: string;        // ISO datetime (UTC, SQLite format)
  quantity: number;
  unitPriceCents: number;
  totalCents: number;
  notes: string;
  createdAt: string;
  updatedAt: string;
}

export interface NewSale {
  customerUid: string;
  productId: number;
  saleDate?: string;       // omit to default to now (server-side)
  quantity: number;
  unitPriceCents: number;
  totalCents: number;
  notes: string;
}

interface SaleRow {
  id: number;
  customer_uid: string;
  product_id: number;
  sale_date: string;
  quantity: number;
  unit_price_cents: number;
  total_cents: number;
  notes: string;
  created_at: string;
  updated_at: string;
}

function rowToSale(r: SaleRow): Sale {
  return {
    id: r.id,
    customerUid: r.customer_uid,
    productId: r.product_id,
    saleDate: r.sale_date,
    quantity: r.quantity,
    unitPriceCents: r.unit_price_cents,
    totalCents: r.total_cents,
    notes: r.notes ?? '',
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  };
}

export async function listSales(customerUid: string): Promise<Sale[]> {
  const conn = await db();
  const rows = await conn.select<SaleRow[]>(
    `SELECT id, customer_uid, product_id, sale_date, quantity,
            unit_price_cents, total_cents, notes, created_at, updated_at
       FROM customer_sales
      WHERE customer_uid = $1
      ORDER BY sale_date DESC, id DESC`,
    [customerUid],
  );
  return rows.map(rowToSale);
}

export async function sumTotalCents(customerUid: string): Promise<number> {
  const conn = await db();
  const rows = await conn.select<{ total: number | null }[]>(
    `SELECT COALESCE(SUM(total_cents), 0) AS total FROM customer_sales WHERE customer_uid = $1`,
    [customerUid],
  );
  return rows[0]?.total ?? 0;
}

export async function addSale(input: NewSale): Promise<number> {
  const conn = await db();
  // sale_date defaults to datetime('now') on the SQL side when omitted.
  if (input.saleDate) {
    const r = await conn.execute(
      `INSERT INTO customer_sales (customer_uid, product_id, sale_date, quantity, unit_price_cents, total_cents, notes)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [input.customerUid, input.productId, input.saleDate, input.quantity, input.unitPriceCents, input.totalCents, input.notes],
    );
    return Number(r.lastInsertId ?? 0);
  }
  const r = await conn.execute(
    `INSERT INTO customer_sales (customer_uid, product_id, quantity, unit_price_cents, total_cents, notes)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [input.customerUid, input.productId, input.quantity, input.unitPriceCents, input.totalCents, input.notes],
  );
  return Number(r.lastInsertId ?? 0);
}

export async function updateSale(sale: Sale): Promise<void> {
  const conn = await db();
  await conn.execute(
    `UPDATE customer_sales
        SET product_id = $1, sale_date = $2, quantity = $3,
            unit_price_cents = $4, total_cents = $5, notes = $6,
            updated_at = datetime('now')
      WHERE id = $7`,
    [sale.productId, sale.saleDate, sale.quantity, sale.unitPriceCents, sale.totalCents, sale.notes, sale.id],
  );
}

export async function deleteSale(id: number): Promise<void> {
  const conn = await db();
  await conn.execute(`DELETE FROM customer_sales WHERE id = $1`, [id]);
}
