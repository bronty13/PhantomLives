import { useCallback, useEffect, useState } from 'react';
import type { Branding, GlobalSettings, Quiz } from '../shared/model';
import { makeBranding, makeQuiz, newId } from '../shared/factory';
import {
  getSettings,
  listBrandings,
  listQuizzes,
  saveBranding,
  saveQuiz,
} from './storage/db';
import { parseBundle } from './storage/bundle';
import { QuizList } from './screens/QuizList';
import { QuizEditor } from './screens/QuizEditor';
import { BrandingManager } from './screens/BrandingManager';
import { GlobalSettingsScreen } from './screens/GlobalSettings';

type Route = 'home' | 'edit' | 'branding' | 'settings';

export function App() {
  const [route, setRoute] = useState<Route>('home');
  const [quizzes, setQuizzes] = useState<Quiz[]>([]);
  const [brandings, setBrandings] = useState<Branding[]>([]);
  const [settings, setSettings] = useState<GlobalSettings | null>(null);
  const [editing, setEditing] = useState<Quiz | null>(null);

  const reload = useCallback(async () => {
    const [q, b, s] = await Promise.all([listQuizzes(), listBrandings(), getSettings()]);
    setQuizzes(q);
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

  if (!settings) return <div className="loading">Loading…</div>;

  return (
    <div className="creator">
      <nav className="topnav">
        <span className="brand">📝 Quizzer</span>
        <button className={navCls(route, 'home')} onClick={() => setRoute('home')}>Quizzes</button>
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
        {route === 'branding' && <BrandingManager brandings={brandings} onChange={reload} />}
        {route === 'settings' && <GlobalSettingsScreen settings={settings} onSaved={(s) => setSettings(s)} />}
      </main>
    </div>
  );
}

function navCls(route: Route, target: Route): string {
  return `nav-btn${route === target ? ' active' : ''}`;
}
