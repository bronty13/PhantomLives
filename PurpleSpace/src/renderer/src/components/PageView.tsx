import React, { useCallback, useEffect, useRef, useState } from 'react';
import { useMutation, useQuery } from 'convex/react';
import { api } from '../../../../convex/_generated/api';
import type { Id } from '../../../../convex/_generated/dataModel';
import { coverStyle } from '../lib/covers';
import type { ExportPayload } from '../App';
import Editor, { type EditorHandle } from './Editor';
import DatabaseView, { RowProperties, databaseToMarkdown } from './DatabaseView';
import IconPicker from './IconPicker';
import CoverPicker from './CoverPicker';

interface PageViewProps {
  pageId: string;
  onNavigate: (id: string) => void;
  exportRef: React.MutableRefObject<(() => Promise<ExportPayload>) | null>;
  showToast: (msg: string) => void;
}

export default function PageView({ pageId, onNavigate, exportRef, showToast }: PageViewProps): React.JSX.Element {
  const page = useQuery(api.pages.get, { id: pageId as Id<'pages'> });
  const parent = useQuery(
    api.pages.get,
    page?.parentId ? { id: page.parentId } : 'skip'
  );
  const rename = useMutation(api.pages.rename);
  const setIcon = useMutation(api.pages.setIcon);
  const setCover = useMutation(api.pages.setCover);

  const [iconPickerAt, setIconPickerAt] = useState<{ x: number; y: number } | null>(null);
  const [coverPickerAt, setCoverPickerAt] = useState<{ x: number; y: number } | null>(null);
  const [titleDraft, setTitleDraft] = useState<string | null>(null);
  const titleRef = useRef<HTMLTextAreaElement>(null);
  const editorRef = useRef<EditorHandle | null>(null);

  const storageId =
    page?.cover?.startsWith('storage:') === true
      ? (page.cover.slice('storage:'.length) as Id<'_storage'>)
      : null;
  const coverUrl = useQuery(api.files.getUrl, storageId ? { storageId } : 'skip');

  // The row case: parent is a database → property strip above the content.
  const isRow = parent?.type === 'database';

  // ----- title editing -------------------------------------------------------
  const commitTitle = useCallback(
    (value: string): void => {
      void rename({ id: pageId as Id<'pages'>, title: value });
    },
    [pageId, rename]
  );

  // A brand-new page (empty title) drops the caret straight into the title,
  // like Notion — type immediately after ⌘N.
  const didAutofocus = useRef(false);
  useEffect(() => {
    if (page && !page.title && !didAutofocus.current) {
      didAutofocus.current = true;
      titleRef.current?.focus();
    }
  }, [page]);

  const autosize = useCallback((): void => {
    const el = titleRef.current;
    if (el) {
      el.style.height = 'auto';
      el.style.height = `${el.scrollHeight}px`;
    }
  }, []);
  useEffect(autosize, [titleDraft, page?.title, autosize]);

  // ----- export registration ---------------------------------------------------
  useEffect(() => {
    exportRef.current = async (): Promise<ExportPayload> => {
      if (!page) return null;
      const title = page.title || 'Untitled';
      if (page.type === 'database') {
        return { title, markdown: databaseToMarkdown(title, page.dbPropsJson, rowsForExport.current) };
      }
      const body = (await editorRef.current?.toMarkdown()) ?? '';
      return { title, markdown: `# ${title}\n\n${body}` };
    };
    return () => {
      exportRef.current = null;
    };
  });
  const rowsForExport = useRef<import('../../../shared/dbmodel').RowData[]>([]);

  if (page === undefined) return <div className="page-scroll" />;
  if (page === null) return <div className="empty-state">This page no longer exists.</div>;

  const title = titleDraft ?? page.title;
  const cs = coverStyle(page.cover, coverUrl);

  return (
    <div className="page-scroll scrolly">
      {cs && (
        <div className="page-cover" style={cs}>
          <div className="page-cover-actions">
            <button className="cover-btn" onClick={(e) => setCoverPickerAt({ x: e.clientX - 360, y: e.clientY + 8 })}>
              Change cover
            </button>
            <button className="cover-btn" onClick={() => void setCover({ id: pageId as Id<'pages'>, cover: undefined })}>
              Remove
            </button>
          </div>
        </div>
      )}

      <div className={`page-head ${page.icon ? 'has-icon' : ''}`}>
        {page.icon && cs && (
          <div className="page-icon-row">
            <button className="page-icon" onClick={(e) => setIconPickerAt({ x: e.clientX, y: e.clientY + 8 })}>
              {page.icon}
            </button>
          </div>
        )}
        <div className="page-head-hover">
          {!cs && page.icon && (
            <button className="ghost-btn" style={{ fontSize: 40, padding: '0 4px' }} onClick={(e) => setIconPickerAt({ x: e.clientX, y: e.clientY + 8 })}>
              {page.icon}
            </button>
          )}
          {!page.icon && (
            <button className="ghost-btn" onClick={(e) => setIconPickerAt({ x: e.clientX, y: e.clientY + 8 })}>
              ☺ Add icon
            </button>
          )}
          {!page.cover && (
            <button className="ghost-btn" onClick={(e) => setCoverPickerAt({ x: e.clientX, y: e.clientY + 8 })}>
              🖼 Add cover
            </button>
          )}
        </div>

        <textarea
          ref={titleRef}
          className="page-title"
          rows={1}
          placeholder={page.type === 'database' ? 'Untitled database' : 'Untitled'}
          value={title}
          onChange={(e) => {
            setTitleDraft(e.target.value);
            commitTitle(e.target.value);
          }}
          onBlur={() => setTitleDraft(null)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              (e.target as HTMLTextAreaElement).blur();
              editorRef.current?.focusStart();
            }
          }}
        />

        {isRow && parent && (
          <RowProperties rowId={pageId} row={page} database={parent} />
        )}
      </div>

      {page.type === 'database' ? (
        <DatabaseView
          pageId={pageId}
          dbPropsJson={page.dbPropsJson ?? null}
          onOpenRow={onNavigate}
          rowsForExport={rowsForExport}
          showToast={showToast}
        />
      ) : (
        <div className="page-body">
          <Editor key={pageId} pageId={pageId} handleRef={editorRef} />
        </div>
      )}

      {iconPickerAt && (
        <IconPicker
          at={iconPickerAt}
          hasIcon={!!page.icon}
          onPick={(emoji) => {
            void setIcon({ id: pageId as Id<'pages'>, icon: emoji });
            setIconPickerAt(null);
          }}
          onRemove={() => {
            void setIcon({ id: pageId as Id<'pages'>, icon: undefined });
            setIconPickerAt(null);
          }}
          onClose={() => setIconPickerAt(null)}
        />
      )}

      {coverPickerAt && (
        <CoverPicker
          at={coverPickerAt}
          onPick={(cover) => {
            void setCover({ id: pageId as Id<'pages'>, cover });
            setCoverPickerAt(null);
          }}
          onClose={() => setCoverPickerAt(null)}
        />
      )}
    </div>
  );
}
