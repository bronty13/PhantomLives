import { useState } from 'react';
import type { Editor } from '@tiptap/react';
import { NF_SIZES, SIZE_PT, type DocNode } from '../../shared/model';
import { InsertDialog, type InsertKind } from './InsertDialog';

const FACES = ['Arial', 'Georgia', 'Times New Roman', 'Courier New', 'Verdana', 'Trebuchet MS', 'Comic Sans MS'];

const INSERTS: Array<{ kind: InsertKind; label: string }> = [
  { kind: 'image', label: 'Image' },
  { kind: 'goodyButton', label: 'Goody / PTV button' },
  { kind: 'tributeButton', label: 'Tribute button' },
  { kind: 'flirtButton', label: 'Flirt (call) button' },
  { kind: 'wishlistLink', label: 'Wishlist link' },
  { kind: 'section', label: 'Section / box' },
  { kind: 'video', label: 'Video' },
  { kind: 'imageMap', label: 'Image map' },
];

export function Toolbar({ editor }: { editor: Editor }) {
  const [insertKind, setInsertKind] = useState<InsertKind | null>(null);
  const [insertOpen, setInsertOpen] = useState(false);

  // Force re-render on selection/transaction so isActive() reflects state.
  const font = editor.getAttributes('font');
  const setFont = (patch: Record<string, unknown>) =>
    editor.chain().focus().setMark('font', { ...font, ...patch }).run();

  const mark = (name: string) => editor.chain().focus().toggleMark(name).run();
  const active = (name: string, attrs?: Record<string, unknown>) =>
    editor.isActive(name, attrs) ? ' active' : '';

  const setAlign = (align: string) =>
    editor
      .chain()
      .focus()
      .updateAttributes(editor.isActive('heading') ? 'heading' : 'paragraph', { align })
      .run();

  const insert = (node: DocNode) => {
    editor.chain().focus().insertContent(node).run();
    setInsertOpen(false);
    setInsertKind(null);
  };

  return (
    <div className="toolbar">
      <div className="tb-group">
        <button className={'tb' + active('bold')} title="Bold" onClick={() => mark('bold')}>
          <b>B</b>
        </button>
        <button className={'tb' + active('italic')} title="Italic" onClick={() => mark('italic')}>
          <i>I</i>
        </button>
        <button className={'tb' + active('underline')} title="Underline" onClick={() => mark('underline')}>
          <u>U</u>
        </button>
        <button className={'tb' + active('strike')} title="Strikethrough" onClick={() => mark('strike')}>
          <s>S</s>
        </button>
      </div>

      <div className="tb-group">
        <select
          title="Font"
          value={font.face ?? ''}
          onChange={(e) => setFont({ face: e.target.value || null })}
        >
          <option value="">Font…</option>
          {FACES.map((f) => (
            <option key={f} value={f}>
              {f}
            </option>
          ))}
        </select>
        <select
          title="Size"
          value={font.size ?? ''}
          onChange={(e) => setFont({ size: e.target.value ? Number(e.target.value) : null })}
        >
          <option value="">Size…</option>
          {NF_SIZES.map((s) => (
            <option key={s} value={s}>
              {s} · {SIZE_PT[s]}pt
            </option>
          ))}
        </select>
        <label className="tb-color" title="Text color">
          <input type="color" value={font.color ?? '#000000'} onChange={(e) => setFont({ color: e.target.value })} />
        </label>
      </div>

      <div className="tb-group">
        <select
          title="Paragraph style"
          value={editor.isActive('heading') ? String(editor.getAttributes('heading').level) : 'p'}
          onChange={(e) => {
            const v = e.target.value;
            if (v === 'p') editor.chain().focus().setParagraph().run();
            else editor.chain().focus().toggleHeading({ level: Number(v) as 1 | 2 | 3 | 4 | 5 | 6 }).run();
          }}
        >
          <option value="p">Paragraph</option>
          {[1, 2, 3, 4, 5, 6].map((l) => (
            <option key={l} value={l}>
              Heading {l}
            </option>
          ))}
        </select>
        {editor.isActive('heading') && (
          <label className="tb-color" title="Heading color">
            <input
              type="color"
              value={editor.getAttributes('heading').color ?? '#000000'}
              onChange={(e) => editor.chain().focus().updateAttributes('heading', { color: e.target.value }).run()}
            />
          </label>
        )}
      </div>

      <div className="tb-group">
        <button className="tb" title="Align left" onClick={() => setAlign('left')}>
          ⬅
        </button>
        <button className="tb" title="Align center" onClick={() => setAlign('center')}>
          ↔
        </button>
        <button className="tb" title="Align right" onClick={() => setAlign('right')}>
          ➡
        </button>
      </div>

      <div className="tb-group">
        <button className={'tb' + active('bulletList')} title="Bullet list" onClick={() => editor.chain().focus().toggleBulletList().run()}>
          • List
        </button>
        <button className={'tb' + active('orderedList')} title="Numbered list" onClick={() => editor.chain().focus().toggleOrderedList().run()}>
          1. List
        </button>
        <button className="tb" title="Divider" onClick={() => editor.chain().focus().setHorizontalRule().run()}>
          ―
        </button>
      </div>

      <div className="tb-group">
        <select
          title="Insert element"
          value=""
          onChange={(e) => {
            const k = e.target.value as InsertKind;
            if (k) {
              setInsertKind(k);
              setInsertOpen(true);
            }
          }}
        >
          <option value="">Insert ▾</option>
          {INSERTS.map((i) => (
            <option key={i.kind} value={i.kind}>
              {i.label}
            </option>
          ))}
        </select>
      </div>

      {insertOpen && insertKind && (
        <InsertDialog
          kind={insertKind}
          onInsert={insert}
          onClose={() => {
            setInsertOpen(false);
            setInsertKind(null);
          }}
        />
      )}
    </div>
  );
}
