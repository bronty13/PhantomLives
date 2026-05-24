import { useEffect, useState } from 'react';
import { Sidebar, type ViewKey } from './components/Sidebar';
import { InboxView } from './views/Inbox/InboxView';
import { SettingsView } from './views/Settings/SettingsView';
import { ManualView } from './views/Manual/ManualView';

export default function App() {
  const [view, setView] = useState<ViewKey>('inbox');
  const [sidebarVisible, setSidebarVisible] = useState(true);

  // Cmd+S / Ctrl+S toggles the sidebar. Same shortcut Molly uses.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const mod = e.metaKey || e.ctrlKey;
      if (mod && (e.key === 's' || e.key === 'S')) {
        e.preventDefault();
        setSidebarVisible((v) => !v);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  return (
    <div className="flex h-full" style={{ background: 'rgb(var(--surface-base))' }}>
      <Sidebar active={view} onSelect={setView} visible={sidebarVisible} />
      <main className="flex-1 overflow-y-auto">
        {view === 'inbox' && <InboxView />}
        {view === 'settings' && <SettingsView />}
        {view === 'manual' && <ManualView />}
      </main>
    </div>
  );
}
