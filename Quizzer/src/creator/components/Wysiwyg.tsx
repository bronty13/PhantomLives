import { useEditor, EditorContent } from '@tiptap/react';
import StarterKit from '@tiptap/starter-kit';
import { useEffect } from 'react';
import { sanitizeHtml } from '../../shared/sanitize';

interface Props {
  value: string;
  onChange: (html: string) => void;
  placeholder?: string;
  minimal?: boolean;
}

/** Lightweight TipTap rich-text editor. Output is sanitized before it leaves here. */
export function Wysiwyg({ value, onChange, minimal }: Props) {
  const editor = useEditor({
    extensions: [StarterKit],
    content: value || '<p></p>',
    onUpdate: ({ editor }) => onChange(sanitizeHtml(editor.getHTML())),
  });

  // Keep editor in sync when the value is swapped externally (e.g. loading a quiz).
  useEffect(() => {
    if (editor && value !== editor.getHTML()) {
      editor.commands.setContent(value || '<p></p>', false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value, editor]);

  if (!editor) return null;

  const btn = (active: boolean) => `wy-btn${active ? ' active' : ''}`;

  return (
    <div className="wysiwyg">
      <div className="wy-toolbar">
        <button type="button" className={btn(editor.isActive('bold'))} onClick={() => editor.chain().focus().toggleBold().run()}><b>B</b></button>
        <button type="button" className={btn(editor.isActive('italic'))} onClick={() => editor.chain().focus().toggleItalic().run()}><i>I</i></button>
        <button type="button" className={btn(editor.isActive('strike'))} onClick={() => editor.chain().focus().toggleStrike().run()}><s>S</s></button>
        {!minimal && <>
          <span className="wy-sep" />
          <button type="button" className={btn(editor.isActive('heading', { level: 2 }))} onClick={() => editor.chain().focus().toggleHeading({ level: 2 }).run()}>H</button>
          <button type="button" className={btn(editor.isActive('bulletList'))} onClick={() => editor.chain().focus().toggleBulletList().run()}>• List</button>
          <button type="button" className={btn(editor.isActive('orderedList'))} onClick={() => editor.chain().focus().toggleOrderedList().run()}>1. List</button>
          <button type="button" className={btn(editor.isActive('blockquote'))} onClick={() => editor.chain().focus().toggleBlockquote().run()}>❝</button>
        </>}
      </div>
      <EditorContent editor={editor} className="wy-content" />
    </div>
  );
}
