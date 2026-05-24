import { useEffect, useState } from 'react';
import { fmtSize, revealWorkingDir, revealWorkingFile,
         type BundleFileRow, type BundleManifest, type BundleSummary } from '../../data/bundles';
import { TopTrio } from './TopTrio';
import type { DocKind } from './DocDrawer';

interface Props {
  summary: BundleSummary;
  manifest: BundleManifest;
  files: BundleFileRow[];
  /** Map<inZipPath, "data:image/jpeg;base64,…">. Empty until the
   *  parallel `get_bundle_thumbnails` IPC call resolves. */
  thumbs: Record<string, string>;
  onOpenDoc: (kind: DocKind) => void;
}

type ThumbSize = 'S' | 'M' | 'L';
const THUMB_PX: Record<ThumbSize, number> = { S: 48, M: 96, L: 192 };
const THUMB_SIZE_KEY = 'sidemolly.thumbSize';

function loadSize(): ThumbSize {
  const v = localStorage.getItem(THUMB_SIZE_KEY);
  return v === 'S' || v === 'M' || v === 'L' ? v : 'M';
}

export function OverviewTab({ summary, manifest, files, thumbs, onOpenDoc }: Props) {
  const [size, setSize] = useState<ThumbSize>(loadSize);
  useEffect(() => { localStorage.setItem(THUMB_SIZE_KEY, size); }, [size]);

  // Manifest file (Phase 2+) only exists when the bundle was published
  // with the new contract. If we have a `bundle_files` row of kind
  // 'manifest', the json is on disk; otherwise the drawer just shows
  // the parsed-from-Molly.log view.
  const hasManifestJson = files.some((f) => f.kind === 'manifest');

  return (
    <div className="flex flex-col gap-4">
      <TopTrio onOpen={onOpenDoc} hasManifestJsonInBundle={hasManifestJson} />
      <FilesPane
        summary={summary}
        manifest={manifest}
        files={files}
        thumbs={thumbs}
        size={size}
        onSizeChange={setSize}
      />
    </div>
  );
}

function FilesPane({ summary, manifest, files, thumbs, size, onSizeChange }: {
  summary: BundleSummary;
  manifest: BundleManifest;
  files: BundleFileRow[];
  thumbs: Record<string, string>;
  size: ThumbSize;
  onSizeChange: (s: ThumbSize) => void;
}) {
  // Media files only — info.md / Molly.log / manifest.json are in the TopTrio.
  const media = files.filter((f) => f.kind === 'video' || f.kind === 'image' || f.kind === 'audio');
  const totalBytes = media.reduce((n, f) => n + f.sizeBytes, 0);

  return (
    <section className="sm-card">
      <header className="flex items-start justify-between mb-4 flex-wrap gap-3">
        <div>
          <h2 className="font-semibold text-base">Files ({media.length})</h2>
          <div className="text-xs mt-0.5" style={{ color: 'rgb(var(--surface-muted))' }}>
            Extracted to{' '}
            <code className="text-[10px]">
              {'~/Library/Application Support/com.phantomlives.sidemolly/work/' + summary.uid}
            </code>
            {' '}· {fmtSize(totalBytes)} total
          </div>
        </div>
        <div className="flex items-center gap-2">
          <span className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Thumbnail size</span>
          <div className="inline-flex rounded-md overflow-hidden" style={{ border: '1px solid rgb(var(--surface-border))' }}>
            {(['S', 'M', 'L'] as const).map((s) => (
              <button
                key={s}
                type="button"
                onClick={() => onSizeChange(s)}
                className="px-2.5 py-1 text-xs"
                style={{
                  background: size === s ? 'rgb(var(--surface-accent) / 0.12)' : 'rgb(var(--surface-card))',
                  color: size === s ? 'rgb(var(--surface-accent))' : 'rgb(var(--surface-text))',
                  fontWeight: size === s ? 600 : 500,
                  borderRight: s !== 'L' ? '1px solid rgb(var(--surface-border))' : 'none',
                }}
              >
                {s}
              </button>
            ))}
          </div>
          <button type="button" className="sm-button secondary text-xs"
                  onClick={() => revealWorkingDir(summary.uid).catch(() => {})}>
            📁 Reveal folder
          </button>
        </div>
      </header>

      {summary.bundleType === 'fansite'
        ? <FanSiteGroups uid={summary.uid} files={media} thumbs={thumbs} manifest={manifest} size={size} />
        : <KindGroups uid={summary.uid} files={media} thumbs={thumbs} size={size} />
      }
    </section>
  );
}

