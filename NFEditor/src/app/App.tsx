import { useEffect, useMemo, useState } from 'react';
import { nanoid } from 'nanoid';
import { APP_VERSION, type DocNode, type NFDocument, type OutputMode } from '../shared/model';
import {
  listDocuments,
  saveDocument,
  deleteDocument,
  getLastSeenVersion,
  setLastSeenVersion,
  getOutputMode,
  setOutputMode,
} from '../storage/db';
import { emptyDoc } from '../shared/schema';
import { templateById } from '../shared/templates';
import { unseenNotes, type ReleaseNote } from '../shared/whatsNew';
import { UpdateBanner } from './components/UpdateBanner';
import { WhatsNew } from './components/WhatsNew';
import { DocList } from './screens/DocList';
import { DocEditor } from './screens/DocEditor';

const now = () => new Date().toISOString();

export function App() {
  const [docs, setDocs] = useState<NFDocument[]>(() => listDocuments());
  const [currentId, setCurrentId] = useState<string | null>(null);
  const [mode, setMode] = useState<OutputMode>((getOutputMode() as OutputMode) || 'legacy');
  const [whatsNew, setWhatsNew] = useState<ReleaseNote[]>([]);

  useEffect(() => {
    const lastSeen = getLastSeenVersion();
    const notes = unseenNotes(lastSeen);
    if (notes.length > 0) setWhatsNew(notes);
    if (lastSeen !== APP_VERSION) setLastSeenVersion(APP_VERSION);
  }, []);

  const current = useMemo(() => docs.find((d) => d.id === currentId) ?? null, [docs, currentId]);

  const persist = (doc: NFDocument) => {
    saveDocument(doc);
    setDocs(listDocuments());
  };

  const create = (docType: 'profile' | 'listing', content?: DocNode, name?: string) => {
    const doc: NFDocument = {
      id: nanoid(),
      name: name ?? (docType === 'profile' ? 'New Profile' : 'New Listing'),
      docType,
      content: content ?? emptyDoc(),
      createdAt: now(),
      updatedAt: now(),
    };
    persist(doc);
    setCurrentId(doc.id);
  };

  const fromTemplate = (templateId: string) => {
    const t = templateById(templateId);
    if (!t) return;
    create(t.docType, t.content as DocNode, t.name);
  };

  const save = (patch: { name?: string; content?: DocNode }) => {
    if (!current) return;
    persist({ ...current, ...patch, updatedAt: now() });
  };

  const changeMode = (m: OutputMode) => {
    setMode(m);
    setOutputMode(m);
  };

  return (
    <div className="app">
      <UpdateBanner />
      <div className="topbar">
        <div className="brand">
          NFEditor <span className="ver">v{APP_VERSION}</span>
        </div>
        <div className="tagline">NiteFlirt Profile &amp; Listing builder</div>
      </div>

      {current ? (
        <DocEditor
          key={current.id}
          doc={current}
          mode={mode}
          onModeChange={changeMode}
          onSave={save}
          onBack={() => setCurrentId(null)}
        />
      ) : (
        <DocList
          docs={docs}
          onNew={(t) => create(t)}
          onNewFromTemplate={fromTemplate}
          onOpen={(id) => setCurrentId(id)}
          onDelete={(id) => {
            deleteDocument(id);
            setDocs(listDocuments());
          }}
        />
      )}

      {whatsNew.length > 0 && <WhatsNew notes={whatsNew} onClose={() => setWhatsNew([])} />}
    </div>
  );
}
