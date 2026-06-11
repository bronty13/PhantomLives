import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useMutation, useQuery } from 'convex/react';
import { api } from '../../../convex/_generated/api';
import type { Id } from '../../../convex/_generated/dataModel';
import type { ThemeSetting } from '../../shared/types';
import { buildTree, breadcrumb, type PageMeta } from '../../shared/tree';
import Sidebar from './components/Sidebar';
import PageView from './components/PageView';
import QuickSwitcher from './components/QuickSwitcher';
import SettingsModal from './components/SettingsModal';
import { Star, Dots, ExportGlyph, DuplicateGlyph, TrashGlyph, SidebarToggle } from './lib/icons';
import { Menu, MenuItem, MenuSep } from './components/Popover';

export type ExportPayload = { title: string; markdown: string } | null;

export default function App(): React.JSX.Element {
  const pages = useQuery(api.pages.tree) as PageMeta[] | undefined;
  const createPage = useMutation(api.pages.create);
  const trashPage = useMutation(api.pages.trash);
  const duplicatePage = useMutation(api.pages.duplicate);
  const toggleFavorite = useMutation(api.pages.toggleFavorite);

  const [currentId, setCurrentId] = useState<string | null>(null);
  const [theme, setTheme] = useState<ThemeSetting>('system');
  const [sidebarWidth, setSidebarWidth] = useState(248);
  const [sidebarHidden, setSidebarHidden] = useState(false);
  const [switcherOpen, setSwitcherOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [pageMenuAt, setPageMenuAt] = useState<{ x: number; y: number } | null>(null);
  const [toast, setToast] = useState<string | null>(null);

  const exportRef = useRef<(() => Promise<ExportPayload>) | null>(null);
  const toastTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const showToast = useCallback((msg: string): void => {
    setToast(msg);
    if (toastTimer.current) clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(null), 2600);
  }, []);

  // ----- theme ------------------------------------------------------------
  useEffect(() => {
    void window.purpleSpace.prefsGet().then((p) => {
      setTheme(p.theme);
      setSidebarWidth(p.sidebarWidth);
      if (p.lastPageId) setCurrentId(p.lastPageId);
    });
  }, []);

  useEffect(() => {
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const apply = (): void => {
      const dark = theme === 'dark' || (theme === 'system' && mq.matches);
      document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    };
    apply();
    mq.addEventListener('change', apply);
    return () => mq.removeEventListener('change', apply);
  }, [theme]);

  const updateTheme = useCallback((t: ThemeSetting): void => {
    setTheme(t);
    void window.purpleSpace.prefsSet({ theme: t });
  }, []);

  // ----- navigation ---------------------------------------------------------
  const navigate = useCallback((id: string | null): void => {
    setCurrentId(id);
    void window.purpleSpace.prefsSet({ lastPageId: id ?? '' });
  }, []);

  const tree = useMemo(() => (pages ? buildTree(pages) : []), [pages]);
  const currentMeta = pages?.find((p) => p._id === currentId) ?? null;
  const crumbs = useMemo(
    () => (pages && currentId ? breadcrumb(pages, currentId) : []),
    [pages, currentId]
  );

  // If the current page vanished (trashed elsewhere), fall back to the first root.
  useEffect(() => {
    if (pages === undefined) return;
    if (currentId && !pages.some((p) => p._id === currentId)) {
      navigate(tree[0]?._id ?? null);
    }
  }, [pages, currentId, tree, navigate]);

  // ----- actions ------------------------------------------------------------
  const newPage = useCallback(
    async (type: 'doc' | 'database', parentId?: string): Promise<void> => {
      const id = await createPage({
        type,
        parentId: parentId as Id<'pages'> | undefined
      });
      navigate(id as string);
    },
    [createPage, navigate]
  );

  const exportCurrent = useCallback(async (): Promise<void> => {
    const payload = await exportRef.current?.();
    if (!payload) return;
    const path = await window.purpleSpace.exportMarkdown(payload.title, payload.markdown);
    if (path) showToast(`Exported to ${path}`);
  }, [showToast]);

  const trashCurrent = useCallback(async (): Promise<void> => {
    if (!currentMeta) return;
    await trashPage({ id: currentMeta._id as Id<'pages'> });
    showToast(`Moved “${currentMeta.title || 'Untitled'}” to Trash`);
  }, [currentMeta, trashPage, showToast]);

  // ----- native menu + keyboard --------------------------------------------
  useEffect(() => {
    const unsub = window.purpleSpace.onMenu((action) => {
      switch (action) {
        case 'new-page':
          void newPage('doc');
          break;
        case 'new-database':
          void newPage('database');
          break;
        case 'export-markdown':
          void exportCurrent();
          break;
        case 'quick-switcher':
          setSwitcherOpen(true);
          break;
        case 'settings':
          setSettingsOpen(true);
          break;
        case 'toggle-theme': {
          const dark = document.documentElement.dataset.theme === 'dark';
          updateTheme(dark ? 'light' : 'dark');
          break;
        }
      }
    });
    return unsub;
  }, [newPage, exportCurrent, updateTheme]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent): void => {
      if ((e.metaKey || e.ctrlKey) && (e.key === 'p' || e.key === 'k')) {
        e.preventDefault();
        setSwitcherOpen((v) => !v);
      }
      if ((e.metaKey || e.ctrlKey) && e.key === '\\') {
        e.preventDefault();
        setSidebarHidden((v) => !v);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  // ----- sidebar resize ------------------------------------------------------
  const startResize = useCallback(
    (e: React.MouseEvent): void => {
      e.preventDefault();
      const startX = e.clientX;
      const startW = sidebarWidth;
      const move = (ev: MouseEvent): void => {
        const w = Math.min(420, Math.max(192, startW + ev.clientX - startX));
        setSidebarWidth(w);
        document.documentElement.style.setProperty('--sidebar-width', `${w}px`);
      };
      const up = (ev: MouseEvent): void => {
        window.removeEventListener('mousemove', move);
        window.removeEventListener('mouseup', up);
        const w = Math.min(420, Math.max(192, startW + ev.clientX - startX));
        void window.purpleSpace.prefsSet({ sidebarWidth: w });
      };
      window.addEventListener('mousemove', move);
      window.addEventListener('mouseup', up);
    },
    [sidebarWidth]
  );

  useEffect(() => {
    document.documentElement.style.setProperty('--sidebar-width', `${sidebarWidth}px`);
  }, [sidebarWidth]);

  // ----- render ---------------------------------------------------------------
  return (
    <div className="shell">
      {!sidebarHidden && (
        <>
          <Sidebar
            tree={tree}
            pages={pages ?? []}
            currentId={currentId}
            onNavigate={navigate}
            onNewPage={newPage}
            onOpenSearch={() => setSwitcherOpen(true)}
            onOpenSettings={() => setSettingsOpen(true)}
            showToast={showToast}
          />
          <div className="sidebar-resizer" onMouseDown={startResize} />
        </>
      )}

      <div className="content">
        <div className="topbar">
          {sidebarHidden && (
            <button
              className="topbar-btn"
              onClick={() => setSidebarHidden(false)}
              title="Show sidebar (⌘\)"
              style={{ marginLeft: 72 }}
            >
              <SidebarToggle />
            </button>
          )}
          <div className="breadcrumbs">
            {crumbs.map((c, i) => (
              <React.Fragment key={c._id}>
                {i > 0 && <span className="crumb-sep">/</span>}
                <button className="crumb" onClick={() => navigate(c._id)}>
                  {c.icon && <span>{c.icon}</span>}
                  <span>{c.title || 'Untitled'}</span>
                </button>
              </React.Fragment>
            ))}
          </div>
          <div className="topbar-spacer" />
          {currentMeta && (
            <>
              <button
                className={`topbar-btn ${currentMeta.favorite ? 'fav-on' : ''}`}
                title={currentMeta.favorite ? 'Remove from Favorites' : 'Add to Favorites'}
                onClick={() => void toggleFavorite({ id: currentMeta._id as Id<'pages'> })}
              >
                <Star filled={currentMeta.favorite} />
              </button>
              <button
                className="topbar-btn"
                title="Page actions"
                onClick={(e) => {
                  const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
                  setPageMenuAt({ x: r.right - 220, y: r.bottom + 4 });
                }}
              >
                <Dots />
              </button>
            </>
          )}
        </div>

        {currentId && currentMeta ? (
          <PageView
            key={currentId}
            pageId={currentId}
            onNavigate={navigate}
            exportRef={exportRef}
            showToast={showToast}
          />
        ) : (
          <div className="empty-state">
            <div className="big">A quiet place for your work</div>
            <div>Create a page from the sidebar, or press ⌘N</div>
          </div>
        )}
      </div>

      {pageMenuAt && currentMeta && (
        <Menu at={pageMenuAt} onClose={() => setPageMenuAt(null)}>
          <MenuItem
            icon={<ExportGlyph />}
            label="Export as Markdown"
            onClick={() => void exportCurrent()}
          />
          <MenuItem
            icon={<DuplicateGlyph />}
            label="Duplicate"
            onClick={() =>
              void duplicatePage({ id: currentMeta._id as Id<'pages'> }).then((id) => {
                if (id) navigate(id as string);
              })
            }
          />
          <MenuSep />
          <MenuItem
            icon={<TrashGlyph />}
            label="Move to Trash"
            danger
            onClick={() => void trashCurrent()}
          />
        </Menu>
      )}

      {switcherOpen && (
        <QuickSwitcher
          pages={pages ?? []}
          onNavigate={(id) => {
            navigate(id);
            setSwitcherOpen(false);
          }}
          onClose={() => setSwitcherOpen(false)}
        />
      )}

      {settingsOpen && (
        <SettingsModal
          theme={theme}
          onTheme={updateTheme}
          onClose={() => setSettingsOpen(false)}
          showToast={showToast}
        />
      )}

      {toast && <div className="toast">{toast}</div>}
    </div>
  );
}
