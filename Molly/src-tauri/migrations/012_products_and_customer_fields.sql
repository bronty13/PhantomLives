-- Phase 1.2.0: extend products with price/unit (used by Phase 3 sales),
-- and extend customers with VIP, primary-email index, mailing address,
-- and two phone numbers. All columns are additive; existing rows get
-- sensible defaults so the migration is lossless.

-- Products -----------------------------------------------------------------
ALTER TABLE products ADD COLUMN price_cents INTEGER NOT NULL DEFAULT 0;
ALTER TABLE products ADD COLUMN unit        TEXT    NOT NULL DEFAULT 'item';

-- Seed sensible units for the 7 preloaded products. Prices stay 0 — Sallie
-- sets them in Settings → Products. The Phone/Cam/Customs trio bills per
-- minute; the physical merch bills per item.
UPDATE products SET unit = 'minute' WHERE name IN ('Phone', 'Cam', 'Customs');
UPDATE products SET unit = 'item'   WHERE name LIKE 'Physical%';

-- Customers ----------------------------------------------------------------
-- VIP toggle (cute indicator + filter target).
ALTER TABLE customers ADD COLUMN vip INTEGER NOT NULL DEFAULT 0;

-- Primary email selector: 0..4 indexes into email1..email5. Replaces the
-- prior COALESCE-first-non-empty heuristic with an explicit choice.
ALTER TABLE customers ADD COLUMN primary_email_index INTEGER NOT NULL DEFAULT 0;

-- Mailing address. Single address per customer for MVP; pivot to a join
-- table if billing/shipping ever diverge. zip / zip4 stay TEXT so leading
-- zeros and international postcodes work.
ALTER TABLE customers ADD COLUMN address1 TEXT NOT NULL DEFAULT '';
ALTER TABLE customers ADD COLUMN address2 TEXT NOT NULL DEFAULT '';
ALTER TABLE customers ADD COLUMN city     TEXT NOT NULL DEFAULT '';
ALTER TABLE customers ADD COLUMN state    TEXT NOT NULL DEFAULT '';
ALTER TABLE customers ADD COLUMN zip      TEXT NOT NULL DEFAULT '';
ALTER TABLE customers ADD COLUMN zip4     TEXT NOT NULL DEFAULT '';
ALTER TABLE customers ADD COLUMN country  TEXT NOT NULL DEFAULT 'US';

-- Two phone numbers with mobile flags. Primary phone is indexed 0 or 1.
ALTER TABLE customers ADD COLUMN phone1            TEXT    NOT NULL DEFAULT '';
ALTER TABLE customers ADD COLUMN phone1_is_mobile  INTEGER NOT NULL DEFAULT 0;
ALTER TABLE customers ADD COLUMN phone2            TEXT    NOT NULL DEFAULT '';
ALTER TABLE customers ADD COLUMN phone2_is_mobile  INTEGER NOT NULL DEFAULT 0;
ALTER TABLE customers ADD COLUMN primary_phone_index INTEGER NOT NULL DEFAULT 0;
