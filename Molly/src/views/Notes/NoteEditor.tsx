import { useEditor, EditorContent, type Editor } from '@tiptap/react';
import StarterKit from '@tiptap/starter-kit';
import Underline from '@tiptap/extension-underline';
import Link from '@tiptap/extension-link';
import Placeholder from '@tiptap/extension-placeholder';
import { useEffect, useRef } from 'react';

interface Props {
  /** Current note HTML. Editor reloads when this changes externally
   *  (i.e. parent switched notes); typing-driven updates stay local. */
  initialHtml: string;
  /** Stable key for the loaded note. Forces a content reset when it
   *  changes so switching notes doesn't bleed body across. */
  noteKey: string | number;
  /** Fired after each edit with both formatted HTML and a plain-text
   *  extract used by the Rust Find scanner. Debounced upstream. */
  onChange: (html: string, text: string) => void;
  /** Optional font family override for this note's editor surface. */
  fontFamily?: string | null;
  /** Optional paper colour for the editor card background. */
  paperColor?: string | null;
}

export function NoteEditor({ initialHtml, noteKey, onChange, fontFamily, paperColor }: Props) {
  const lastKey = useRef<string | number>(noteKey);
  const editor = useEditor({
    extensions: [
      StarterKit.configure({ heading: { levels: [1, 2, 3] } }),
      Underline,
      Link.configure({ openOnClick: false, autolink: true, defaultProtocol: 'https' }),
      Placeholder.configure({ placeholder: 'Start writing — soft sparkles encouraged ✨' }),
    ],
    content: initialHtml,
    onUpdate({ editor }) {
      onChange(editor.getHTML(), editor.getText());
    },
    editorProps: {
      attributes: {
        // spellcheck on contenteditable: macOS WebKit honours both spell
        // check AND grammar correction when the user has them on in
        // System Settings → Keyboard → Text Input.
        spellcheck: 'true',
        autocorrect: 'on',
        class: 'molly-note-editor min-h-[480px] p-6 focus:outline-none leading-relaxed',
      },
    },
  });

  // External note swap: reset content so the editor doesn't carry
  // the previous note's body.
  useEffect(() => {
    if (!editor) return;
    if (lastKey.current !== noteKey) {
      lastKey.current = noteKey;
      editor.commands.setContent(initialHtml || '', { emitUpdate: false });
    } else if (editor.getHTML() !== initialHtml && !editor.isFocused) {
      // Same note, body changed externally (rare — e.g. import) and
      // editor isn't focused. Don't clobber active typing.
      editor.commands.setContent(initialHtml || '', { emitUpdate: false });
    }
  }, [editor, noteKey, initialHtml]);

  if (!editor) return <div className="text-xs opacity-60 p-6">Loading editor…</div>;

  return (
    <div
      className="rounded-2xl border border-black/10 overflow-hidden"
      style={{
        background: paperColor ?? 'white',
        boxShadow: '0 6px 20px rgb(var(--persona-primary) / 0.18)',
        fontFamily: fontFamily ?? undefined,
      }}
    >
      <Toolbar editor={editor} />
      <div style={{ fontFamily: fontFamily ?? undefined }}>
        <EditorContent editor={editor} />
      </div>
    </div>
  );
}

function Toolbar({ editor }: { editor: Editor }) {
  const Btn = ({ label, isActive, onClick, title }: {
    label: string; isActive?: boolean; onClick: () => void; title?: string;
  }) => (
    <button
      type="button"
      title={title}
      onClick={onClick}
      className="px-2 py-1 rounded-md text-xs font-semibold transition"
      style={{
        background: isActive ? 'rgb(var(--persona-accent))' : 'transparent',
        color: isActive ? 'white' : 'rgb(var(--persona-text))',
        border: '1px solid rgb(var(--persona-primary) / 0.35)',
      }}
    >
      {label}
    </button>
  );
  return (
    <div className="flex flex-wrap gap-1 p-2 border-b border-black/5 bg-white/40 backdrop-blur-sm">
      <Btn label="B" title="Bold (⌘B)" isActive={editor.isActive('bold')}
        onClick={() => editor.chain().focus().toggleBold().run()} />
      <Btn label="I" title="Italic (⌘I)" isActive={editor.isActive('italic')}
        onClick={() => editor.chain().focus().toggleItalic().run()} />
      <Btn label="U" title="Underline (⌘U)" isActive={editor.isActive('underline')}
        onClick={() => editor.chain().focus().toggleUnderline().run()} />
      <Btn label="S" title="Strikethrough" isActive={editor.isActive('strike')}
        onClick={() => editor.chain().focus().toggleStrike().run()} />
      <div className="w-px bg-black/10 mx-1" />
      <Btn label="H1" isActive={editor.isActive('heading', { level: 1 })}
        onClick={() => editor.chain().focus().toggleHeading({ level: 1 }).run()} />
      <Btn label="H2" isActive={editor.isActive('heading', { level: 2 })}
        onClick={() => editor.chain().focus().toggleHeading({ level: 2 }).run()} />
      <Btn label="H3" isActive={editor.isActive('heading', { level: 3 })}
        onClick={() => editor.chain().focus().toggleHeading({ level: 3 }).run()} />
      <div className="w-px bg-black/10 mx-1" />
      <Btn label="• List" isActive={editor.isActive('bulletList')}
        onClick={() => editor.chain().focus().toggleBulletList().run()} />
      <Btn label="1. List" isActive={editor.isActive('orderedList')}
        onClick={() => editor.chain().focus().toggleOrderedList().run()} />
      <Btn label="❝" title="Quote" isActive={editor.isActive('blockquote')}
        onClick={() => editor.chain().focus().toggleBlockquote().run()} />
      <Btn label="—" title="Horizontal rule"
        onClick={() => editor.chain().focus().setHorizontalRule().run()} />
      <Btn label="Link" title="Add or edit link" isActive={editor.isActive('link')}
        onClick={() => {
          const prev = (editor.getAttributes('link') as { href?: string }).href ?? '';
          const url = window.prompt('Link URL (blank to remove):', prev);
          if (url === null) return;
          if (url === '') editor.chain().focus().extendMarkRange('link').unsetLink().run();
          else editor.chain().focus().extendMarkRange('link').setLink({ href: url }).run();
        }} />
      <Btn label="Clear" title="Clear formatting"
        onClick={() => editor.chain().focus().clearNodes().unsetAllMarks().run()} />
    </div>
  );
}
