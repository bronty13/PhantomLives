import { useCallback, useEffect, useState } from 'react';
import type { AppSettings, CalendarBundle, FillerEntry, Theme } from '../model/types';
import { APP_VERSION, DEFAULT_APP_SETTINGS } from '../model/types';
import {
  deleteBundle, ensureSeeded, getSettings, listBundles, listCustomSayings, listThemes,
  saveBundle, saveSettings,
} from '../storage/db';
import { sayingPool } from '../data/sayings';
import { Home } from './screens/Home';
import { CalendarEditor } from './screens/CalendarEditor';
import { NewBundleWizard } from './screens/NewBundleWizard';
import { SettingsModal } from './screens/Settings';

export function App() {
  const [loading, setLoading] = useState(true);
  const [settings, setSettings] = useState<AppSettings | null>(null);
  const [themes, setThemes] = useState<Theme[]>([]);
  const [bundles, setBundles] = useState<CalendarBundle[]>([]);
  const [customSayings, setCustomSayings] = useState<FillerEntry[]>([]);
  const [active, setActive] = useState<CalendarBundle | null>(null);
  const [modal, setModal] = useState<'none' | 'new' | 'settings'>('none');

  const reloadBundles = useCallback(async () => setBundles(await listBundles()), []);
  const reloadThemes = useCallback(async () => setThemes(await listThemes()), []);
  const reloadSayings = useCallback(async () => setCustomSayings(await listCustomSayings()), []);

  useEffect(() => {
    (async () => {
      try {
        await ensureSeeded();
        setSettings(await getSettings());
        await reloadThemes();
        await reloadBundles();
        await reloadSayings();
      } catch (e) {
        // Never let a storage hiccup hang the UI on the loading screen.
        console.error('CalendarMaker load error:', e);
        setSettings((s) => s ?? { ...DEFAULT_APP_SETTINGS });
      } finally {
        setLoading(false);
      }
    })();
  }, [reloadBundles, reloadThemes, reloadSayings]);

  const onSaveSettings = async (s: AppSettings) => {
    await saveSettings(s);
    setSettings(s);
  };

  const openBundle = (b: CalendarBundle) => setActive(b);

  const onBundleChange = async (b: CalendarBundle) => {
    setActive(b);
    await saveBundle(b);
  };

  const onCreated = async (b: CalendarBundle) => {
    await saveBundle(b);
    await reloadBundles();
    setModal('none');
    setActive(b);
  };

  const onDelete = async (id: string) => {
    await deleteBundle(id);
    await reloadBundles();
  };

  if (loading || !settings) {
    return <div className="empty" style={{ paddingTop: 120 }}>Loading CalendarMaker…</div>;
  }

  const activeTheme = active ? themes.find((t) => t.id === active.themeId) ?? themes[0] : null;
  const sayings = sayingPool(customSayings);

  return (
    <div className="app">
      <div className="topbar">
        <div className="brand">Calendar<span>Maker</span></div>
        <div className="spacer" />
        {active ? (
          <button className="ghost" onClick={() => { setActive(null); reloadBundles(); }}>← All calendars</button>
        ) : (
          <>
            <button onClick={() => setModal('settings')}>Settings</button>
            <button className="primary" onClick={() => setModal('new')}>+ New calendar</button>
          </>
        )}
        <span className="ver">v{APP_VERSION}</span>
      </div>

      <div className="content">
        <div className="wrap">
          {active && activeTheme ? (
            <CalendarEditor
              bundle={active}
              theme={activeTheme}
              themes={themes}
              settings={settings}
              sayings={sayings}
              onChange={onBundleChange}
              onThemesChanged={reloadThemes}
            />
          ) : (
            <Home
              bundles={bundles}
              settings={settings}
              sayings={sayings}
              onOpen={openBundle}
              onDelete={onDelete}
              onNew={() => setModal('new')}
              onImported={async (b) => { await saveBundle(b); await reloadBundles(); setActive(b); }}
              onImportTheme={reloadThemes}
            />
          )}
        </div>
      </div>

      {modal === 'new' && (
        <NewBundleWizard
          themes={themes}
          settings={settings}
          onCancel={() => setModal('none')}
          onCreate={onCreated}
        />
      )}
      {modal === 'settings' && (
        <SettingsModal
          settings={settings}
          themes={themes}
          customSayings={customSayings}
          onClose={() => setModal('none')}
          onSave={onSaveSettings}
          onSayingsChanged={reloadSayings}
        />
      )}
    </div>
  );
}
