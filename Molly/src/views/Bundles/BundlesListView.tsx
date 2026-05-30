import { useCallback, useEffect, useState } from 'react';
import {
  type BundleSummary,
  type BundleType,
  createBundle,
  deleteBundleDraft,
  deletePublishedBundle,
  listBundles,
  openBundleArchive,
} from '../../data/bundles';
import { ALL_PERSONAS, type Persona } from '../../data/personas';
import { listPersonas } from '../../data/personas';
import { listContentTags, type ContentTag } from '../../data/contentTags';
import { ReadonlyTagPill } from './components/ContentTagPicker';
import { ContentBundleForm } from './ContentBundleForm';
import { CustomBundleForm } from './CustomBundleForm';
import { FanSiteBundleForm } from './FanSiteBundleForm';
import { YouTubeBundleForm } from './YouTubeBundleForm';
import { PublishWizard } from './PublishWizard';
import { ImportReturnFileWizard } from './ImportReturnFileWizard';

interface Props {
  active: Persona;
}

type RouteState =
  | { kind: 'list' }
  | { kind: 'draft'; uid: string }
  | { kind: 'wizard'; uid: string };

export function BundlesListView({ active }: Props) {
  const [route, setRoute] = useState<RouteState>({ kind: 'list' });
  const [items, setItems] = useState<BundleSummary[]>([]);
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [tags, setTags] = useState<ContentTag[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [creatingType, setCreatingType] = useState<BundleType | null>(null);
  const [showImport, setShowImport] = useState(false);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const all = await listBundles(null);
      setItems(all);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    let alive = true;
    refresh();
    listPersonas().then((p) => { if (alive) setPersonas(p); }).catch(() => {});
    listContentTags().then((t) => { if (alive) setTags(t); }).catch(() => {});
    return () => { alive = false; };
  }, [refresh]);

  const filteredItems = active.code === 'ALL'
    ? items
    : items.filter((b) => b.personaCode === active.code);

  async function startNew(type: BundleType) {
    setCreatingType(type);
    try {
      const code = active.code === ALL_PERSONAS.code ? null : active.code;
      const uid = await createBundle(type, code);
      await refresh();
      setRoute({ kind: 'draft', uid });
    } catch (e) {
      setError(String(e));
    } finally {
      setCreatingType(null);
    }
  }

  async function onDeleteBundle(uid: string, state: string) {
    const ok = state === 'published'
      ? confirm(
          'Unpublish this bundle?\n\n' +
          'The ZIP file in ~/Downloads/Molly bundles/ will be removed and ' +
          'the bundle will become editable again. ' +
          'Everything you typed in (title, files, categories, etc.) is preserved. ' +
          'The linked Clips row (if any) also survives.',
        )
      : confirm('Delete this draft and all uploaded files? This cannot be undone.');
    if (!ok) return;
    try {
      if (state === 'published') {
        await deletePublishedBundle(uid);
      } else {
        await deleteBundleDraft(uid);
      }
      await refresh();
    } catch (e) {
      setError(String(e));
    }
  }

  if (route.kind === 'draft') {
    const b = items.find((it) => it.uid === route.uid);
    const locked = b?.state === 'published';
    const onUnlock = async () => {
      const ok = confirm(
        'Unpublish this bundle?\n\n' +
        'The ZIP file in ~/Downloads/Molly bundles/ will be removed and ' +
        'the bundle will become editable again. ' +
        'Everything you typed in (title, files, categories, etc.) is preserved. ' +
        'The linked Clips row (if any) also survives.',
      );
      if (!ok) return;
      try {
        await deletePublishedBundle(route.uid);
        await refresh();
      } catch (e) {
        setError(String(e));
      }
    };
    const closeProps = {
      uid: route.uid,
      locked,
      onPublishRequested: () => setRoute({ kind: 'wizard', uid: route.uid }),
      onClose: () => { setRoute({ kind: 'list' }); refresh(); },
      onDeleted: () => refresh(),
      onUnlock: locked ? onUnlock : undefined,
    };
    switch (b?.bundleType) {
      case 'content': return <ContentBundleForm {...closeProps} />;
      case 'youtube': return <YouTubeBundleForm {...closeProps} />;
      case 'custom':  return <CustomBundleForm {...closeProps} />;
      case 'fansite': return <FanSiteBundleForm {...closeProps} />;
      default:
        return (
          <div className="p-8 max-w-2xl space-y-3">
            <button type="button" onClick={() => setRoute({ kind: 'list' })} className="pretty-button secondary">← Back to list</button>
            <div className="pretty-card text-sm">Unknown bundle type: <code>{b?.bundleType}</code></div>
          </div>
        );
    }
  }

  if (route.kind === 'wizard') {
    return (
      <PublishWizard
        uid={route.uid}
        onClose={() => setRoute({ kind: 'draft', uid: route.uid })}
        onPublished={() => { refresh(); }}
      />
    );
  }

  return (
    <div className="p-8 space-y-4 max-w-5xl">
      <header className="space-y-1">
        <h2 className="display-font text-2xl font-bold persona-accent">🎁 Bundles</h2>
        <p className="opacity-70 text-sm">
          Compose delivery packages for Robert. Four flavors — Content, YouTube,
          Custom and Fan Site.
        </p>
      </header>

      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          onClick={() => startNew('content')}
          disabled={creatingType !== null}
          className="pretty-button"
        >
          ＋ New Content Bundle
        </button>
        <button
          type="button"
          onClick={() => startNew('custom')}
          disabled={creatingType !== null}
          className="pretty-button secondary"
        >
          ＋ New Custom Bundle
        </button>
        <button
          type="button"
          onClick={() => startNew('fansite')}
          disabled={creatingType !== null}
          className="pretty-button secondary"
        >
          ＋ New Fan Site Bundle
        </button>
        <button
          type="button"
          onClick={() => startNew('youtube')}
          disabled={creatingType !== null}
          className="pretty-button secondary"
        >
          ▶️ New YouTube Bundle
        </button>
        <button
          type="button"
          onClick={() => setShowImport(true)}
          className="pretty-button secondary ml-auto"
          title="Import SideMolly's return file (post-bundle ZIP)"
        >
          📥 Import Return File
        </button>
      </div>

      {showImport && (
        <ImportReturnFileWizard
          onClose={() => setShowImport(false)}
          onImported={() => { refresh(); }}
        />
      )}

      {error && (
        <div className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-xl px-3 py-2">{error}</div>
      )}

      {loading ? (
        <div className="opacity-60 italic">Loading bundles…</div>
      ) : filteredItems.length === 0 ? (
        <div className="pretty-card text-center text-sm opacity-70">
          No bundles yet — click <strong>＋ New Content Bundle</strong> to start.
        </div>
      ) : (
        <ul className="space-y-2">
          {filteredItems.map((b) => {
            const persona = personas.find((p) => p.code === b.personaCode);
            return (
              <li
                key={b.uid}
                className="pretty-card flex items-center gap-3 hover:shadow-md transition cursor-pointer"
                onClick={() => setRoute({ kind: 'draft', uid: b.uid })}
              >
                <span className="text-2xl" aria-hidden>
                  {b.bundleType === 'content' ? '🎁' : b.bundleType === 'youtube' ? '▶️' : b.bundleType === 'custom' ? '✨' : '📅'}
                </span>
                <div className="flex-1 min-w-0">
                  <div className="flex items-baseline gap-2 flex-wrap">
                    <span className="font-mono text-xs opacity-60">{b.uid}</span>
                    <span className="text-xs uppercase tracking-wider opacity-50">{b.bundleType}</span>
                    <StatePill state={b.state} aging={b.agingFlag} />
                    {b.completedAt && <ImportedBadge deleteAfter={b.deleteAfter} alreadyPurged={b.state === 'purged'} />}
                  </div>
                  <div className="font-medium truncate">{b.title || <em className="opacity-50">(untitled)</em>}</div>
                  <div className="text-xs opacity-60 flex flex-wrap gap-x-3 gap-y-0.5">
                    <span>persona: {persona?.name ?? b.personaCode ?? '(unassigned)'}</span>
                    <span>{b.fileCount} file{b.fileCount === 1 ? '' : 's'}</span>
                    {b.goLiveDate && <span>go-live: {b.goLiveDate}</span>}
                    {b.publishedAt && <span>published: {b.publishedAt.slice(0, 10)}</span>}
                  </div>
                  {b.tagIds.length > 0 && (
                    <div className="flex flex-wrap gap-1 mt-1">
                      {b.tagIds
                        .map((tid) => tags.find((t) => t.id === tid))
                        .filter((t): t is ContentTag => !!t)
                        .map((t) => <ReadonlyTagPill key={t.id} tag={t} />)}
                    </div>
                  )}
                </div>
                {b.state === 'published' && b.bundlePath && (
                  <button
                    type="button"
                    onClick={(e) => { e.stopPropagation(); openBundleArchive(b.bundlePath!); }}
                    className="pretty-button secondary text-xs"
                  >
                    Open ZIP
                  </button>
                )}
                <button
                  type="button"
                  onClick={(e) => { e.stopPropagation(); onDeleteBundle(b.uid, b.state); }}
                  className={b.state === 'published' ? 'pretty-button secondary text-xs' : 'pretty-button danger text-xs'}
                  title={b.state === 'published'
                    ? 'Remove the ZIP and unlock the draft for re-editing (data preserved)'
                    : 'Delete the draft + all uploaded files (cannot be undone)'}
                >
                  {b.state === 'published' ? '📝 Unpublish & edit' : 'Delete draft'}
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

function ImportedBadge({ deleteAfter, alreadyPurged }: { deleteAfter: string | null; alreadyPurged: boolean }) {
  const tail = alreadyPurged
    ? ' · already cleaned up'
    : deleteAfter
      ? ` · cleanup ${deleteAfter.slice(0, 10)}`
      : '';
  return (
    <span
      className="text-[11px] font-semibold px-1.5 py-0.5 rounded-full"
      style={{ background: '#DCFCE7', color: '#166534' }}
      title="Return file from SideMolly has been imported"
    >
      ✓ Imported{tail}
    </span>
  );
}

function StatePill({ state, aging }: { state: string; aging: string }) {
  let bg = '#E5E7EB', color = '#374151', label: string = state;
  if (state === 'draft') { bg = '#FEE7F0'; color = '#9D174D'; label = 'draft'; }
  if (state === 'published') { bg = '#DCFCE7'; color = '#166534'; label = 'published'; }
  if (state === 'purged') { bg = '#F1F5F9'; color = '#475569'; label = 'purged'; }
  return (
    <span className="text-[11px] font-semibold px-1.5 py-0.5 rounded-full" style={{ background: bg, color }}>
      {label}
      {state === 'draft' && aging !== 'fresh' && (
        <span className="ml-1" title={`${aging} draft`}>
          {aging === 'overdue' ? '🌼' : '🌷'}
        </span>
      )}
    </span>
  );
}
