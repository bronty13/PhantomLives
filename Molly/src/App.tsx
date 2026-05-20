import { useCallback, useEffect, useState } from 'react';
import { Sidebar, type ViewKey } from './components/Sidebar';
import { PersonaSwitcher } from './components/PersonaSwitcher';
import { usePersonas, type Persona } from './state/personas';
import { useApplyPersonaTheme } from './state/theme';
import { SettingsView } from './views/Settings/SettingsView';
import { CustomerListView } from './views/Customers/CustomerListView';
import { MollyHelper } from './views/MollyHelper/MollyHelper';
import { HomeDashboard } from './views/Home/HomeDashboard';
import { CalendarView } from './views/Calendar/CalendarView';
import { ClipsListView } from './views/Clips/ClipsListView';
import { RemindersView } from './views/Reminders/RemindersView';
import { materializeOccurrences, pendingCounts } from './data/occurrences';

function PlaceholderView({ title, blurb, active }: { title: string; blurb: string; active: Persona }) {
  return (
    <div className="p-8 max-w-3xl">
      <div className="pretty-card">
        <h2 className="display-font text-2xl font-bold persona-accent">{title}</h2>
        <p className="mt-2 opacity-80">{blurb}</p>
        <p className="mt-4 text-sm opacity-60">
          Currently filtered by <span className="font-semibold">{active.name}</span>.
        </p>
      </div>
    </div>
  );
}

const COPY: Record<Exclude<ViewKey, 'home' | 'settings' | 'customers' | 'helper' | 'calendar' | 'clips' | 'reminders'>, { title: string; blurb: string }> = {
  income:   { title: 'Income',   blurb: 'Adhoc one-offs + per-site monthly wizard. Arrives in Phase 4.' },
  expenses: { title: 'Expenses', blurb: 'One-off + recurring expenses, attachments, MTD/YTD. Arrives in Phase 4.' },
  reports:  { title: 'Reports',  blurb: 'MTD / Prior MTD / YTD per persona and ALL. Arrives in Phase 4.' },
};

export default function App() {
  const { personas, active, choose, loading, error, refresh } = usePersonas();
  useApplyPersonaTheme(active);

  const [view, setView] = useState<ViewKey>('home');
  const [sidebarVisible, setSidebarVisible] = useState(true);
  const [pendingTotal, setPendingTotal] = useState(0);

  const refreshCounts = useCallback(async () => {
    try {
      const c = await pendingCounts(active.code === 'ALL' ? undefined : { personaCode: active.code });
      setPendingTotal(c.todayCount + c.overdueCount);
    } catch (e) {
      console.warn('pendingCounts failed', e);
    }
  }, [active.code]);

  // Materialize occurrences on app launch + every 30 min, then refresh count.
  useEffect(() => {
    let alive = true;
    const tick = async () => {
      try {
        await materializeOccurrences();
        if (alive) await refreshCounts();
      } catch (e) {
        console.warn('materialize failed', e);
      }
    };
    tick();
    const id = window.setInterval(tick, 30 * 60_000);
    return () => {
      alive = false;
      window.clearInterval(id);
    };
  }, [refreshCounts]);

  // Refresh count when active persona changes.
  useEffect(() => {
    refreshCounts();
  }, [refreshCounts]);

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

  let body: React.ReactNode;
  switch (view) {
    case 'home':      body = <HomeDashboard active={active} onGoTo={(v) => setView(v)} />; break;
    case 'reminders': body = <RemindersView active={active} onCountsChanged={refreshCounts} />; break;
    case 'calendar':  body = <CalendarView active={active} />; break;
    case 'clips':     body = <ClipsListView active={active} />; break;
    case 'customers': body = <CustomerListView active={active} />; break;
    case 'helper':    body = <MollyHelper active={active} />; break;
    case 'settings':  body = <SettingsView active={active} onPersonasChanged={refresh} />; break;
    default:          body = <PlaceholderView title={COPY[view].title} blurb={COPY[view].blurb} active={active} />;
  }

  return (
    <div className="h-screen flex" style={{ background: 'rgb(var(--persona-tint))' }}>
      <Sidebar active={view} onSelect={setView} visible={sidebarVisible} pendingCount={pendingTotal} />
      <div className="flex-1 flex flex-col min-w-0">
        <PersonaSwitcher
          personas={personas}
          active={active}
          onChoose={choose}
          onToggleSidebar={() => setSidebarVisible((v) => !v)}
        />
        <main className="flex-1 overflow-y-auto">
          {body}
        </main>
      </div>
    </div>
  );
}
