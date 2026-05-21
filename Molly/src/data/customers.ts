import { db } from './db';

export interface Customer {
  uid: string;
  personaCode: string | null;
  username: string;
  realName: string;
  emails: [string, string, string, string, string];
  primaryEmailIndex: number; // 0..4
  notesHtml: string;
  archived: boolean;
  vip: boolean;
  // Mailing address (single address per customer for MVP).
  address1: string;
  address2: string;
  city: string;
  state: string;
  zip: string;
  zip4: string;
  country: string; // ISO 3166-1 alpha-2, default 'US'
  // Phone numbers (two slots, like emails but smaller).
  phone1: string;
  phone1IsMobile: boolean;
  phone2: string;
  phone2IsMobile: boolean;
  primaryPhoneIndex: number; // 0 | 1
  createdAt: string;
  updatedAt: string;
}

export interface CustomerSummary {
  uid: string;
  personaCode: string | null;
  username: string;
  realName: string;
  primaryEmail: string;
  vip: boolean;
  productCount: number;
  interestCount: number;
  kinkCount: number;
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
  primary_email_index: number;
  notes_html: string;
  archived: number;
  vip: number;
  address1: string;
  address2: string;
  city: string;
  state: string;
  zip: string;
  zip4: string;
  country: string;
  phone1: string;
  phone1_is_mobile: number;
  phone2: string;
  phone2_is_mobile: number;
  primary_phone_index: number;
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
    primaryEmailIndex: r.primary_email_index ?? 0,
    notesHtml: r.notes_html,
    archived: r.archived !== 0,
    vip: (r.vip ?? 0) !== 0,
    address1: r.address1 ?? '',
    address2: r.address2 ?? '',
    city: r.city ?? '',
    state: r.state ?? '',
    zip: r.zip ?? '',
    zip4: r.zip4 ?? '',
    country: r.country ?? 'US',
    phone1: r.phone1 ?? '',
    phone1IsMobile: (r.phone1_is_mobile ?? 0) !== 0,
    phone2: r.phone2 ?? '',
    phone2IsMobile: (r.phone2_is_mobile ?? 0) !== 0,
    primaryPhoneIndex: r.primary_phone_index ?? 0,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  };
}

