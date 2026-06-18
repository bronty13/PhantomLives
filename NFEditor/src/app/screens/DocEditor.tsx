import { useEffect, useState } from 'react';
import { useEditor, EditorContent } from '@tiptap/react';
import { buildExtensions } from '../../shared/schema';
import { serialize } from '../../shared/serialize';
import { hasEmoji, stripEmoji } from '../../shared/validate/emoji';
import type { DocNode, NFDocument, OutputMode } from '../../shared/model';
import { Toolbar } from '../editor/Toolbar';
import { Preview3Up } from '../preview/Preview3Up';
import { ValidatorPanel } from '../panels/ValidatorPanel';
import { OutputPanel } from '../panels/OutputPanel';
import { ImportDialog } from '../panels/ImportDialog';

export function DocEditor({
  doc,
  mode,
  onModeChange,
  onSave,
  onBack,
}: {
  doc: NFDocument;
  mode: OutputMode;
  onModeChange: (m: OutputMode) => void;
  onSave: (patch: { name?: string; content?: DocNode }) => void;
  onBack: () => void;
}) {
  const [name, setName] = useState(doc.name);
  const [json, setJson] = useState<DocNode>(doc.content);
  const [tab, setTab] = useState<'preview' | 'output'>('preview');
  const [emojiFlash, setEmojiFlash] = useState(false);
  const [importing, setImporting] = useState(false);

  const flashEmoji = () => {
    setEmojiFlash(true);
    setTimeout(() => setEmojiFlash(false), 2500);
  };

  const editor = useEditor({
    extensions: buildExtensions(),
    content: doc.content,
    editorProps: {
      handleTextInput(_view, _from, _to, text) {
        if (hasEmoji(text)) {
          flashEmoji();
          return true; // block the emoji keystroke
        }
        return false;
      },
      transformPastedHTML: (html) => (hasEmoji(html) ? (flashEmoji(), stripEmoji(html)) : html),
      transformPastedText: (text) => (hasEmoji(text) ? (flashEmoji(), stripEmoji(text)) : text),
    },
    onUpdate: ({ editor }) => {
      const next = editor.getJSON() as DocNode;
      setJson(next);
      onSave({ content: next });
    },
  });

  // Persist name edits.
  useEffect(() => {
    onSave({ name });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [name]);

  if (!editor) return null;

  return (
    <div className="editor-screen">
      <header className="ed-header">
        <button className="ghost" onClick={onBack}>
          ← All documents
        </button>
        <input className="doc-name" value={name} onChange={(e) => setName(e.target.value)} />
        <span className={`badge ${doc.docType}`}>{doc.docType === 'profile' ? 'Profile' : 'Listing'}</span>
        <div className="spacer" />
        <button className="ghost" onClick={() => setImporting(true)}>
          Import HTML
        </button>
        <div className="mode-toggle" role="group" aria-label="Output mode">
          <button className={mode === 'compact' ? 'active' : ''} onClick={() => onModeChange('compact')}>
            Compact
          </button>
          <button className={mode === 'legacy' ? 'active' : ''} onClick={() => onModeChange('legacy')}>
            Legacy table
          </button>
        </div>
      </header>

      {emojiFlash && (
        <div className="emoji-flash">🚫 Emoji are blocked — they would truncate your NiteFlirt page on save.</div>
      )}

      <Toolbar editor={editor} />

      <div className="ed-body">
        <div className="ed-left">
          <EditorContent editor={editor} className="nf-editor-content" />
        </div>
        <div className="ed-right">
          <ValidatorPanel doc={json} mode={mode} docType={doc.docType} />
          <div className="tabs">
            <button className={tab === 'preview' ? 'active' : ''} onClick={() => setTab('preview')}>
              Preview
            </button>
            <button className={tab === 'output' ? 'active' : ''} onClick={() => setTab('output')}>
              HTML output
            </button>
          </div>
          {tab === 'preview' ? (
            <Preview3Up html={serialize(json, mode)} docType={doc.docType} />
          ) : (
            <OutputPanel doc={json} mode={mode} name={name} />
          )}
        </div>
      </div>

      {importing && (
        <ImportDialog
          onClose={() => setImporting(false)}
          onImport={(cleaned) => {
            editor.commands.setContent(cleaned, true);
            setJson(editor.getJSON() as DocNode);
            onSave({ content: editor.getJSON() as DocNode });
            setImporting(false);
          }}
        />
      )}
    </div>
  );
}
