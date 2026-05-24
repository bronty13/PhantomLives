import { fmtPrice, fmtSize, type BundleFileRow,
         type BundleManifest, type BundleSummary } from '../../data/bundles';

interface Props {
  summary: BundleSummary;
  manifest: BundleManifest;
  files: BundleFileRow[];
}

export function OverviewTab({ summary, manifest, files }: Props) {
  return (
    <div className="flex flex-col gap-4">
      <ManifestPane manifest={manifest} />
      <FilesPane files={files} bundleType={summary.bundleType} />
    </div>
  );
}

function ManifestPane({ manifest }: { manifest: BundleManifest }) {
  return (
    <section className="sm-card">
      <h2 className="font-semibold text-base mb-3">Manifest</h2>
      <dl className="grid grid-cols-[140px_1fr] gap-x-4 gap-y-1.5 text-sm">
        <Field k="UID"             v={<code className="text-xs">{manifest.uid}</code>} />
        <Field k="Type"            v={manifest.bundleType} />
        <Field k="Persona"         v={manifest.personaCode ?? '(unassigned)'} />
        <Field k="Content date"    v={manifest.contentDate ?? '—'} />
        {manifest.goLiveDate && <Field k="Go-live date" v={manifest.goLiveDate} />}
        {manifest.publishedAt && <Field k="Published"   v={<code className="text-xs">{manifest.publishedAt}</code>} />}

        {manifest.bundleType === 'content' && (
          <>
            <Field k="Description mode" v={manifest.descriptionMode ?? '—'} />
            {manifest.descriptionText && (
              <Field k="Description" v={<pre className="text-xs whitespace-pre-wrap">{manifest.descriptionText}</pre>} />
            )}
            {manifest.descriptionAudioPath && (
              <Field k="Audio" v={<code className="text-xs">{manifest.descriptionAudioPath}</code>} />
            )}
            {manifest.categories.length > 0 && (
              <Field k="Categories" v={
                <div className="flex flex-wrap gap-1.5">
                  {manifest.categories.map((c, i) => (
                    <span key={i} className="text-xs px-1.5 py-0.5 rounded"
                          style={{ background: 'rgb(var(--surface-accent) / 0.12)', color: 'rgb(var(--surface-accent))' }}>
                      {c}
                    </span>
                  ))}
                </div>
              } />
            )}
          </>
        )}

        {manifest.bundleType === 'custom' && (
          <>
            <Field k="Recipient" v={manifest.deliveryRecipient || '—'} />
            <Field k="Delivery"  v={
              manifest.deliveryKind === 'site' ? (manifest.deliverySiteName ?? '—') :
              manifest.deliveryKind === 'url'  ? (<a href={manifest.deliveryUrl ?? '#'} target="_blank" rel="noreferrer" className="underline">{manifest.deliveryUrl}</a>) :
              '—'
            } />
            <Field k="Price" v={fmtPrice(manifest.priceCents, manifest.handledInPlatform)} />
          </>
        )}

        {manifest.bundleType === 'fansite' && (
          <>
            <Field k="Month" v={
              manifest.fansiteYear && manifest.fansiteMonth
                ? `${manifest.fansiteYear}-${String(manifest.fansiteMonth).padStart(2, '0')}`
                : '—'
            } />
            <Field k="Days"  v={`${manifest.fanDays.length} day${manifest.fanDays.length === 1 ? '' : 's'}`} />
          </>
        )}

        {manifest.specialInstructions && (
          <Field k="Special instructions"
            v={<pre className="text-xs whitespace-pre-wrap">{manifest.specialInstructions}</pre>} />
        )}
      </dl>

      {manifest.bundleType === 'fansite' && manifest.fanDays.length > 0 && (
        <FanDayList days={manifest.fanDays} />
      )}
    </section>
  );
}