export async function listCustomers(opts?: { personaCode?: string; search?: string }): Promise<CustomerSummary[]> {
  const conn = await db();
  const params: unknown[] = [];
  // Primary email: prefer the user-chosen primary_email_index when that slot
  // is non-empty; otherwise fall back to the first non-empty slot.
  let sql = `
    SELECT
      c.uid, c.persona_code, c.username, c.real_name, c.vip,
      COALESCE(
        NULLIF(CASE c.primary_email_index
          WHEN 0 THEN c.email1
          WHEN 1 THEN c.email2
          WHEN 2 THEN c.email3
          WHEN 3 THEN c.email4
          WHEN 4 THEN c.email5
        END, ''),
        NULLIF(c.email1, ''),
        NULLIF(c.email2, ''),
        NULLIF(c.email3, ''),
        NULLIF(c.email4, ''),
        NULLIF(c.email5, ''),
        ''
      ) AS primary_email,
      (SELECT COUNT(*) FROM customer_products  WHERE customer_uid = c.uid) AS product_count,
      (SELECT COUNT(*) FROM customer_interests WHERE customer_uid = c.uid) AS interest_count,
      (SELECT COUNT(*) FROM customer_kinks     WHERE customer_uid = c.uid) AS kink_count,
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
  // VIP first, then by recency. Keeps the cute ⭐ rows up top.
  sql += ' ORDER BY c.vip DESC, c.updated_at DESC';

  type R = {
    uid: string;
    persona_code: string | null;
    username: string;
    real_name: string;
    vip: number;
    primary_email: string;
    product_count: number;
    interest_count: number;
    kink_count: number;
    updated_at: string;
  };
  const rows = await conn.select<R[]>(sql, params);
  return rows.map((r) => ({
    uid: r.uid,
    personaCode: r.persona_code,
    username: r.username,
    realName: r.real_name,
    primaryEmail: r.primary_email,
    vip: (r.vip ?? 0) !== 0,
    productCount: r.product_count,
    interestCount: r.interest_count,
    kinkCount: r.kink_count,
    updatedAt: r.updated_at,
  }));
}

const CUSTOMER_COLS =
  'uid, persona_code, username, real_name, ' +
  'email1, email2, email3, email4, email5, primary_email_index, ' +
  'notes_html, archived, vip, ' +
  'address1, address2, city, state, zip, zip4, country, ' +
  'phone1, phone1_is_mobile, phone2, phone2_is_mobile, primary_phone_index, ' +
  'created_at, updated_at';

export async function getCustomer(uid: string): Promise<Customer | null> {
  const conn = await db();
  const rows = await conn.select<CustomerRow[]>(
    `SELECT ${CUSTOMER_COLS} FROM customers WHERE uid = $1`,
    [uid],
  );
  if (rows.length === 0) return null;
  return rowToCustomer(rows[0]);
}

export async function createCustomer(c: Customer): Promise<void> {
  const conn = await db();
  // New customers get sensible defaults for every new column (Phase 1).
  // The Customer object already carries them — just persist as-is.
  await conn.execute(
    `INSERT INTO customers (
       uid, persona_code, username, real_name,
       email1, email2, email3, email4, email5, primary_email_index,
       notes_html, archived, vip,
       address1, address2, city, state, zip, zip4, country,
       phone1, phone1_is_mobile, phone2, phone2_is_mobile, primary_phone_index
     ) VALUES (
       $1, $2, $3, $4,
       $5, $6, $7, $8, $9, $10,
       $11, $12, $13,
       $14, $15, $16, $17, $18, $19, $20,
       $21, $22, $23, $24, $25
     )`,
    [
      c.uid, c.personaCode, c.username, c.realName,
      c.emails[0], c.emails[1], c.emails[2], c.emails[3], c.emails[4], c.primaryEmailIndex,
      c.notesHtml, c.archived ? 1 : 0, c.vip ? 1 : 0,
      c.address1, c.address2, c.city, c.state, c.zip, c.zip4, c.country,
      c.phone1, c.phone1IsMobile ? 1 : 0, c.phone2, c.phone2IsMobile ? 1 : 0, c.primaryPhoneIndex,
    ],
  );
}

export async function updateCustomer(c: Customer): Promise<void> {
  const conn = await db();
  await conn.execute(
    `UPDATE customers SET
       persona_code = $1, username = $2, real_name = $3,
       email1 = $4, email2 = $5, email3 = $6, email4 = $7, email5 = $8,
       primary_email_index = $9,
       notes_html = $10, archived = $11, vip = $12,
       address1 = $13, address2 = $14, city = $15, state = $16,
       zip = $17, zip4 = $18, country = $19,
       phone1 = $20, phone1_is_mobile = $21, phone2 = $22, phone2_is_mobile = $23,
       primary_phone_index = $24,
       updated_at = datetime('now')
     WHERE uid = $25`,
    [
      c.personaCode, c.username, c.realName,
      c.emails[0], c.emails[1], c.emails[2], c.emails[3], c.emails[4],
      c.primaryEmailIndex,
      c.notesHtml, c.archived ? 1 : 0, c.vip ? 1 : 0,
      c.address1, c.address2, c.city, c.state,
      c.zip, c.zip4, c.country,
      c.phone1, c.phone1IsMobile ? 1 : 0, c.phone2, c.phone2IsMobile ? 1 : 0,
      c.primaryPhoneIndex,
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

export async function getCustomerKinkIds(uid: string): Promise<number[]> {
  const conn = await db();
  const rows = await conn.select<{ kink_id: number }[]>(
    'SELECT kink_id FROM customer_kinks WHERE customer_uid = $1 ORDER BY position, kink_id',
    [uid],
  );
  return rows.map((r) => r.kink_id);
}

export async function setCustomerKinks(uid: string, ids: number[]): Promise<void> {
  const conn = await db();
  await conn.execute('DELETE FROM customer_kinks WHERE customer_uid = $1', [uid]);
  for (let i = 0; i < ids.length; i++) {
    await conn.execute(
      'INSERT INTO customer_kinks (customer_uid, kink_id, position) VALUES ($1, $2, $3)',
      [uid, ids[i], i],
    );
  }
}
