import { useState } from 'react';
import type { MapRow } from '../data/maps';
import type { ThemePref } from '../state/uiTheme';

interface SidebarProps {
  maps: MapRow[];
  activeMapId: string | null;
  view: 'editor' | 'settings';
  themePref: ThemePref;
  onSelectMap: (id: string) => void;
  onNewMap: () => void;
  onRenameMap: (id: string, title: string) => void;
  onDeleteMap: (id: string) => void;
  onOpenSettings: () => void;
  onCycleTheme: () => void;
}

const themeGlyph: Record<ThemePref, string> = {
  auto: '🌗',
  light: '☀️',
  dark: '🌙',
};

/**
 * Fixed-width sidebar (manual layout per CLAUDE.md — no NavigationSplitView
 * equivalent). Lists maps newest-first; double-click a row to rename.
 */
export function Sidebar({
  maps,
  activeMapId,
  view,
  themePref,
  onSelectMap,
  onNewMap,
  onRenameMap,
  onDeleteMap,
  onOpenSettings,
  onCycleTheme,
}: SidebarProps) {
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [draft, setDraft] = useState('');

  const startRename = (m: MapRow) => {
    setRenamingId(m.id);
    setDraft(m.title);
  };
  const commitRename = () => {
    if (renamingId) onRenameMap(renamingId, draft);
    setRenamingId(null);
  };

  return (
    <aside className="flex w-64 shrink-0 flex-col border-r border-surface-border bg-surface-card">
      <div className="flex items-center gap-2 px-4 py-4">
        <span className="text-2xl">🧠</span>
        <span className="font-display text-xl text-brand-600">PurpleMind</span>
      </div>

      <div className="px-3">
        <button type="button" className="btn-primary w-full" onClick={onNewMap}>
          ＋ New map
        </button>
      </div>

      <div className="mt-3 flex-1 overflow-y-auto px-2">
        <div className="px-2 pb-1 text-xs font-semibold uppercase tracking-wide text-surface-muted">
          Maps ({maps.length})
        </div>
        {maps.length === 0 ? (
          <div className="px-2 py-3 text-sm text-surface-muted">
            No maps yet. Create one to get started!
          </div>
        ) : (
          <ul className="flex flex-col gap-1">
            {maps.map((m) => {
              const active = view === 'editor' && m.id === activeMapId;
              return (
                <li key={m.id}>
                  {renamingId === m.id ? (
                    <input
                      autoFocus
                      className="field"
                      value={draft}
                      onChange={(e) => setDraft(e.target.value)}
                      onBlur={commitRename}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') commitRename();
                        if (e.key === 'Escape') setRenamingId(null);
                      }}
                    />
                  ) : (
                    <div
                      className={`group flex items-center gap-1 rounded-xl px-2.5 py-2 text-sm
                        ${active ? 'bg-brand-100 text-brand-700 dark:bg-surface-border dark:text-brand-200' : 'hover:bg-surface-input'}`}
                    >
                      <button
                        type="button"
                        className="flex-1 truncate text-left font-semibold"
                        onClick={() => onSelectMap(m.id)}
                        onDoubleClick={() => startRename(m)}
                        title={m.title}
                      >
                        {m.title}
                      </button>
                      <button
                        type="button"
                        className="opacity-0 transition group-hover:opacity-100 hover:text-brand-600"
                        title="Rename"
                        onClick={() => startRename(m)}
                      >
                        ✎
                      </button>
                      <button
                        type="button"
                        className="opacity-0 transition group-hover:opacity-100 hover:text-red-500"
                        title="Delete map"
                        onClick={() => onDeleteMap(m.id)}
                      >
                        🗑
                      </button>
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </div>

      <div className="flex items-center gap-2 border-t border-surface-border p-3">
        <button
          type="button"
          className={`btn-ghost flex-1 ${view === 'settings' ? 'bg-surface-input' : ''}`}
          onClick={onOpenSettings}
        >
          ⚙ Settings
        </button>
        <button
          type="button"
          className="btn-ghost"
          title={`Theme: ${themePref} (click to change)`}
          onClick={onCycleTheme}
        >
          {themeGlyph[themePref]}
        </button>
      </div>
    </aside>
  );
}
