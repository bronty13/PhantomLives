import { useCallback, useEffect, useState } from 'react';
import type { Branding, GlobalSettings, Quiz, Wheel } from '../shared/model';
import { makeBranding, makeQuiz, makeWheel, newId } from '../shared/factory';
import {
  getSettings,
  listBrandings,
  listQuizzes,
  listWheels,
  saveBranding,
  saveQuiz,
  saveWheel,
} from './storage/db';
import { parseBundle } from './storage/bundle';
import { parseWheelBundle } from './storage/wheelBundle';
import { QuizList } from './screens/QuizList';
import { QuizEditor } from './screens/QuizEditor';
import { WheelList } from './screens/WheelList';
import { WheelEditor } from './screens/WheelEditor';
import { BrandingManager } from './screens/BrandingManager';
import { GlobalSettingsScreen } from './screens/GlobalSettings';
import { UpdateBanner } from './components/UpdateBanner';
import { WhatsNew } from './components/WhatsNew';
import { unseenNotes, type ReleaseNote } from './data/whatsNew';
import { APP_VERSION } from '../shared/appMeta';

const LAST_SEEN_KEY = 'quizzer.lastSeenVersion';

type Route = 'home' | 'edit' | 'wheels' | 'editWheel' | 'branding' | 'settings';

export function App() {
  const [route, setRoute] = useState<Route>('home');
  const [quizzes, setQuizzes] = useState<Quiz[]>([]);
  const [wheels, setWheels] = useState<Wheel[]>([]);
  const [brandings, setBrandings] = useState<Branding[]>([]);
  const [settings, setSettings] = useState<GlobalSettings | null>(null);
  const [editing, setEditing] = useState<Quiz | null>(null);
  const [editingWheel, setEditingWheel] = useState<Wheel | null>(null);
  const [whatsNew, setWhatsNew] = useState<ReleaseNote[]>([]);

  // On first load, show the What's New popup for any versions newer than the one
  // last seen, then record this build as seen so it never nags again. A brand-new
  // install (no marker) shows nothing — there's no update to announce.
  useEffect(() => {
    const lastSeen = localStorage.getItem(LAST_SEEN_KEY);
    setWhatsNew(unseenNotes(lastSeen));
    localStorage.setItem(LAST_SEEN_KEY, APP_VERSION);
  }, []);

  const reload = useCallback(async () => {
    const [q, w, b, s] = await Promise.all([
      listQuizzes(), listWheels(), listBrandings(), getSettings(),
    ]);
    setQuizzes(q);
    setWheels(w);
    setBrandings(b);
    setSettings(s);
  }, []);

  useEffect(() => { void reload(); }, [reload]);

  async function ensureBranding(): Promise<Branding> {
    if (brandings.length > 0) return brandings[0];
    const b = makeBranding('Default Brand');
    await saveBranding(b);
    await reload();
    return b;
  }

  async function newQuiz() {
    if (!settings) return;
    const branding = await ensureBranding();
    const quiz = makeQuiz(branding.id, settings);
    await saveQuiz(quiz);
    await reload();
    setEditing(quiz);
    setRoute('edit');
  }

  async function importQuiz(file: File) {
    try {
      const bundle = parseBundle(await file.text());
      await saveBranding(bundle.branding);
      const quiz: Quiz = { ...bundle.quiz, id: newId(), updatedAt: Date.now() };
      await saveQuiz(quiz);
      await reload();
      setEditing(quiz);
      setRoute('edit');
    } catch (e) {
      alert(`Import failed: ${e instanceof Error ? e.message : e}`);
    }
  }

  function openQuiz(q: Quiz) {
    setEditing(q);
    setRoute('edit');
  }

  async function newWheel() {
    if (!settings) return;
    const branding = await ensureBranding();
    const wheel = makeWheel(branding.id, settings);
    await saveWheel(wheel);
    await reload();
    setEditingWheel(wheel);
    setRoute('editWheel');
  }

  async function importWheel(file: File) {
    try {
      const bundle = parseWheelBundle(await file.text());
      await saveBranding(bundle.branding);
      const wheel: Wheel = { ...bundle.wheel, id: newId(), updatedAt: Date.now() };
      await saveWheel(wheel);
      await reload();
      setEditingWheel(wheel);
      setRoute('editWheel');
    } catch (e) {
      alert(`Import failed: ${e instanceof Error ? e.message : e}`);
    }
  }

  function openWheel(w: Wheel) {
    setEditingWheel(w);
    setRoute('editWheel');
  }

  if (!settings) return <div className="loading">Loading…</div>;

  return (
    <div className="creator">
      <UpdateBanner />
      {whatsNew.length > 0 && <WhatsNew notes={whatsNew} onClose={() => setWhatsNew([])} />}
      <nav className="topnav">
        <span className="brand">📝 Quizzer</span>
        <button className={navCls(route, 'home')} onClick={() => setRoute('home')}>Quizzes</button>
        <button className={navCls(route, 'wheels')} onClick={() => setRoute('wheels')}>Wheels</button>
        <button className={navCls(route, 'branding')} onClick={() => setRoute('branding')}>Branding</button>
        <button className={navCls(route, 'settings')} onClick={() => setRoute('settings')}>Settings</button>
      </nav>

      <main className="content">
        {route === 'home' && (
          <QuizList quizzes={quizzes} brandings={brandings} onOpen={openQuiz} onNew={newQuiz} onImport={importQuiz} reload={reload} />
        )}
        {route === 'edit' && editing && (
          <QuizEditor initial={editing} brandings={brandings} settings={settings}
            onBack={() => { setRoute('home'); void reload(); }}
            onSaved={() => void reload()} />
        )}
        {route === 'wheels' && (
          <WheelList wheels={wheels} brandings={brandings} onOpen={openWheel} onNew={newWheel} onImport={importWheel} reload={reload} />
        )}
        {route === 'editWheel' && editingWheel && (
          <WheelEditor initial={editingWheel} brandings={brandings}
            onBack={() => { setRoute('wheels'); void reload(); }}
            onSaved={() => void reload()} />
        )}
        {route === 'branding' && <BrandingManager brandings={brandings} onChange={reload} />}
        {route === 'settings' && <GlobalSettingsScreen settings={settings} onSaved={(s) => setSettings(s)} />}
      </main>
    </div>
  );
}

function navCls(route: Route, target: Route): string {
  return `nav-btn${route === target ? ' active' : ''}`;
}
