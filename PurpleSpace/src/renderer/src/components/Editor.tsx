import React, { useEffect, useMemo, useRef } from 'react';
import { useConvex, useMutation, useQuery } from 'convex/react';
import { useCreateBlockNote } from '@blocknote/react';
import { BlockNoteView } from '@blocknote/mantine';
import { codeBlockOptions } from '@blocknote/code-block';
import type { Block } from '@blocknote/core';
import { api } from '../../../../convex/_generated/api';
import type { Id } from '../../../../convex/_generated/dataModel';
import { useIsDark } from '../lib/useIsDark';

import '@blocknote/core/fonts/inter.css';
import '@blocknote/mantine/style.css';

export interface EditorHandle {
  toMarkdown: () => Promise<string>;
  focusStart: () => void;
}

interface EditorProps {
  pageId: string;
  handleRef: React.MutableRefObject<EditorHandle | null>;
}

const SAVE_DEBOUNCE_MS = 400;

export default function Editor({ pageId, handleRef }: EditorProps): React.JSX.Element | null {
  const doc = useQuery(api.documents.get, { pageId: pageId as Id<'pages'> });
  // Wait for the stored document before constructing the editor; `null`
  // means a fresh page (no content yet).
  if (doc === undefined) return null;
  return <LoadedEditor pageId={pageId} handleRef={handleRef} blocksJson={doc?.blocksJson ?? null} />;
}

function LoadedEditor({
  pageId,
  handleRef,
  blocksJson
}: EditorProps & { blocksJson: string | null }): React.JSX.Element {
  const convex = useConvex();
  const save = useMutation(api.documents.save);
  const dark = useIsDark();
  const saveTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pendingJson = useRef<string | null>(null);

  const initialContent = useMemo(() => {
    if (!blocksJson) return undefined;
    try {
      const blocks = JSON.parse(blocksJson) as Block[];
      return blocks.length ? blocks : undefined;
    } catch {
      return undefined;
    }
    // The editor is constructed once per page mount (PageView keys us by pageId);
    // live re-parsing on every remote echo would fight the local editing session.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const editor = useCreateBlockNote({
    initialContent,
    codeBlock: codeBlockOptions,
    uploadFile: async (file: File): Promise<string> => {
      const uploadUrl = await convex.mutation(api.files.generateUploadUrl, {});
      const res = await fetch(uploadUrl, {
        method: 'POST',
        headers: { 'Content-Type': file.type || 'application/octet-stream' },
        body: file
      });
      if (!res.ok) throw new Error(`upload failed: HTTP ${res.status}`);
      const { storageId } = (await res.json()) as { storageId: string };
      const url = await convex.query(api.files.getUrl, {
        storageId: storageId as Id<'_storage'>
      });
      if (!url) throw new Error('uploaded file has no URL');
      return url;
    }
  });

  const flush = (): void => {
    if (pendingJson.current != null) {
      void save({ pageId: pageId as Id<'pages'>, blocksJson: pendingJson.current });
      pendingJson.current = null;
    }
  };

  useEffect(() => {
    handleRef.current = {
      toMarkdown: async () => editor.blocksToMarkdownLossy(editor.document),
      focusStart: () => editor.focus()
    };
    return () => {
      handleRef.current = null;
    };
  }, [editor, handleRef]);

  // Flush the debounced save when the page unmounts (navigation away).
  useEffect(() => {
    return () => {
      if (saveTimer.current) clearTimeout(saveTimer.current);
      flush();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <BlockNoteView
      editor={editor}
      theme={dark ? 'dark' : 'light'}
      onChange={() => {
        pendingJson.current = JSON.stringify(editor.document);
        if (saveTimer.current) clearTimeout(saveTimer.current);
        saveTimer.current = setTimeout(flush, SAVE_DEBOUNCE_MS);
      }}
    />
  );
}
