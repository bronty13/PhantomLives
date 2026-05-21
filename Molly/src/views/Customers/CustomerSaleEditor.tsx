import { useState } from 'react';
import { addSale, updateSale, type Sale } from '../../data/customerSales';
import type { TaxonomyItem } from '../../data/taxonomy';

interface Props {
  customerUid: string;
  products: TaxonomyItem[];   // non-archived products from the catalog
  initial?: Sale;             // present = edit mode; absent = new sale
  onSaved: () => Promise<void> | void;
  onCancel: () => void;
}

function centsToText(cents: number): string {
  return (cents / 100).toFixed(2);
}

function parseDecimal(s: string): number {
  const cleaned = s.replace(/[^\d.]/g, '');
  const n = parseFloat(cleaned);
  return isFinite(n) ? n : 0;
}

function unitLabel(unit: string | undefined, qty: number): string {
  if (!unit) return '';
  // Simple pluralization for the units we ship with (minute/hour/item/session/set).
  const plural = qty === 1 ? unit : `${unit}s`;
  return plural;
}

export function CustomerSaleEditor({ customerUid, products, initial, onSaved, onCancel }: Props) {
  const sorted = products.filter((p) => !p.archived);
  const initProductId = initial?.productId ?? sorted[0]?.id ?? 0;
  const initProduct = sorted.find((p) => p.id === initProductId);
  const initQty = initial?.quantity ?? 1;
  const initUnitCents = initial?.unitPriceCents ?? initProduct?.priceCents ?? 0;
  const initTotalCents = initial?.totalCents ?? Math.round(initQty * initUnitCents);

  const [productId, setProductId] = useState<number>(initProductId);
  const [qtyText, setQtyText] = useState<string>(String(initQty));
  const [unitText, setUnitText] = useState<string>(centsToText(initUnitCents));
  const [totalText, setTotalText] = useState<string>(centsToText(initTotalCents));
  // <input type="date"> wants "YYYY-MM-DD". SQLite stores "YYYY-MM-DD HH:MM:SS"
  // (or just "YYYY-MM-DD"); split on space or T and keep the date portion.
  const initDate = (initial?.saleDate ?? '').split(/[ T]/)[0] ?? '';
  const [saleDate, setSaleDate] = useState<string>(initDate);
  const [notes, setNotes] = useState<string>(initial?.notes ?? '');
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState('');

  const product = sorted.find((p) => p.id === productId);
  const qtyNum = parseDecimal(qtyText);
  const unitDisplay = unitLabel(product?.unit, qtyNum);

  function onQtyChange(v: string) {
    setQtyText(v);
    const q = parseDecimal(v);
    const unit = parseDecimal(unitText);
    setTotalText((q * unit).toFixed(2));
  }
  function onUnitChange(v: string) {
    setUnitText(v);
    const q = parseDecimal(qtyText);
    const unit = parseDecimal(v);
    setTotalText((q * unit).toFixed(2));
  }
  function onTotalChange(v: string) {
    // Editing total back-solves unit price; quantity stays put.
    setTotalText(v);
    const q = parseDecimal(qtyText);
    const total = parseDecimal(v);
    if (q > 0) setUnitText((total / q).toFixed(2));
  }
  function onProductChange(id: number) {
    setProductId(id);
    const p = sorted.find((x) => x.id === id);
    if (p && (p.priceCents ?? 0) > 0) {
      const unit = centsToText(p.priceCents ?? 0);
      setUnitText(unit);
      const q = parseDecimal(qtyText);
      setTotalText((q * parseDecimal(unit)).toFixed(2));
    }
  }

  async function commit() {
    if (!productId) {
      setStatus('Pick a product first.');
      return;
    }
    setBusy(true);
    setStatus('');
    try {
      const quantity = parseDecimal(qtyText);
      const unitPriceCents = Math.round(parseDecimal(unitText) * 100);
      const totalCents = Math.round(parseDecimal(totalText) * 100);
      // Pin the time to noon UTC so the date sorts cleanly against history's
      // full datetimes and timezone shifts don't bump the displayed day.
      const dateForDb = saleDate ? `${saleDate} 12:00:00` : undefined;
      if (initial) {
        await updateSale({
          ...initial,
          productId,
          saleDate: dateForDb ?? initial.saleDate,
          quantity,
          unitPriceCents,
          totalCents,
          notes,
        });
      } else {
        await addSale({
          customerUid,
          productId,
          saleDate: dateForDb,
          quantity,
          unitPriceCents,
          totalCents,
          notes,
        });
      }
      await onSaved();
    } catch (e) {
      setStatus(`Couldn't save: ${String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="p-3 rounded-xl bg-white border border-black/10 space-y-3">
      <div className="text-xs uppercase tracking-wider opacity-60 font-semibold">
        🛒 {initial ? 'Edit sale' : 'New sale'}
      </div>

      <div className="grid grid-cols-2 gap-3">
        <label className="flex flex-col gap-1 col-span-2">
          <span className="text-xs opacity-60">Product</span>
          <select
            className="pretty-input"
            value={productId}
            onChange={(e) => onProductChange(Number(e.target.value))}
          >
            {sorted.length === 0 && <option value={0}>No products available</option>}
            {sorted.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
                {p.priceCents !== undefined && p.priceCents > 0
                  ? ` — $${centsToText(p.priceCents)} / ${p.unit || 'item'}`
                  : ''}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1">
          <span className="text-xs opacity-60">Quantity {unitDisplay && `(${unitDisplay})`}</span>
          <input
            type="text"
            inputMode="decimal"
            className="pretty-input"
            value={qtyText}
            onChange={(e) => onQtyChange(e.target.value)}
          />
        </label>

        <label className="flex flex-col gap-1">
          <span className="text-xs opacity-60">Unit price (USD)</span>
          <input
            type="text"
            inputMode="decimal"
            className="pretty-input"
            value={unitText}
            onChange={(e) => onUnitChange(e.target.value)}
            onBlur={(e) => onUnitChange(parseDecimal(e.target.value).toFixed(2))}
          />
        </label>

        <label className="flex flex-col gap-1">
          <span className="text-xs opacity-60">Total (USD)</span>
          <input
            type="text"
            inputMode="decimal"
            className="pretty-input"
            value={totalText}
            onChange={(e) => onTotalChange(e.target.value)}
            onBlur={(e) => onTotalChange(parseDecimal(e.target.value).toFixed(2))}
          />
        </label>

        <label className="flex flex-col gap-1">
          <span className="text-xs opacity-60">Date {!initial && '(leave blank for today)'}</span>
          <input
            type="date"
            className="pretty-input"
            value={saleDate}
            onChange={(e) => setSaleDate(e.target.value)}
          />
        </label>

        <label className="flex flex-col gap-1 col-span-2">
          <span className="text-xs opacity-60">Notes — what was this sale?</span>
          <textarea
            rows={2}
            className="pretty-input"
            placeholder="e.g. 10-minute custom; usual feet content"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
          />
        </label>
      </div>

      {status && <div className="text-sm" style={{ color: '#B45309' }}>{status}</div>}

      <div className="flex items-center gap-2 justify-end">
        <button type="button" className="pretty-button secondary" onClick={onCancel} disabled={busy}>
          Cancel
        </button>
        <button type="button" className="pretty-button" onClick={commit} disabled={busy || !productId}>
          {busy ? 'Saving…' : initial ? '💾 Save changes' : '➕ Add sale'}
        </button>
      </div>
    </div>
  );
}
