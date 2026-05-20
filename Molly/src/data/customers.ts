import { db } from './db';

export interface Customer {
  uid: string;
  personaCode: string | null;
  username: string;
  realName: string;
  emails: [string, string, string, string, string];
  notesHtml: string;
  archived: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface CustomerSummary {
  uid: string;
  personaCode: string | null;
  username: string;
  realName: string;
  primaryEmail: string;
  productCount: number;
  interestCount: number;
  updatedAt: string;
}

interface CustomerRow {
  uid: string;
  persona_code: string | null;
  username: string;
  real_name: string;
  email1: string;
  email2: string;
  email3: string;
  email4: string;
  email5: string;
  notes_html: string;
  archived: number;
  created_at: string;
  updated_at: string;
}

function rowToCustomer(r: CustomerRow): Customer {
  return {
    uid: r.uid,
    personaCode: r.persona_code,
    username: r.username,
    realName: r.real_name,
    emails: [r.email1, r.email2, r.email3, r.email4, r.email5],
    notesHtml: r.notes_html,
    archived: r.archived !== 0,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  };
}

export async function listCustomers(opts?: { personaCode?: string; search?: string }): Promise<CustomerSummary[]> {
  const conn = await db();
  const params: unknown[] = [];
  let sql = `
    SELECT
      c.uid, c.persona_code, c.username, c.real_name,
      COALESCE(NULLIF(c.email1, ''), NULLIF(c.email2, ''), NULLIF(c.email3, ''), NULLIF(c.email4, ''), NULLIF(c.email5, ''), '') AS primary_email,
      (SELECT COUNT(*) FROM customer_products  WHERE customer_uid = c.uid) AS product_count,
      (SELECT COUNT(*) FROM customer_interests WHERE customer_uid = c.uid) AS interest_count,
      c.updated_at
    FROM customers c
    WHERE c.archived = 0`;
  if (opts?.personaCode && opts.personaCode !== 'ALL') {
    params.push(opts.personaCode);
    sql += ` AND c.persona_code = $${params.length}`;
  }
  if (opts?.search && opts.search.trim()) {
    const like = `%${opts.search.trim()}%`;
    params.push(like, like, like);
    sql += ` AND (c.username LIKE $${params.length - 2} OR c.real_name LIKE $${params.length - 1} OR c.uid LIKE $${params.length})`;
  }
  sql += ' ORDER BY c.updated_at DESC';

  type R = {
    uid: string;
    persona_code: string | null;
    username: string;
    real_name: string;
    primary_email: string;
    product_count: number;
    interest_count: number;
    updated_at: string;
  };
  const rows = await conn.select<R[]>(sql, params);
  return rows.map((r) => ({
    uid: r.uid,
    personaCode: r.persona_code,
    username: r.username,
    realName: r.real_name,
    primaryEmail: r.primary_email,
    productCount: r.product_count,
    interestCount: r.interest_count,
    updatedAt: r.updated_at,
  }));
}

export async function getCustomer(uid: string): Promise<Customer | null> {
  const conn = await db();
  const rows = await conn.select<CustomerRow[]>(
    'SELECT uid, persona_code, username, real_name, email1, email2, email3, email4, email5, notes_html, archived, created_at, updated_at FROM customers WHERE uid = $1',
    [uid],
  );
  if (rows.length === 0) return null;
  return rowToCustomer(rows[0]);
}

export async function createCustomer(c: Customer): Promise<void> {
  const conn = await db();
  await conn.execute(
    `INSERT INTO customers (uid, persona_code, username, real_name, email1, email2, email3, email4, email5, notes_html, archived)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
    [
      c.uid,
      c.personaCode,
      c.username,
      c.realName,
      c.emails[0],
      c.emails[1],
      c.emails[2],
      c.emails[3],
      c.emails[4],
      c.notesHtml,
      c.archived ? 1 : 0,
    ],
  );
}

export async function updateCustomer(c: Customer): Promise<void> {
  const conn = await db();
  await conn.execute(
    `UPDATE customers SET persona_code = $1, username = $2, real_name = $3, email1 = $4, email2 = $5, email3 = $6, email4 = $7, email5 = $8, notes_html = $9, archived = $10, updated_at = datetime('now') WHERE uid = $11`,
    [
      c.personaCode,
      c.username,
      c.realName,
      c.emails[0],
      c.emails[1],
      c.emails[2],
      c.emails[3],
      c.emails[4],
      c.notesHtml,
      c.archived ? 1 : 0,
      c.uid,
    ],
  );
}

export async function deleteCustomer(uid: string): Promise<void> {
  const conn = await db();
  await conn.execute('DELETE FROM customers WHERE uid = $1', [uid]);
}

export async function getCustomerProductIds(uid: string): Promise<number[]> {
  const conn = await db();
  const rows = await conn.select<{ product_id: number }[]>(
    'SELECT product_id FROM customer_products WHERE customer_uid = $1',
    [uid],
  );
  return rows.map((r) => r.product_id);
}

export async function getCustomerInterestIds(uid: string): Promise<number[]> {
  const conn = await db();
  const rows = await conn.select<{ interest_id: number }[]>(
    'SELECT interest_id FROM customer_interests WHERE customer_uid = $1',
    [uid],
  );
  return rows.map((r) => r.interest_id);
}

export async function setCustomerProducts(uid: string, ids: number[]): Promise<void> {
  const conn = await db();
  await conn.execute('DELETE FROM customer_products WHERE customer_uid = $1', [uid]);
  for (const pid of ids) {
    await conn.execute('INSERT INTO customer_products (customer_uid, product_id) VALUES ($1, $2)', [uid, pid]);
  }
}

export async function setCustomerInterests(uid: string, ids: number[]): Promise<void> {
  const conn = await db();
  await conn.execute('DELETE FROM customer_interests WHERE customer_uid = $1', [uid]);
  for (const iid of ids) {
    await conn.execute('INSERT INTO customer_interests (customer_uid, interest_id) VALUES ($1, $2)', [uid, iid]);
  }
}
