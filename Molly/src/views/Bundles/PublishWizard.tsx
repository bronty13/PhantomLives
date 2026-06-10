import { useEffect, useState } from 'react';
import { convertFileSrc } from '@tauri-apps/api/core';
import {
  type Bundle,
  type BundlePublishResult,
  getBundle,
  listProhibitedWords,
  openBundleArchive,
  publishBundle,
  revealBundlesDir,
} from '../../data/bundles';
import { hasBlockingIssues, validateBundle, type ValidationIssue } from '../../lib/bundleValidation';
import { ValidationChecklist } from './components/ValidationChecklist';
import { BundleFilePreview } from './components/BundleFilePreview';
import { listContentTags, type ContentTag } from '../../data/contentTags';
import { ReadonlyTagPill } from './components/ContentTagPicker';

type Stage = 'loading' | 'review' | 'composing' | 'done' | 'error';

interface Props {
  uid: string;
  onClose: () => void;
  onPublished: () => void;     // refresh list after publish
}

export function PublishWizard({ uid, onClose, onPublished }: Props) {
  const [stage, setStage] = useState<Stage>('loading');
  const [bundle, setBundle] = useState<Bundle | null>(null);
  const [tags, setTags] = useState<ContentTag[]>([]);
  const [issues, setIssues] = useState<ValidationIssue[]>([]);
  const [result, setResult] = useState<BundlePublishResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [serverIssues, setServerIssues] = useState<ValidationIssue[] | null>(null);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const [b, pw, t] = await Promise.all([
          getBundle(uid),
          listProhibitedWords(),
          listContentTags(),
        ]);
        if (!alive) return;
        setBundle(b);
        setTags(t);
        setIssues(validateBundle(b, { today: new Date(), prohibitedWords: pw }));
        setStage('review');
      } catch (e) {
        if (!alive) return;
        setError(String(e));
        setStage('error');
      }
    })();
    return () => { alive = false; };
  }, [uid]);

  const blocking = hasBlockingIssues(issues);

  async function onApprove() {
    if (blocking) return;
    setStage('composing');
    setError(null);
    setServerIssues(null);
    try {
      const r = await publishBundle(uid);
      setResult(r);
      setStage('done');
      onPublished();
    } catch (e: any) {
      // BundleErrorPayload — discriminate on `kind`
      if (e && typeof e === 'object' && e.kind === 'validationFailed' && Array.isArray(e.issues)) {
        setServerIssues(e.issues);
        setStage('review');
        return;
      }
      const msg = (e && typeof e === 'object' && 'message' in e) ? String((e as any).message) : String(e);
      setError(msg);
      setStage('error');
    }
  }

  const persona = bundle?.summary.personaCode ?? '(unassigned)';

  return (
    <div className="fixed inset-0 z-40 bg-black/40 backdrop-blur-sm flex items-stretch justify-end">
      <div className="bg-white w-full max-w-3xl h-full overflow-y-auto shadow-2xl flex flex-col">
        <header className="p-6 border-b border-black/5 flex items-center justify-between sticky top-0 bg-white z-10">
          <div>
            <h2 className="display-font text-xl font-semibold">Review &amp; Publish</h2>
            <p className="text-xs opacity-60 font-mono">{uid}</p>
          </div>
          <button type="button" onClick={onClose} className="pretty-button secondary">Cancel</button>
        </header>

        {stage === 'loading' && (
          <div className="p-8 opacity-60 italic">Loading bundle…</div>
        )}

        {stage === 'review' && bundle && (
          <div className="p-6 space-y-5 flex-1">
            <ReviewSection title="Header">
              <ReviewRow label="Type" value={<span className="font-mono uppercase">{bundle.summary.bundleType}</span>} />
              <ReviewRow label="Persona" value={<span className="font-mono">{persona}</span>} />
              <ReviewRow label="Title" value={<span className="font-medium">{bundle.summary.title || <em className="opacity-50">(blank)</em>}</span>} />
              <ReviewRow label="Content date" value={<span className="font-mono">{bundle.summary.contentDate}</span>} />
              {bundle.summary.bundleType === 'youtube' && (
                <ReviewRow label="Visibility" value={bundle.makePrivate ? '🔒 Private (goes live on publish)' : '🌐 Public'} />
              )}
              {bundle.summary.bundleType !== 'fansite' && !(bundle.summary.bundleType === 'youtube' && bundle.makePrivate) && (
                <ReviewRow label="Go-live date" value={<span className="font-mono">{bundle.summary.goLiveDate ?? '(not set)'}</span>} />
              )}
              {bundle.summary.bundleType === 'youtube' && (
                <ReviewRow label="Also post SFW ManyVids" value={bundle.alsoPostSfwManyvids ? 'Yes' : 'No'} />
              )}
              {bundle.summary.bundleType === 'fansite' && (
                <ReviewRow label="Month" value={
                  <span className="font-mono">
                    {bundle.fansiteYear ?? '(none)'}-{bundle.fansiteMonth != null ? String(bundle.fansiteMonth).padStart(2, '0') : '??'}
                  </span>
                } />
              )}
            </ReviewSection>

            {(bundle.summary.bundleType === 'content' || bundle.summary.bundleType === 'youtube') && (
              <>
                <ReviewSection title="Description">
                  {bundle.descriptionMode === 'audio' && bundle.descriptionAudioAbsolutePath ? (
                    <audio controls className="w-full" src={convertFileSrc(bundle.descriptionAudioAbsolutePath)} />
                  ) : bundle.descriptionMode === 'text' ? (
                    <pre className="whitespace-pre-wrap text-sm bg-pink-50 rounded-xl p-3">{bundle.descriptionText || '(blank)'}</pre>
                  ) : (
                    <span className="opacity-60 italic">No description set.</span>
                  )}
                </ReviewSection>
                {(bundle.summary.bundleType === 'content' || bundle.summary.bundleType === 'youtube') && (bundle.thumbnailAbsolutePath || bundle.teaserGifAbsolutePath) && (
                  <ReviewSection title={bundle.summary.bundleType === 'youtube' ? 'Thumbnail' : 'Preview assets'}>
                    <div className="flex flex-wrap gap-4">
                      {bundle.thumbnailAbsolutePath && (
                        <figure className="space-y-1">
                          <img src={convertFileSrc(bundle.thumbnailAbsolutePath)} alt="Thumbnail" className="rounded-lg border border-pink-200 max-h-40" />
                          <figcaption className="text-xs opacity-60">🖼️ Thumbnail — {bundle.thumbnailOriginalName}</figcaption>
                        </figure>
                      )}
                      {bundle.teaserGifAbsolutePath && (
                        <figure className="space-y-1">
                          <img src={convertFileSrc(bundle.teaserGifAbsolutePath)} alt="Teaser GIF" className="rounded-lg border border-pink-200 max-h-40" />
                          <figcaption className="text-xs opacity-60">🎞️ Teaser — {bundle.teaserGifOriginalName}</figcaption>
                        </figure>
                      )}
                    </div>
                  </ReviewSection>
                )}
                {bundle.summary.bundleType === 'content' && (
                  <ReviewSection title={`Categories (${bundle.categories.length})`}>
                    {bundle.categories.length === 0 ? (
                      <span className="opacity-60 italic">None selected.</span>
                    ) : (
                      <div className="flex flex-wrap gap-1.5">
                        {bundle.categories.map((c, i) => (
                          <span key={c.name} className="px-2 py-0.5 rounded-full text-xs font-mono text-white" style={{ background: 'rgb(var(--persona-accent))' }}>
                            {i + 1}. {c.name}
                          </span>
                        ))}
                      </div>
                    )}
                  </ReviewSection>
                )}
              </>
            )}

            {bundle.summary.bundleType === 'custom' && (
              <ReviewSection title="Delivery">
                <ReviewRow label="Method" value={
                  bundle.deliveryKind === 'url'
                    ? (bundle.deliveryUrl
                        ? <span className="font-mono break-all">{bundle.deliveryUrl}</span>
                        : <span>🔗 URL link <em className="opacity-60">(filled in on return)</em></span>)
                    : bundle.deliveryKind === 'site'
                    ? <span className="font-mono">site #{bundle.deliverySiteId ?? '?'}</span>
                    : <em className="opacity-50">(not set)</em>
                } />
                {bundle.deliveryKind !== 'url' && (
                  <ReviewRow label="To" value={bundle.deliveryRecipient || <em className="opacity-50">(not set)</em>} />
                )}
                {bundle.deliveryKind !== 'url' && (
                  <ReviewRow label="Price" value={
                    bundle.handledInPlatform
                      ? <em>handled in delivery platform</em>
                      : bundle.priceCents != null
                      ? <span className="font-mono">${(bundle.priceCents / 100).toFixed(2)}</span>
                      : <em className="opacity-50">(not set)</em>
                  } />
                )}
                {bundle.deliveryKind === 'url' && (
                  <ReviewRow label="Recipient / price" value={<em className="opacity-60">filled in on return</em>} />
                )}
              </ReviewSection>
            )}

            {bundle.summary.bundleType === 'fansite' && (
              <ReviewSection title={`Days (${bundle.fanDays.length})`}>
                <ul className="space-y-1.5 text-sm">
                  {bundle.fanDays.slice().sort((a, b) => a.dayOfMonth - b.dayOfMonth).map((d) => (
                    <li key={d.id} className="flex items-baseline gap-2 flex-wrap">
                      <span className="font-mono text-xs opacity-60 w-6 text-right">{String(d.dayOfMonth).padStart(2, '0')}</span>
                      <span className="truncate flex-1">{d.message || <em className="opacity-50">(no message)</em>}</span>
                      <span className="text-xs opacity-50 font-mono">{d.fileCount} file{d.fileCount === 1 ? '' : 's'}</span>
                      {d.tagIds.length > 0 && (
                        <span className="basis-full flex flex-wrap gap-1 pl-6">
                          {d.tagIds
                            .map((tid) => tags.find((t) => t.id === tid))
                            .filter((t): t is ContentTag => !!t)
                            .map((t) => <ReadonlyTagPill key={t.id} tag={t} />)}
                        </span>
                      )}
                    </li>
                  ))}
                </ul>
              </ReviewSection>
            )}

            {bundle.summary.bundleType !== 'fansite' && (
              <ReviewSection title={`Files (${bundle.files.filter((f) => f.fansiteDayId === null).length})`}>
                <ul className="space-y-4">
                  {bundle.files.filter((f) => f.fansiteDayId === null).map((f, i) => (
                    <li key={f.id} className="rounded-xl border border-black/5 bg-white/60 p-3 space-y-2">
                      <div className="flex items-center gap-2 text-sm">
                        <span className="font-mono text-xs opacity-60 w-10 text-right">{String(i + 1).padStart(5, '0')}</span>
                        <span aria-hidden>{f.kind === 'video' ? '🎬' : f.kind === 'image' ? '🖼️' : '🎙️'}</span>
                        <span className="truncate flex-1 font-medium" title={f.originalName}>{f.originalName}</span>
                        <span className="text-xs opacity-50 font-mono">{f.sha256.slice(0, 8)}…</span>
                      </div>
                      <BundleFilePreview file={f} />
                    </li>
                  ))}
                </ul>
              </ReviewSection>
            )}

            {bundle.summary.bundleType === 'fansite' && (
              <ReviewSection title={`Day files (${bundle.files.filter((f) => f.fansiteDayId !== null).length})`}>
                {bundle.fanDays
                  .slice()
                  .sort((a, b) => a.dayOfMonth - b.dayOfMonth)
                  .map((d) => {
                    const dayFiles = bundle.files.filter((f) => f.fansiteDayId === d.id);
                    if (dayFiles.length === 0) return null;
                    return (
                      <div key={d.id} className="mb-3 last:mb-0">
                        <div className="text-xs font-semibold opacity-70 mb-1">
                          Day {String(d.dayOfMonth).padStart(2, '0')} — {dayFiles.length} file{dayFiles.length === 1 ? '' : 's'}
                        </div>
                        <ul className="space-y-3 pl-3 border-l-2 border-black/5">
                          {dayFiles.map((f, i) => (
                            <li key={f.id} className="rounded-xl border border-black/5 bg-white/60 p-3 space-y-2">
                              <div className="flex items-center gap-2 text-sm">
                                <span className="font-mono text-xs opacity-60 w-6 text-right">{i + 1}</span>
                                <span aria-hidden>{f.kind === 'video' ? '🎬' : f.kind === 'image' ? '🖼️' : '🎙️'}</span>
                                <span className="truncate flex-1 font-medium" title={f.originalName}>{f.originalName}</span>
                              </div>
                              <BundleFilePreview file={f} />
                            </li>
                          ))}
                        </ul>
                      </div>
                    );
                  })}
              </ReviewSection>
            )}

            {bundle.summary.bundleType !== 'fansite' && (
              <ReviewSection title={`Content tags (${bundle.summary.tagIds.length})`}>
                {bundle.summary.tagIds.length === 0 ? (
                  <span className="opacity-60 italic">None selected.</span>
                ) : (
                  <div className="flex flex-wrap gap-1.5">
                    {bundle.summary.tagIds
                      .map((tid) => tags.find((t) => t.id === tid))
                      .filter((t): t is ContentTag => !!t)
                      .map((t) => <ReadonlyTagPill key={t.id} tag={t} />)}
                  </div>
                )}
              </ReviewSection>
            )}

            <ReviewSection title="Special instructions">
              <pre className="whitespace-pre-wrap text-sm bg-amber-50 rounded-xl p-3">
                {bundle.specialInstructions || '(none)'}
              </pre>
            </ReviewSection>

            <ReviewSection title="Pre-flight checks">
              <ValidationChecklist issues={serverIssues ?? issues} />
            </ReviewSection>

            <div className="flex justify-end gap-2 pt-2">
              <button type="button" onClick={onClose} className="pretty-button secondary">Back to edit</button>
              <button
                type="button"
                onClick={onApprove}
                disabled={blocking}
                className="pretty-button"
                title={blocking ? 'Fix the blocking issues first' : 'Compose & publish'}
              >
                ✨ Approve &amp; Publish
              </button>
            </div>
          </div>
        )}

        {stage === 'composing' && (
          <div className="p-12 flex flex-col items-center gap-3 opacity-80">
            <div className="display-font text-lg">Composing bundle…</div>
            <div className="text-xs opacity-60">Hashing files · writing inner ZIP · writing outer ZIP</div>
          </div>
        )}

        {stage === 'done' && result && (
          <div className="p-6 space-y-4">
            <div className="bg-emerald-50 border border-emerald-200 rounded-2xl p-4">
              <div className="text-lg font-semibold text-emerald-800">🎉 Bundle published.</div>
              <div className="text-sm mt-1 opacity-80 font-mono break-all">{result.path}</div>
              <div className="text-xs opacity-70 mt-1">{(result.sizeBytes / 1024 / 1024).toFixed(2)} MB · {result.fileCount} files inside</div>
            </div>
            <dl className="text-xs grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 font-mono">
              <dt className="opacity-60">UID</dt><dd>{result.uid}</dd>
              <dt className="opacity-60">Inner SHA-256</dt><dd className="break-all">{result.innerSha256}</dd>
              <dt className="opacity-60">Outer SHA-256</dt><dd className="break-all">{result.outerSha256}</dd>
            </dl>
            {result.clipCreated && (
              <div className="text-sm bg-pink-50 border border-pink-200 rounded-xl px-3 py-2">
                💖 Clips row created with status <strong>Bundled</strong>.
              </div>
            )}
            <div className="flex gap-2">
              <button type="button" onClick={() => openBundleArchive(result.path)} className="pretty-button">Open ZIP</button>
              <button type="button" onClick={() => revealBundlesDir()} className="pretty-button secondary">Reveal in Finder</button>
              <button type="button" onClick={onClose} className="pretty-button secondary ml-auto">Back to list</button>
            </div>
          </div>
        )}

        {stage === 'error' && (
          <div className="p-6 space-y-3">
            <div className="bg-red-50 border border-red-200 rounded-2xl p-4 text-sm text-red-800 whitespace-pre-wrap">
              {error}
            </div>
            <button type="button" onClick={onClose} className="pretty-button secondary">Back to draft</button>
          </div>
        )}
      </div>
    </div>
  );
}

function ReviewSection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="space-y-2">
      <h3 className="text-xs font-semibold uppercase tracking-wider opacity-60">{title}</h3>
      {children}
    </section>
  );
}

function ReviewRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-baseline gap-2 text-sm">
      <span className="opacity-60 min-w-[7rem]">{label}</span>
      <span>{value}</span>
    </div>
  );
}