function FanDayList({ days }: { days: BundleManifest['fanDays'] }) {
  return (
    <div className="mt-4">
      <div className="text-xs uppercase tracking-wider mb-2" style={{ color: 'rgb(var(--surface-muted))' }}>
        Fan-site days
      </div>
      <ul className="flex flex-col gap-1.5">
        {days.map((d) => (
          <li key={d.dayOfMonth} className="flex items-start gap-3 text-sm">
            <span className="font-mono text-xs px-1.5 py-0.5 rounded shrink-0"
                  style={{ background: 'rgb(var(--surface-base))', minWidth: 38, textAlign: 'center' }}>
              Day {String(d.dayOfMonth).padStart(2, '0')}
            </span>
            <span className="text-xs shrink-0 pt-0.5" style={{ color: 'rgb(var(--surface-muted))' }}>
              {d.fileCount} file{d.fileCount === 1 ? '' : 's'}
            </span>
            <span className="flex-1 min-w-0">{d.message || <em style={{ color: 'rgb(var(--surface-muted))' }}>(no message)</em>}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

function FilesPane({ files, bundleType }: { files: BundleFileRow[]; bundleType: BundleSummary['bundleType'] }) {
  // Stats by kind.
  const counts: Record<string, number> = {};
  let totalBytes = 0;
  for (const f of files) {
    counts[f.kind] = (counts[f.kind] ?? 0) + 1;
    totalBytes += f.sizeBytes;
  }

  return (
    <section className="sm-card">
      <div className="flex items-center justify-between mb-3">
        <h2 className="font-semibold text-base">Files ({files.length})</h2>
        <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
          {Object.entries(counts).map(([k, n]) => `${n} ${k}`).join(' · ')} · {fmtSize(totalBytes)} total
        </div>
      </div>

      <ul className="flex flex-col gap-1">
        {files.map((f) => (
          <li key={f.inZipPath}
              className="flex items-center gap-3 text-xs py-1"
              style={{ borderTop: '1px solid rgb(var(--surface-border))' }}
          >
            <span className="shrink-0 w-12 font-mono" style={{ color: 'rgb(var(--surface-muted))' }}>
              {kindGlyph(f.kind)}
            </span>
            {bundleType === 'fansite' && f.fansiteDayOfMonth != null && (
              <span className="shrink-0 font-mono" style={{ color: 'rgb(var(--surface-muted))' }}>
                D{String(f.fansiteDayOfMonth).padStart(2, '0')}/{String(f.position).padStart(2, '0')}
              </span>
            )}
            {(bundleType === 'content' || bundleType === 'custom') && f.position > 0 && (
              <span className="shrink-0 font-mono" style={{ color: 'rgb(var(--surface-muted))' }}>
                #{String(f.position).padStart(5, '0')}
              </span>
            )}
            <span className="flex-1 min-w-0 truncate font-mono">{f.originalName}</span>
            <span className="shrink-0" style={{ color: 'rgb(var(--surface-muted))' }}>{fmtSize(f.sizeBytes)}</span>
            <code className="shrink-0 text-[10px]" style={{ color: 'rgb(var(--surface-muted))' }}
                  title={f.sha256}>{f.sha256.slice(0, 8)}…</code>
          </li>
        ))}
      </ul>
    </section>
  );
}

function Field({ k, v }: { k: string; v: React.ReactNode }) {
  return (
    <>
      <dt className="text-xs uppercase tracking-wider pt-1" style={{ color: 'rgb(var(--surface-muted))' }}>{k}</dt>
      <dd className="text-sm">{v}</dd>
    </>
  );
}

function kindGlyph(kind: BundleFileRow['kind']): string {
  switch (kind) {
    case 'video':    return '🎬 video';
    case 'image':    return '🖼 image';
    case 'audio':    return '🎙 audio';
    case 'info':     return '📄 info';
    case 'log':      return '📜 log';
    case 'manifest': return '🗂 manifest';
    case 'other':    return '· other';
  }
}
