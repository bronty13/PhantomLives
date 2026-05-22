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

/** Where the custom video is being delivered — either a site from
 * Molly's existing `sites` table (filtered to the bundle's persona) OR
 * an arbitrary URL. Exactly one of the two is the rule (validated
 * server + client side). Switching from one to the other clears the
 * inactive field. */
export function DeliveryField({
  personaCode, deliveryKind, deliverySiteId, deliveryUrl,
  onChangeKind, onChangeSiteId, onChangeUrl, disabled,
}: Props) {
  const [sites, setSites] = useState<Site[]>([]);
  const [urlDraft, setUrlDraft] = useState(deliveryUrl ?? '');
  useEffect(() => { setUrlDraft(deliveryUrl ?? ''); }, [deliveryUrl]);

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
      // Switching to site → clear URL.
      if (deliveryUrl) await onChangeUrl(null);
    } else {
      // Switching to URL → clear site_id.
      if (deliverySiteId != null) await onChangeSiteId(null);
    }
    await onChangeKind(kind);
  }

  return (
    <div className="space-y-2" id="bundle-delivery" tabIndex={-1}>
      <div className="text-xs font-semibold opacity-75">Delivery platform</div>
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
        <input
          id="bundle-delivery-url"
          type="text"
          className="pretty-input w-full font-mono"
          placeholder="https://example.com/clip-123"
          value={urlDraft}
          onChange={(e) => setUrlDraft(e.target.value)}
          onBlur={() => { if (urlDraft !== (deliveryUrl ?? '')) onChangeUrl(urlDraft || null); }}
          disabled={disabled}
        />
      )}

      {!deliveryKind && (
        <div className="text-xs opacity-60 italic">
          Pick Site for a known platform, or URL link for anything else.
        </div>
      )}
    </div>
  );
}
