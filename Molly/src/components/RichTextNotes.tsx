import { useEditor, EditorContent } from '@tiptap/react';
import StarterKit from '@tiptap/starter-kit';
import Link from '@tiptap/extension-link';
import Placeholder from '@tiptap/extension-placeholder';
import { useEffect } from 'react';

interface Props {
  value: string;
  onChange: (html: string) => void;
  placeholder?: string;
  className?: string;
}

export function RichTextNotes({ value, onChange, placeholder = 'Notes…', className }: Props) {
  const editor = useEditor({
    extensions: [
      StarterKit.configure({
        heading: { levels: [2, 3] },
      }),
      Link.configure({ openOnClick: false, autolink: true, defaultProtocol: 'https' }),
      Placeholder.configure({ placeholder }),
    ],
    content: value,
    onUpdate({ editor }) {
      onChange(editor.getHTML());
    },
    editorProps: {
      attributes: {
        class: 'molly-richtext min-h-[160px] p-3 focus:outline-none persona-text',
      },
    },
  });

  // Keep the editor in sync if the parent swaps customers (uid changed).
  useEffect(() => {
    if (!editor) return;
    if (editor.getHTML() !== value) {
      editor.commands.setContent(value || '', { emitUpdate: false });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [editor, value]);

  if (!editor) {
    return <div className="text-xs opacity-60">Loading editor…</div>;
  }

  const Button = ({ label, isActive, onClick, title }: { label: string; isActive?: boolean; onClick: () => void; title?: string }) => (
    <button
      type="button"
      title={title}
      onClick={onClick}
      className="px-2 py-1 rounded-md text-xs font-semibold transition"
      style={{
        background: isActive ? 'rgb(var(--persona-accent))' : 'transparent',
        color: isActive ? 'white' : 'rgb(var(--persona-text))',
        border: '1px solid rgb(var(--persona-primary) / 0.4)',
      }}
    >
      {label}
    </button>
  );

  return (
    <div className={`rounded-xl border border-black/10 bg-white ${className ?? ''}`} style={{ boxShadow: '0 2px 8px rgb(var(--persona-primary) / 0.18)' }}>
      <div className="flex flex-wrap gap-1 p-2 border-b border-black/5">
        <Button label="B" title="Bold" isActive={editor.isActive('bold')} onClick={() => editor.chain().focus().toggleBold().run()} />
        <Button label="I" title="Italic" isActive={editor.isActive('italic')} onClick={() => editor.chain().focus().toggleItalic().run()} />
        <Button label="S" title="Strikethrough" isActive={editor.isActive('strike')} onClick={() => editor.chain().focus().toggleStrike().run()} />
        <Button label="H2" isActive={editor.isActive('heading', { level: 2 })} onClick={() => editor.chain().focus().toggleHeading({ level: 2 }).run()} />
        <Button label="H3" isActive={editor.isActive('heading', { level: 3 })} onClick={() => editor.chain().focus().toggleHeading({ level: 3 }).run()} />
        <Button label="• List" isActive={editor.isActive('bulletList')} onClick={() => editor.chain().focus().toggleBulletList().run()} />
        <Button label="1. List" isActive={editor.isActive('orderedList')} onClick={() => editor.chain().focus().toggleOrderedList().run()} />
        <Button label="Quote" isActive={editor.isActive('blockquote')} onClick={() => editor.chain().focus().toggleBlockquote().run()} />
        <Button label="HR" onClick={() => editor.chain().focus().setHorizontalRule().run()} />
        <Button
          label="Link"
          title="Add or edit link"
          isActive={editor.isActive('link')}
          onClick={() => {
            const prev = (editor.getAttributes('link') as { href?: string }).href ?? '';
            const url = window.prompt('Link URL (blank to remove):', prev);
            if (url === null) return;
            if (url === '') {
              editor.chain().focus().extendMarkRange('link').unsetLink().run();
            } else {
              editor.chain().focus().extendMarkRange('link').setLink({ href: url }).run();
            }
          }}
        />
        <Button label="Clear" title="Clear formatting" onClick={() => editor.chain().focus().clearNodes().unsetAllMarks().run()} />
      </div>
      <EditorContent editor={editor} />
    </div>
  );
}
