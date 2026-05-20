import { useCallback, useEffect, useState } from 'react';
import { Sidebar, type ViewKey } from './components/Sidebar';
import { PersonaSwitcher } from './components/PersonaSwitcher';
import { usePersonas } from './state/personas';
import { useApplyPersonaTheme } from './state/theme';
import { SettingsView } from './views/Settings/SettingsView';
import { CustomerListView } from './views/Customers/CustomerListView';
import { MollyHelper } from './views/MollyHelper/MollyHelper';
import { HomeDashboard } from './views/Home/HomeDashboard';
import { CalendarView } from './views/Calendar/CalendarView';
import { ClipsListView } from './views/Clips/ClipsListView';
import { RemindersView } from './views/Reminders/RemindersView';
import { IncomeView } from './views/Income/IncomeView';
import { ExpensesView } from './views/Expenses/ExpensesView';
import { ReportsView } from './views/Reports/ReportsView';
import { materializeOccurrences, pendingCounts } from './data/occurrences';
import { materializeRecurringExpenses } from './data/expenses';

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

  // Materialize occurrences + recurring expenses on app launch and every
  // 30 min. Both are idempotent so this is safe to run on every tick.
  useEffect(() => {
    let alive = true;
    const tick = async () => {
      try {
        await materializeOccurrences();
        await materializeRecurringExpenses();
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

  useEffect(() => {
    refreshCounts();
  }, [refreshCounts]);

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
    case 'income':    body = <IncomeView active={active} />; break;
    case 'expenses':  body = <ExpensesView active={active} onChanged={refreshCounts} />; break;
    case 'reports':   body = <ReportsView active={active} />; break;
    case 'settings':  body = <SettingsView active={active} onPersonasChanged={refresh} />; break;
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
