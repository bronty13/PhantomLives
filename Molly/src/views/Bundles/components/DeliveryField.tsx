import { useEffect, useState } from 'react';
import { listSites, type Site } from '../../../data/sites';

interface Props {
  personaCode: string | null;
  deliveryKind: 'site' | 'url' | null;
  deliverySiteId: number | null;
  deliveryUrl: string | null;
  onChangeKind: (kind: 'site' | 'url' | null) => Promise<void>;
  onChangeSiteId: (id: number | null) => Promise<void>;
  onChangeUrl: (url: string | null) => Promise<void>;
  disabled?: boolean;
}

/** Where the custom video is being delivered — either a known site from
 * Molly's `sites` table (filtered to the bundle's persona) OR an
 * arbitrary URL that Robert will fill in on return. Sallie just picks
 * the method; the URL itself is the work-product Robert delivers back
 * via the SideMolly return-file flow, so it's not collected here. */
export function DeliveryField({
  personaCode, deliveryKind, deliverySiteId, deliveryUrl,
  onChangeKind, onChangeSiteId, onChangeUrl, disabled,
}: Props) {
  const [sites, setSites] = useState<Site[]>([]);

  useEffect(() => {
    let alive = true;
    listSites({ personaCode: personaCode ?? undefined })
      .then((s) => { if (alive) setSites(s); })
      .catch(() => { if (alive) setSites([]); });
    return () => { alive = false; };
  }, [personaCode]);

  async function pickKind(kind: 'site' | 'url') {
    if (deliveryKind === kind) return;
    if (kind === 'site') {
      // Switching to site → clear any stale URL Sallie might have typed
      // under the old (pre-1.20.1) flow.
      if (deliveryUrl) await onChangeUrl(null);
    } else {
      // Switching to URL → clear site_id (and any stale URL).
      if (deliverySiteId != null) await onChangeSiteId(null);
      if (deliveryUrl) await onChangeUrl(null);
    }
    await onChangeKind(kind);
  }

  return (
    <div className="space-y-2" id="bundle-delivery" tabIndex={-1}>
      <div className="text-xs font-semibold opacity-75">Delivery method</div>
      <div className="flex gap-2">
        <button
          type="button"
          onClick={() => pickKind('site')}
          className={`pretty-button ${deliveryKind === 'site' ? '' : 'secondary'}`}
          disabled={disabled}
        >🌐 Site</button>
        <button
          type="button"
          onClick={() => pickKind('url')}
          className={`pretty-button ${deliveryKind === 'url' ? '' : 'secondary'}`}
          disabled={disabled}
        >🔗 URL link</button>
      </div>

      {deliveryKind === 'site' && (
        <select
          id="bundle-delivery-site"
          className="pretty-input w-full"
          value={deliverySiteId ?? ''}
          onChange={(e) => {
            const v = e.target.value;
            void onChangeSiteId(v === '' ? null : Number(v));
          }}
          disabled={disabled}
        >
          <option value="">— pick a site —</option>
          {sites.map((s) => (
            <option key={s.id} value={s.id}>{s.name}</option>
          ))}
        </select>
      )}

      {deliveryKind === 'url' && (
        <div className="text-xs opacity-70 italic bg-pink-50 border border-pink-200 rounded-xl px-3 py-2">
          🔗 URL link delivery — Robert will fill in the URL on return.
          Nothing else to enter here.
        </div>
      )}

      {!deliveryKind && (
        <div className="text-xs opacity-60 italic">
          Pick Site for a known platform, or URL link for everything else.
        </div>
      )}
    </div>
  );
}
