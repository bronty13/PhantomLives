import Store from 'electron-store';

interface RecentFile {
  path: string;
  name: string;
  openedAt: number;
}

interface AppState {
  recents: RecentFile[];
}

const MAX_RECENTS = 20;

const store = new Store<AppState>({
  name: 'purple-pdf',
  defaults: { recents: [] }
});

export function getRecents(): RecentFile[] {
  return store.get('recents', []);
}

export function addRecent(path: string, name: string): RecentFile[] {
  const now = Date.now();
  const existing = store.get('recents', []);
  const filtered = existing.filter((r) => r.path !== path);
  filtered.unshift({ path, name, openedAt: now });
  const trimmed = filtered.slice(0, MAX_RECENTS);
  store.set('recents', trimmed);
  return trimmed;
}

export function clearRecents(): void {
  store.set('recents', []);
}