function FanSiteGroups({ uid, files, thumbs, manifest, size }: {
  uid: string; files: BundleFileRow[]; thumbs: Record<string, string>;
  manifest: BundleManifest; size: ThumbSize;
}) {
  const byDay = new Map<number, BundleFileRow[]>();
  for (const f of files) {
    const d = f.fansiteDayOfMonth ?? 0;
    if (!byDay.has(d)) byDay.set(d, []);
    byDay.get(d)!.push(f);
  }
  const days = Array.from(byDay.keys()).sort((a, b) => a - b);
  const messageByDay = new Map(manifest.fanDays.map((d) => [d.dayOfMonth, d.message]));

  return (
    <div className="flex flex-col gap-4">
      {days.map((d) => {
        const dayFiles = byDay.get(d)!;
        const message = messageByDay.get(d);
        return (
          <div key={d}>
            <div className="flex items-baseline gap-3 mb-1.5"
                 style={{ borderBottom: '1px solid rgb(var(--surface-border))', paddingBottom: 4 }}>
              <div className="display-font text-sm" style={{ color: 'rgb(var(--surface-accent))' }}>
                FAN-SITE DAY {String(d).padStart(2, '0')}
              </div>
              <div className="text-[11px]" style={{ color: 'rgb(var(--surface-muted))' }}>
                {dayFiles.length} file{dayFiles.length === 1 ? '' : 's'}
              </div>
              {message && (
                <div className="text-xs flex-1 min-w-0 truncate" style={{ color: 'rgb(var(--surface-text) / 0.8)' }}>
                  · {message}
                </div>
              )}
            </div>
            <ul className="flex flex-col gap-1">
              {dayFiles.map((f) => (
                <FileRow key={f.inZipPath} uid={uid} file={f} thumbs={thumbs} size={size}
                  prefix={`D${String(d).padStart(2, '0')}/${String(f.position).padStart(2, '0')}`} />
              ))}
            </ul>
          </div>
        );
      })}
    </div>
  );
}

function KindGroups({ uid, files, thumbs, size }: {
  uid: string; files: BundleFileRow[]; thumbs: Record<string, string>; size: ThumbSize;
}) {
  const KIND_ORDER: BundleFileRow['kind'][] = ['video', 'image', 'audio'];
  const byKind = new Map<string, BundleFileRow[]>();
  for (const f of files) {
    if (!byKind.has(f.kind)) byKind.set(f.kind, []);
    byKind.get(f.kind)!.push(f);
  }
  return (
    <div className="flex flex-col gap-4">
      {KIND_ORDER.filter((k) => byKind.has(k)).map((kind) => {
        const rows = byKind.get(kind)!;
        return (
          <div key={kind}>
            <div className="flex items-baseline gap-3 mb-1.5"
                 style={{ borderBottom: '1px solid rgb(var(--surface-border))', paddingBottom: 4 }}>
              <div className="display-font text-sm" style={{ color: 'rgb(var(--surface-accent))' }}>
                {kind.toUpperCase()}
              </div>
              <div className="text-[11px]" style={{ color: 'rgb(var(--surface-muted))' }}>
                {rows.length} file{rows.length === 1 ? '' : 's'}
              </div>
            </div>
            <ul className="flex flex-col gap-1">
              {rows.map((f) => (
                <FileRow key={f.inZipPath} uid={uid} file={f} thumbs={thumbs} size={size}
                  prefix={f.position > 0 ? `#${String(f.position).padStart(5, '0')}` : ''} />
              ))}
            </ul>
          </div>
        );
      })}
    </div>
  );
}

function FileRow({ uid, file, thumbs, size, prefix }: {
  uid: string; file: BundleFileRow; thumbs: Record<string, string>;
  size: ThumbSize; prefix: string;
}) {
  const px = THUMB_PX[size];
  return (
    <li className="flex items-center gap-3 py-1"
        style={{ borderBottom: '1px solid rgb(var(--surface-border) / 0.5)' }}
    >
      <Thumb file={file} dataUrl={thumbs[file.inZipPath]} px={px} />
      {prefix && (
        <span className="shrink-0 font-mono text-xs" style={{ color: 'rgb(var(--surface-muted))', minWidth: 64 }}>
          {prefix}
        </span>
      )}
      <span className="flex-1 min-w-0 truncate font-mono text-xs">{file.originalName}</span>
      <span className="shrink-0 text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
        {fmtSize(file.sizeBytes)}
      </span>
      <code className="shrink-0 text-[10px]" title={file.sha256} style={{ color: 'rgb(var(--surface-muted))' }}>
        {file.sha256.slice(0, 8)}…
      </code>
      <button type="button" onClick={() => revealWorkingFile(uid, file.inZipPath).catch(() => {})}
              title="Reveal in Finder"
              className="shrink-0 px-1 text-sm opacity-50 hover:opacity-100">
        📁
      </button>
    </li>
  );
}

function Thumb({ file, dataUrl, px }: {
  file: BundleFileRow; dataUrl: string | undefined; px: number;
}) {
  // `dataUrl` is the entry from the bundle's thumbnails map fetched
  // server-side as a base64 `data:image/jpeg;base64,…` payload. Missing
  // entries (videos we couldn't ffmpeg, HEIC images, info/log/manifest
  // kinds) fall through to the kind-glyph block.
  if (!dataUrl) {
    return (
      <div
        className="shrink-0 flex items-center justify-center rounded text-base"
        style={{
          width: px, height: px,
          background: 'rgb(var(--surface-base))',
          border: '1px solid rgb(var(--surface-border))',
        }}
        title={file.thumbnailPath ?? file.kind}
      >
        {kindGlyph(file.kind)}
      </div>
    );
  }
  return (
    <img
      src={dataUrl}
      alt={file.originalName}
      className="shrink-0 object-cover rounded"
      style={{
        width: px, height: px,
        border: '1px solid rgb(var(--surface-border))',
      }}
    />
  );
}

function kindGlyph(kind: BundleFileRow['kind']): string {
  switch (kind) {
    case 'video':    return '🎬';
    case 'image':    return '🖼';
    case 'audio':    return '🎙';
    case 'info':     return '📄';
    case 'log':      return '📜';
    case 'manifest': return '🗂';
    case 'other':    return '·';
  }
}
