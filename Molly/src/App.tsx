import { useEffect, useState } from 'react';
import { Sidebar, type ViewKey } from './components/Sidebar';
import { PersonaSwitcher } from './components/PersonaSwitcher';
import { usePersonas, type Persona } from './state/personas';
import { useApplyPersonaTheme } from './state/theme';
import { BackupSettings } from './views/Settings/BackupSettings';

function PlaceholderView({ title, blurb, active }: { title: string; blurb: string; active: Persona }) {
  return (
    <div className="p-8 max-w-3xl">
      <div className="pretty-card">
        <h2 className="display-font text-2xl font-bold persona-accent">{title}</h2>
        <p className="mt-2 opacity-80">{blurb}</p>
        <p className="mt-4 text-sm opacity-60">
          Currently filtered by <span className="font-semibold">{active.name}</span>. This view ships in a later
          phase — Phase 0 ships the shell, theming, and backup only.
        </p>
      </div>
    </div>
  );
}

function HomeView({ active }: { active: Persona }) {
  return (
    <div className="p-8 space-y-4 max-w-4xl">
      <div className="pretty-card">
        <div className="text-xs uppercase tracking-wider opacity-60">welcome back</div>
        <h2 className="display-font text-3xl font-bold persona-accent mt-1">Hi, I'm Molly 💕</h2>
        <p className="opacity-80 mt-2">
          I'm your little command center for everything you make. Pick a persona at the top to filter the whole app
          to that vibe, or stay on <strong>★ All</strong> for the cross-persona view.
        </p>
        <div className="mt-4 grid grid-cols-3 gap-3">
          <div className="p-3 rounded-xl persona-tint border border-black/5">
            <div className="text-xs opacity-60">Active persona</div>
            <div className="font-semibold persona-text mt-1">{active.name}</div>
          </div>
          <div className="p-3 rounded-xl persona-tint border border-black/5">
            <div className="text-xs opacity-60">Coming up</div>
            <div className="font-semibold persona-text mt-1">Scheduler in Phase 3</div>
          </div>
          <div className="p-3 rounded-xl persona-tint border border-black/5">
            <div className="text-xs opacity-60">Clips imported</div>
            <div className="font-semibold persona-text mt-1">MasterClipper import in Phase 2</div>
          </div>
        </div>
      </div>
    </div>
  );
}

function SettingsView({ active }: { active: Persona }) {
  return (
    <div className="p-8 space-y-4 max-w-3xl">
      <div>
        <h2 className="display-font text-2xl font-bold persona-accent">Settings</h2>
        <p className="opacity-70 text-sm">Persona ({active.name}) · Sites · Products · Interests · Backup</p>
      </div>
      <BackupSettings />
      <div className="pretty-card text-sm opacity-70">
        Other settings tabs (personas, sites, products, interests) arrive in Phase 1.
      </div>
    </div>
  );
}

const COPY: Record<ViewKey, { title: string; blurb: string }> = {
  home:      { title: 'Home',           blurb: '' },
  calendar:  { title: 'Calendar',       blurb: 'Clip releases on a month grid, color-dotted per persona. Arrives in Phase 2.' },
  clips:     { title: 'Clips',          blurb: 'Imported from MasterClipper CSV exports. Arrives in Phase 2.' },
  customers: { title: 'Customers',      blurb: 'UID, names, multi-email, products, interests, rich-text notes. Arrives in Phase 1.' },
  helper:    { title: 'Molly Helper',   blurb: "A persona-aware site launcher with username reminders. Arrives in Phase 1." },
  income:    { title: 'Income',         blurb: 'Adhoc one-offs + per-site monthly wizard. Arrives in Phase 4.' },
  expenses:  { title: 'Expenses',       blurb: 'One-off + recurring expenses, attachments, MTD/YTD. Arrives in Phase 4.' },
  reports:   { title: 'Reports',        blurb: 'MTD / Prior MTD / YTD per persona and ALL. Arrives in Phase 4.' },
  settings:  { title: 'Settings',       blurb: '' },
};

export default function App() {
  const { personas, active, choose, loading, error } = usePersonas();
  useApplyPersonaTheme(active);

  const [view, setView] = useState<ViewKey>('home');
  const [sidebarVisible, setSidebarVisible] = useState(true);

  // Cmd/Ctrl+S toggles the sidebar (PhantomLives convention).
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const mod = e.metaKey || e.ctrlKey;
      if (mod && e.key.toLowerCase() === 's' && !e.shiftKey && !e.altKey) {
        e.preventDefault();
        setSidebarVisible((v) => !v);
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, []);

  if (loading) {
    return <div className="h-screen flex items-center justify-center display-font text-xl persona-accent">Molly is waking up…</div>;
  }
  if (error) {
    return (
      <div className="h-screen flex items-center justify-center p-8">
        <div className="pretty-card max-w-md">
          <h2 className="display-font text-xl persona-accent mb-2">Eek — couldn't open the database.</h2>
          <p className="text-sm opacity-80">{error}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="h-screen flex" style={{ background: 'rgb(var(--persona-tint))' }}>
      <Sidebar active={view} onSelect={setView} visible={sidebarVisible} />
      <div className="flex-1 flex flex-col min-w-0">
        <PersonaSwitcher
          personas={personas}
          active={active}
          onChoose={choose}
          onToggleSidebar={() => setSidebarVisible((v) => !v)}
        />
        <main className="flex-1 overflow-y-auto">
          {view === 'home' && <HomeView active={active} />}
          {view === 'settings' && <SettingsView active={active} />}
          {view !== 'home' && view !== 'settings' && (
            <PlaceholderView title={COPY[view].title} blurb={COPY[view].blurb} active={active} />
          )}
        </main>
      </div>
    </div>
  );
}
