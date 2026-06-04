import { useCallback, useEffect, useState } from 'react';
import { Sidebar } from './components/Sidebar';
import { MapEditorView } from './views/MapEditorView';
import { WelcomeView } from './views/WelcomeView';
import { SettingsView } from './views/SettingsView';
import { useUiTheme } from './state/uiTheme';
import {
  createMap,
  deleteMap,
  listMaps,
  renameMap,
  type MapRow,
} from './data/maps';

type View = 'editor' | 'settings';

export default function App() {
  const { pref, cycle } = useUiTheme();
  const [maps, setMaps] = useState<MapRow[]>([]);
  const [activeMapId, setActiveMapId] = useState<string | null>(null);
  const [view, setView] = useState<View>('editor');
  const [loaded, setLoaded] = useState(false);

  const refreshMaps = useCallback(
    async (selectId?: string) => {
      const rows = await listMaps();
      setMaps(rows);
      if (selectId) {
        setActiveMapId(selectId);
        setView('editor');
      } else if (activeMapId && !rows.some((m) => m.id === activeMapId)) {
        setActiveMapId(rows[0]?.id ?? null);
      }
      setLoaded(true);
    },
    [activeMapId],
  );

  const LAST_MAP_KEY = 'pm-last-map';

  // Initial load: list maps and reopen the last-opened map if it still exists.
  useEffect(() => {
    void (async () => {
      const rows = await listMaps();
      setMaps(rows);
      const last = (() => {
        try {
          return localStorage.getItem(LAST_MAP_KEY);
        } catch {
          return null;
        }
      })();
      if (last && rows.some((m) => m.id === last)) {
        setActiveMapId(last);
        setView('editor');
      }
      setLoaded(true);
    })();
  }, []);

  // Remember the active map so we can reopen it next launch.
  useEffect(() => {
    if (!activeMapId) return;
    try {
      localStorage.setItem(LAST_MAP_KEY, activeMapId);
    } catch {
      /* private mode — ignore */
    }
  }, [activeMapId]);

  const handleNewMap = useCallback(async () => {
    const map = await createMap('Untitled map');
    await refreshMaps(map.id);
  }, [refreshMaps]);

  const handleSelectMap = useCallback((id: string) => {
    setActiveMapId(id);
    setView('editor');
  }, []);

  const handleRename = useCallback(
    async (id: string, title: string) => {
      await renameMap(id, title);
      await refreshMaps();
    },
    [refreshMaps],
  );

  const handleDelete = useCallback(
    async (id: string) => {
      if (!confirm('Delete this map and all its nodes? This cannot be undone.')) return;
      await deleteMap(id);
      if (activeMapId === id) setActiveMapId(null);
      await refreshMaps();
    },
    [activeMapId, refreshMaps],
  );

  const activeMap = maps.find((m) => m.id === activeMapId) ?? null;

  return (
    <div className="flex h-full w-full">
      <Sidebar
        maps={maps}
        activeMapId={activeMapId}
        view={view}
        themePref={pref}
        onSelectMap={handleSelectMap}
        onNewMap={handleNewMap}
        onRenameMap={handleRename}
        onDeleteMap={handleDelete}
        onOpenSettings={() => setView('settings')}
        onCycleTheme={cycle}
      />
      <main className="flex-1 overflow-hidden">
        {view === 'settings' ? (
          <SettingsView />
        ) : activeMap ? (
          <MapEditorView
            key={activeMap.id}
            mapId={activeMap.id}
            title={activeMap.title}
            onMapsChanged={refreshMaps}
          />
        ) : (
          <WelcomeView hasMaps={loaded && maps.length > 0} onNewMap={handleNewMap} />
        )}
      </main>
    </div>
  );
}
