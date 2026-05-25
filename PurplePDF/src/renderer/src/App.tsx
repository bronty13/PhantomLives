import { useCallback, useEffect, useState } from 'react';
import type { RecentFile } from '../../shared/types';
import PDFViewer from './features/viewer/PDFViewer';
import { loadDocument, loadDocumentInfo } from './features/viewer/types';
import type { Tab } from './features/viewer/types';
import { DEFAULT_COLORS } from './features/annotate/types';
import { buildModifiedPdf } from './features/annotate/flatten';
import { applyWatermark } from './features/annotate/watermark';
import { applyHeaderFooter } from './features/annotate/headerFooter';
import { detectContentBounds } from './features/viewer/autoCrop';
import CompareModal from './features/viewer/CompareModal';
import { ocrPages } from './features/ocr/ocr';
import type { PDFDocumentProxy } from './features/viewer/pdfjs';
import type { PageOp } from './features/annotate/flatten';
import { extractFormFields, initialValues } from './features/forms/extract';
import SignatureModal from './features/sign/SignatureModal';
import ProtectModal, { type ProtectOptions } from './features/security/ProtectModal';
import PropertiesModal from './features/properties/PropertiesModal';
import Welcome from './features/welcome/Welcome';

export default function App(): JSX.Element {
  const [tabs, setTabs] = useState<Tab[]>([]);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [recents, setRecents] = useState<RecentFile[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [armedSignature, setArmedSignature] = useState<
    { bytes: Uint8Array; width: number; height: number } | null
  >(null);
  const [signatureModalOpen, setSignatureModalOpen] = useState(false);
  const [protectModalOpen, setProtectModalOpen] = useState(false);
  const [propertiesModalOpen, setPropertiesModalOpen] = useState(false);
  const [a11yRefreshNonce, setA11yRefreshNonce] = useState(0);
  const [compare, setCompare] = useState<{
    leftDoc: PDFDocumentProxy;
    leftName: string;
    rightDoc: PDFDocumentProxy;
    rightName: string;
  } | null>(null);

  const activeTab = tabs.find((t) => t.id === activeId) ?? null;

  const refreshRecents = useCallback(() => {
    window.purplePDF.getRecents().then(setRecents).catch(() => undefined);
  }, []);

  useEffect(() => refreshRecents(), [refreshRecents]);

  const openPath = useCallback(
    async (filePath: string) => {
      try {
        const existing = tabs.find((t) => t.path === filePath);
        if (existing) {
          setActiveId(existing.id);
          return;
        }
        const loaded = await window.purplePDF.readFile(filePath);
        // Keep a pristine copy of the bytes for pdf-lib; pdfjs gets its own slice.
        const originalBytes = loaded.data.slice(0);
        const doc = await loadDocument(loaded.data);
        const formFields = await extractFormFields(doc);
        const formValues = initialValues(formFields);
        const properties = await loadDocumentInfo(doc);
        const id = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
        const tab: Tab = {
          id,
          path: loaded.path,
          name: loaded.name,
          doc,
          originalBytes,
          numPages: doc.numPages,
          currentPage: 1,
          zoom: 1,
          fitMode: 'fit-width',
          rotation: 0,
          outline: [],
          findQuery: '',
          findMatches: [],
          findIndex: -1,
          findVisible: false,
          tool: 'select',
          color: DEFAULT_COLORS.highlight,
          strokeWidth: 2,
          toolPrefs: {},
          annotations: [],
          pageOps: [],
          selectedAnnotId: null,
          past: [],
          future: [],
          dirty: false,
          formFields,
          formValues,
          formInitial: { ...formValues },
          formDirty: false,
          properties
        };
        setTabs((prev) => [...prev, tab]);
        setActiveId(id);
        setError(null);
        refreshRecents();
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e));
      }
    },
    [tabs, refreshRecents]
  );

  const updateActive = useCallback(
    (patch: Partial<Tab>) => {
      if (!activeId) return;
      setTabs((prev) => prev.map((t) => (t.id === activeId ? { ...t, ...patch } : t)));
    },
    [activeId]
  );

  const updateTab = useCallback((id: string, patch: Partial<Tab>) => {
    setTabs((prev) => prev.map((t) => (t.id === id ? { ...t, ...patch } : t)));
  }, []);

  const closeTab = useCallback(
    (id: string) => {
      setTabs((prev) => {
        const idx = prev.findIndex((t) => t.id === id);
        if (idx === -1) return prev;
        prev[idx].doc.destroy();
        const next = prev.filter((t) => t.id !== id);
        if (id === activeId) {
          const fallback = next[idx] ?? next[idx - 1] ?? null;
          setActiveId(fallback ? fallback.id : null);
        }
        return next;
      });
    },
    [activeId]
  );

  // ----- Save flow -----
  const saveTab = useCallback(
    async (
      tab: Tab,
      targetPath: string | null,
      opts?: { stripMetadata?: boolean }
    ): Promise<void> => {
      try {
        const annotsByPage = new Map<number, typeof tab.annotations>();
        for (const a of tab.annotations) {
          const arr = annotsByPage.get(a.page) ?? [];
          arr.push(a);
          annotsByPage.set(a.page, arr);
        }
        const bytes = await buildModifiedPdf(
          tab.originalBytes,
          annotsByPage,
          tab.pageOps,
          tab.formValues,
          {
            stripMetadata: opts?.stripMetadata,
            properties: opts?.stripMetadata
              ? undefined
              : {
                  title: tab.properties.title,
                  author: tab.properties.author,
                  subject: tab.properties.subject,
                  keywords: tab.properties.keywords
                    ? tab.properties.keywords.split(',').map((s) => s.trim()).filter(Boolean)
                    : [],
                  language: tab.properties.language
                }
          }
        );
        const path = targetPath ?? tab.path;
        // Copy into a fresh ArrayBuffer for IPC (avoid SharedArrayBuffer + structured-clone of subarrays)
        const buf = new ArrayBuffer(bytes.byteLength);
        new Uint8Array(buf).set(bytes);
        let result: { ok: boolean; path: string };
        try {
          result = await window.purplePDF.saveBytes(path, buf);
        } catch (writeErr) {
          // Read-only / protected destination → automatically prompt for Save As.
          const msg = writeErr instanceof Error ? writeErr.message : String(writeErr);
          if (/EPERM|EACCES|EROFS|EISDIR/i.test(msg)) {
            const fallback = await window.purplePDF.saveAsDialog(tab.name);
            if (!fallback) return;
            // Re-encode buffer for the second IPC call (the first one was transferred/consumed).
            const buf2 = new ArrayBuffer(bytes.byteLength);
            new Uint8Array(buf2).set(bytes);
            result = await window.purplePDF.saveBytes(fallback, buf2);
          } else {
            throw writeErr;
          }
        }
        // Reload the saved file into the tab so subsequent edits stack on the
        // already-flattened doc.
        if (result.ok) {
          const loaded = await window.purplePDF.readFile(result.path);
          const originalBytes = loaded.data.slice(0);
          const newDoc = await loadDocument(loaded.data);
          const formFields = await extractFormFields(newDoc);
          const formValues = initialValues(formFields);
          const properties = await loadDocumentInfo(newDoc);
          tab.doc.destroy();
          updateTab(tab.id, {
            path: result.path,
            name: loaded.name,
            doc: newDoc,
            originalBytes,
            numPages: newDoc.numPages,
            currentPage: Math.min(tab.currentPage, newDoc.numPages),
            annotations: [],
            pageOps: [],
            past: [],
            future: [],
            dirty: false,
            selectedAnnotId: null,
            outline: [],
            formFields,
            formValues,
            formInitial: { ...formValues },
            formDirty: false,
            properties
          });
          refreshRecents();
          // Re-run a11y checks against the freshly-saved doc.
          setA11yRefreshNonce((n) => n + 1);
          // Clear any pending autosave for this source — the explicit save supersedes it.
          void window.purplePDF.autosaveClear({ sourcePath: result.path, sourceName: loaded.name });
        }
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e));
      }
    },
    [updateTab, refreshRecents]
  );

  const doSave = useCallback(async () => {
    if (!activeTab) return;
    await saveTab(activeTab, activeTab.path);
  }, [activeTab, saveTab]);

  const doSaveAs = useCallback(async () => {
    if (!activeTab) return;
    const target = await window.purplePDF.saveAsDialog(activeTab.path);
    if (!target) return;
    await saveTab(activeTab, target);
  }, [activeTab, saveTab]);

  // ----- Creation & conversion (P4) -----
  const newFromImages = useCallback(async () => {
    try {
      const images = await window.purplePDF.pickImages();
      if (images.length === 0) return;
      const out = await window.purplePDF.imagesToPdf(images, 'Combined.pdf');
      if (out) await openPath(out);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, [openPath]);

  const newFromUrl = useCallback(async () => {
    const url = window.prompt('Enter a URL to capture as PDF:', 'https://');
    if (!url) return;
    try {
      const out = await window.purplePDF.urlToPdf(url, 'Web Page.pdf');
      if (out) await openPath(out);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, [openPath]);

  const newFromOffice = useCallback(async () => {
    try {
      const picked = await window.purplePDF.pickOffice();
      if (picked.length === 0) return;
      const out = await window.purplePDF.officeToPdf(picked[0]);
      if (out) await openPath(out);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, [openPath]);

  const exportAs = useCallback(
    async (target: 'docx' | 'xlsx' | 'pptx') => {
      if (!activeTab) return;
      try {
        // Flatten current annotations/page-ops into a fresh PDF byte stream so
        // unsaved edits are reflected in the export.
        const annotsByPage = new Map<number, typeof activeTab.annotations>();
        for (const a of activeTab.annotations) {
          const arr = annotsByPage.get(a.page) ?? [];
          arr.push(a);
          annotsByPage.set(a.page, arr);
        }
        const bytes = await buildModifiedPdf(
          activeTab.originalBytes,
          annotsByPage,
          activeTab.pageOps,
          activeTab.formValues
        );
        const buf = new ArrayBuffer(bytes.byteLength);
        new Uint8Array(buf).set(bytes);
        const out = await window.purplePDF.pdfToOffice(buf, target, activeTab.name);
        if (out) {
          // Don't open in Purple PDF (it's a Word/Excel/PowerPoint file now);
          // just confirm with a banner.
          setError(null);
        }
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e));
      }
    },
    [activeTab]
  );

  const exportImages = useCallback(
    async (scope: 'current' | 'all', format: 'png' | 'jpeg') => {
      if (!activeTab) return;
      try {
        const ext = format === 'png' ? 'png' : 'jpg';
        const mime = format === 'png' ? 'image/png' : 'image/jpeg';
        const baseName = activeTab.name.replace(/\.pdf$/i, '');
        const renderScale = 2; // ~144 DPI relative to default rendering scale of 1.

        const renderToBlob = async (pageNum: number): Promise<Blob> => {
          const page = await activeTab.doc.getPage(pageNum);
          const vp = page.getViewport({ scale: renderScale, rotation: activeTab.rotation });
          const canvas = document.createElement('canvas');
          canvas.width = Math.ceil(vp.width);
          canvas.height = Math.ceil(vp.height);
          const ctx = canvas.getContext('2d');
          if (!ctx) throw new Error('Could not create 2D canvas context.');
          await page.render({ canvasContext: ctx, viewport: vp }).promise;
          return await new Promise<Blob>((resolve, reject) => {
            canvas.toBlob(
              (b) => (b ? resolve(b) : reject(new Error('toBlob returned null'))),
              mime,
              format === 'jpeg' ? 0.92 : undefined
            );
          });
        };

        if (scope === 'current') {
          const pageNum = activeTab.currentPage;
          const defaultName = `${baseName}-page-${pageNum}.${ext}`;
          const outPath = await window.purplePDF.saveAsDialog(defaultName);
          if (!outPath) return;
          const blob = await renderToBlob(pageNum);
          const buf = await blob.arrayBuffer();
          await window.purplePDF.saveBytes(outPath, buf);
          setError(null);
        } else {
          const dir = await window.purplePDF.pickDirectory();
          if (!dir) return;
          const pad = String(activeTab.numPages).length;
          const sep = dir.includes('\\') ? '\\' : '/';
          for (let i = 1; i <= activeTab.numPages; i++) {
            const blob = await renderToBlob(i);
            const buf = await blob.arrayBuffer();
            const num = String(i).padStart(pad, '0');
            const outPath = `${dir}${sep}${baseName}-page-${num}.${ext}`;
            await window.purplePDF.saveBytes(outPath, buf);
          }
          setError(null);
          alert(`Wrote ${activeTab.numPages} ${format.toUpperCase()} files to:\n${dir}`);
        }
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e));
      }
    },
    [activeTab]
  );

  const exportFormData = useCallback(
    async (format: 'json' | 'csv') => {
      if (!activeTab) return;
      try {
        const grouped = new Map<string, string>();
        // Aggregate by fieldName, normalizing types to strings for CSV/JSON.
        const byName = new Map<string, (typeof activeTab.formFields)[number]>();
        for (const f of activeTab.formFields) {
          if (!byName.has(f.fieldName)) byName.set(f.fieldName, f);
        }
        for (const [name] of byName) {
          const v = activeTab.formValues[name];
          if (typeof v === 'boolean') grouped.set(name, v ? 'true' : 'false');
          else grouped.set(name, v ?? '');
        }

        let content: string;
        let ext: string;
        if (format === 'json') {
          content = JSON.stringify(Object.fromEntries(grouped), null, 2);
          ext = 'json';
        } else {
          const esc = (s: string): string =>
            /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
          const rows = ['field,value'];
          for (const [k, v] of grouped) rows.push(`${esc(k)},${esc(v)}`);
          content = rows.join('\n');
          ext = 'csv';
        }
        const baseName = activeTab.name.replace(/\.pdf$/i, '');
        const target = await window.purplePDF.saveAsDialog(`${baseName}.${ext}`);
        if (!target) return;
        const buf = new TextEncoder().encode(content);
        const arr = new ArrayBuffer(buf.byteLength);
        new Uint8Array(arr).set(buf);
        await window.purplePDF.saveBytes(target, arr);
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e));
      }
    },
    [activeTab]
  );

  // ----- E-sign & security (P6) -----

  const openSignatureModal = useCallback(() => {
    if (!activeTab) return;
    setSignatureModalOpen(true);
  }, [activeTab]);

  const onSignatureCreated = useCallback(
    (bytes: Uint8Array, width: number, height: number) => {
      setArmedSignature({ bytes, width, height });
      setSignatureModalOpen(false);
      // Switch to signature tool so the next click places the signature.
      if (activeId) updateTab(activeId, { tool: 'signature' });
    },
    [activeId, updateTab]
  );

  // Disarm signature placement when leaving the signature tool.
  useEffect(() => {
    if (activeTab && activeTab.tool !== 'signature' && armedSignature) {
      setArmedSignature(null);
    }
  }, [activeTab, armedSignature]);

  // ----- Debounced background autosave -----
  // After 5 s without further edits, flatten the current tab and persist a
  // recovery snapshot under userData/autosaves. Only runs when the tab is
  // dirty so cleanly-loaded docs don't waste cycles.
  useEffect(() => {
    if (!activeTab || !activeTab.dirty) return;
    const tabSnapshot = activeTab;
    const handle = window.setTimeout(() => {
      void (async () => {
        try {
          const annotsByPage = new Map<number, typeof tabSnapshot.annotations>();
          for (const a of tabSnapshot.annotations) {
            const arr = annotsByPage.get(a.page) ?? [];
            arr.push(a);
            annotsByPage.set(a.page, arr);
          }
          const bytes = await buildModifiedPdf(
            tabSnapshot.originalBytes,
            annotsByPage,
            tabSnapshot.pageOps,
            tabSnapshot.formValues
          );
          const buf = new ArrayBuffer(bytes.byteLength);
          new Uint8Array(buf).set(bytes);
          await window.purplePDF.autosaveWrite({
            bytes: buf,
            sourcePath: tabSnapshot.path,
            sourceName: tabSnapshot.name
          });
        } catch (err) {
          // Autosave failures are silent — explicit save is the user-visible path.
          console.warn('[autosave] failed:', err);
        }
      })();
    }, 5000);
    return () => window.clearTimeout(handle);
  }, [
    activeTab,
    activeTab?.dirty,
    activeTab?.annotations,
    activeTab?.pageOps,
    activeTab?.formValues,
    activeTab?.path,
    activeTab?.name,
    activeTab?.originalBytes
  ]);

  const startRedact = useCallback(() => {
    if (!activeId || !activeTab) return;
    if (!sessionStorage.getItem('purplepdf-redact-warned')) {
      sessionStorage.setItem('purplepdf-redact-warned', '1');
      setError(
        'Visual Redaction draws an opaque black rectangle over content. The underlying text/images remain in the file unless you also use "Document → Remove Document Metadata" and re-flatten. This is NOT audit-grade redaction.'
      );
    }
    updateTab(activeId, { tool: 'redact', color: '#000000' });
  }, [activeId, activeTab, updateTab]);

  const openProtectModal = useCallback(() => {
    if (!activeTab) return;
    setProtectModalOpen(true);
  }, [activeTab]);

  const onProtectConfirm = useCallback(
    async (opts: ProtectOptions) => {
      setProtectModalOpen(false);
      if (!activeTab) return;
      try {
        // Flatten current annotations/forms BEFORE encrypting so they make it
        // into the protected output (the protected file cannot be re-edited).
        const annotsByPage = new Map<number, typeof activeTab.annotations>();
        for (const a of activeTab.annotations) {
          const arr = annotsByPage.get(a.page) ?? [];
          arr.push(a);
          annotsByPage.set(a.page, arr);
        }
        const bytes = await buildModifiedPdf(
          activeTab.originalBytes,
          annotsByPage,
          activeTab.pageOps,
          activeTab.formValues
        );
        const buf = new ArrayBuffer(bytes.byteLength);
        new Uint8Array(buf).set(bytes);
        const out = await window.purplePDF.protectPdf({
          bytes: buf,
          sourceName: activeTab.name,
          userPassword: opts.userPassword,
          ownerPassword: opts.ownerPassword,
          permissions: opts.permissions
        });
        if (out) {
          refreshRecents();
          setError(null);
        }
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e));
      }
    },
    [activeTab, refreshRecents]
  );

  const removeMetadata = useCallback(async () => {
    if (!activeTab) return;
    // Overwrite the current file (uses Save As fallback if read-only).
    await saveTab(activeTab, activeTab.path, { stripMetadata: true });
  }, [activeTab, saveTab]);

  // ----- Standards & accessibility (P7) -----

  const openProperties = useCallback(() => {
    if (!activeTab) return;
    setPropertiesModalOpen(true);
  }, [activeTab]);

  const onPropertiesApply = useCallback(
    (next: { title: string; author: string; subject: string; keywords: string; language: string }) => {
      setPropertiesModalOpen(false);
      if (!activeId) return;
      updateTab(activeId, { properties: next, dirty: true });
      // Trigger a re-run of any open a11y panel so the user sees changes
      // reflected after they Save.
      setA11yRefreshNonce((n) => n + 1);
    },
    [activeId, updateTab]
  );

  const convertToStandard = useCallback(
    async (target: 'PDF/A-1b' | 'PDF/A-2b' | 'PDF/A-3b' | 'PDF/X-3') => {
      if (!activeTab) return;
      try {
        // Flatten current state first so the standard-compliant output
        // contains the user's edits, properties, and form values.
        const annotsByPage = new Map<number, typeof activeTab.annotations>();
        for (const a of activeTab.annotations) {
          const arr = annotsByPage.get(a.page) ?? [];
          arr.push(a);
          annotsByPage.set(a.page, arr);
        }
        const bytes = await buildModifiedPdf(
          activeTab.originalBytes,
          annotsByPage,
          activeTab.pageOps,
          activeTab.formValues,
          {
            properties: {
              title: activeTab.properties.title,
              author: activeTab.properties.author,
              subject: activeTab.properties.subject,
              keywords: activeTab.properties.keywords
                ? activeTab.properties.keywords
                    .split(',')
                    .map((s) => s.trim())
                    .filter(Boolean)
                : [],
              language: activeTab.properties.language
            }
          }
        );
        const buf = new ArrayBuffer(bytes.byteLength);
        new Uint8Array(buf).set(bytes);
        const out = await window.purplePDF.convertToStandard({
          bytes: buf,
          sourceName: activeTab.name,
          target
        });
        if (out) {
          refreshRecents();
          setError(null);
        }
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e));
      }
    },
    [activeTab, refreshRecents]
  );

  const triggerA11yCheck = useCallback(() => {
    setA11yRefreshNonce((n) => n + 1);
  }, []);

  // ----- IPC wiring -----
  useEffect(() => {
    const offs: Array<() => void> = [];
    offs.push(window.purplePDF.onOpenFile((p) => void openPath(p)));
    offs.push(window.purplePDF.onCloseTab(() => activeId && closeTab(activeId)));
    offs.push(window.purplePDF.onFind(() => activeId && updateActive({ findVisible: true })));
    offs.push(window.purplePDF.onSave(() => void doSave()));
    offs.push(window.purplePDF.onSaveAs(() => void doSaveAs()));
    offs.push(
      window.purplePDF.onNewFrom((kind) => {
        if (kind === 'images') void newFromImages();
        else if (kind === 'url') void newFromUrl();
        else if (kind === 'office') void newFromOffice();
      })
    );
    offs.push(window.purplePDF.onExportAs((kind) => void exportAs(kind)));
    offs.push(
      window.purplePDF.onExportImage(({ scope, format }) => void exportImages(scope, format))
    );
    offs.push(window.purplePDF.onExportForm((kind) => void exportFormData(kind)));
    offs.push(window.purplePDF.onProtect(() => openProtectModal()));
    offs.push(window.purplePDF.onRemoveMetadata(() => void removeMetadata()));
    offs.push(window.purplePDF.onAddSignature(() => openSignatureModal()));
    offs.push(window.purplePDF.onRedactTool(() => startRedact()));
    offs.push(window.purplePDF.onProperties(() => openProperties()));
    offs.push(window.purplePDF.onConvertStandard((target) => void convertToStandard(target)));
    offs.push(window.purplePDF.onA11yCheck(() => triggerA11yCheck()));
    offs.push(
      window.purplePDF.onCombinePdfs(() => {
        void (async () => {
          const out = await window.purplePDF.combinePdfs();
          if (out) {
            await openPath(out);
          }
        })();
      })
    );
    offs.push(
      window.purplePDF.onSplitPdf(() => {
        void (async () => {
          if (!activeTab) {
            alert('Open a PDF first, then choose Split PDF.');
            return;
          }
          const mode = window.confirm(
            'Split into one PDF per page?\n\nClick OK for per-page split, or Cancel to extract a page range instead.'
          )
            ? 'per-page'
            : 'ranges';
          let rangeStr: string | undefined;
          if (mode === 'ranges') {
            const r = window.prompt(
              `Enter page ranges to extract (1-${activeTab.numPages}).\nExample: 1-3, 5, 8-10`
            );
            if (!r) return;
            rangeStr = r;
          }
          // Snapshot the *current* document bytes (with any pending edits).
          const annotsByPage = new Map<number, typeof activeTab.annotations>();
          for (const a of activeTab.annotations) {
            const arr = annotsByPage.get(a.page) ?? [];
            arr.push(a);
            annotsByPage.set(a.page, arr);
          }
          const bytes = await buildModifiedPdf(
            activeTab.originalBytes,
            annotsByPage,
            activeTab.pageOps,
            activeTab.formValues
          );
          const buf = new ArrayBuffer(bytes.byteLength);
          new Uint8Array(buf).set(bytes);
          const res = await window.purplePDF.splitPdf({
            bytes: buf,
            sourceName: activeTab.name,
            mode,
            ranges: rangeStr
          });
          if (res && mode === 'ranges' && res.files[0]) {
            await openPath(res.files[0]);
          }
        })();
      })
    );

    offs.push(
      window.purplePDF.onOptimizePdf(() => {
        void (async () => {
          if (!activeTab) {
            alert('Open a PDF first, then choose Optimize PDF.');
            return;
          }
          const choice = window.prompt(
            'Optimize quality preset:\n  screen   - smallest, low-res images (web)\n  ebook    - small, screen viewing (default)\n  printer  - moderate, print-quality\n  prepress - largest, press-ready',
            'ebook'
          );
          if (!choice) return;
          const quality = (['screen', 'ebook', 'printer', 'prepress'] as const).includes(
            choice.trim() as 'ebook'
          )
            ? (choice.trim() as 'screen' | 'ebook' | 'printer' | 'prepress')
            : 'ebook';
          const annotsByPage = new Map<number, typeof activeTab.annotations>();
          for (const a of activeTab.annotations) {
            const arr = annotsByPage.get(a.page) ?? [];
            arr.push(a);
            annotsByPage.set(a.page, arr);
          }
          const bytes = await buildModifiedPdf(
            activeTab.originalBytes,
            annotsByPage,
            activeTab.pageOps,
            activeTab.formValues
          );
          const buf = new ArrayBuffer(bytes.byteLength);
          new Uint8Array(buf).set(bytes);
          const out = await window.purplePDF.optimizePdf({
            bytes: buf,
            sourceName: activeTab.name,
            quality
          });
          if (out) await openPath(out);
        })();
      })
    );

    offs.push(
      window.purplePDF.onWatermark(() => {
        void (async () => {
          if (!activeTab) {
            alert('Open a PDF first, then choose Add Watermark.');
            return;
          }
          const text = window.prompt('Watermark text:', 'CONFIDENTIAL');
          if (!text) return;
          const annotsByPage = new Map<number, typeof activeTab.annotations>();
          for (const a of activeTab.annotations) {
            const arr = annotsByPage.get(a.page) ?? [];
            arr.push(a);
            annotsByPage.set(a.page, arr);
          }
          const baseBytes = await buildModifiedPdf(
            activeTab.originalBytes,
            annotsByPage,
            activeTab.pageOps,
            activeTab.formValues
          );
          const stamped = await applyWatermark(baseBytes, text);
          const buf = new ArrayBuffer(stamped.byteLength);
          new Uint8Array(buf).set(stamped);
          const def = activeTab.name.replace(/\.pdf$/i, '') + ' (watermarked).pdf';
          const target = await window.purplePDF.saveAsDialog(def);
          if (!target) return;
          await window.purplePDF.saveBytes(target, buf);
          await openPath(target);
        })();
      })
    );

    offs.push(
      window.purplePDF.onHeaderFooter(() => {
        void (async () => {
          if (!activeTab) {
            alert('Open a PDF first, then choose Header / Footer / Bates.');
            return;
          }
          const header = window.prompt(
            'Header text (top center). Leave blank to skip.\nTokens: {page} {total} {date} {bates}',
            ''
          );
          if (header === null) return;
          const footer = window.prompt(
            'Footer text (bottom center). Leave blank to skip.\nTokens: {page} {total} {date} {bates}',
            'Page {page} of {total}'
          );
          if (footer === null) return;
          const wantBates = window.confirm('Add Bates numbering (bottom right)?');
          let bates: { prefix: string; start: number; digits: number } | undefined;
          if (wantBates) {
            const prefix = window.prompt('Bates prefix:', 'DOC') ?? '';
            const startStr = window.prompt('Bates start number:', '1') ?? '1';
            const digitsStr = window.prompt('Number of digits (zero-padded):', '6') ?? '6';
            const start = parseInt(startStr, 10);
            const digits = parseInt(digitsStr, 10);
            if (!Number.isFinite(start) || !Number.isFinite(digits)) {
              alert('Bates start and digits must be numbers.');
              return;
            }
            bates = { prefix, start, digits };
          }
          if (!header && !footer && !bates) {
            alert('Nothing to stamp.');
            return;
          }
          const annotsByPage = new Map<number, typeof activeTab.annotations>();
          for (const a of activeTab.annotations) {
            const arr = annotsByPage.get(a.page) ?? [];
            arr.push(a);
            annotsByPage.set(a.page, arr);
          }
          const baseBytes = await buildModifiedPdf(
            activeTab.originalBytes,
            annotsByPage,
            activeTab.pageOps,
            activeTab.formValues
          );
          const stamped = await applyHeaderFooter(baseBytes, {
            header: header || undefined,
            footer: footer || undefined,
            bates
          });
          const buf = new ArrayBuffer(stamped.byteLength);
          new Uint8Array(buf).set(stamped);
          const def = activeTab.name.replace(/\.pdf$/i, '') + ' (stamped).pdf';
          const target = await window.purplePDF.saveAsDialog(def);
          if (!target) return;
          await window.purplePDF.saveBytes(target, buf);
          await openPath(target);
        })();
      })
    );

    offs.push(
      window.purplePDF.onAutoCrop((scope) => {
        void (async () => {
          if (!activeTab) {
            alert('Open a PDF first, then choose Auto-Crop Margins.');
            return;
          }
          const pages =
            scope === 'all'
              ? Array.from({ length: activeTab.numPages }, (_, i) => i + 1)
              : [activeTab.currentPage];
          const newOps: PageOp[] = [];
          let blank = 0;
          for (const p of pages) {
            const bounds = await detectContentBounds(activeTab.doc, p);
            if (!bounds) {
              blank++;
              continue;
            }
            newOps.push({ kind: 'crop', page: p - 1, crop: bounds });
          }
          if (newOps.length === 0) {
            alert('No content found to crop.');
            return;
          }
          updateActive({
            pageOps: [...activeTab.pageOps, ...newOps],
            dirty: true
          });
          if (blank > 0) {
            console.warn(`[auto-crop] Skipped ${blank} blank page(s).`);
          }
        })();
      })
    );

    offs.push(
      window.purplePDF.onCompare(() => {
        void (async () => {
          if (!activeTab) {
            alert('Open a PDF first, then choose Compare.');
            return;
          }
          const pickPath = await window.purplePDF.pickPdf();
          if (!pickPath) return;
          try {
            const loaded = await window.purplePDF.readFile(pickPath);
            const rightDoc = await loadDocument(loaded.data);
            setCompare({
              leftDoc: activeTab.doc,
              leftName: activeTab.name,
              rightDoc,
              rightName: loaded.name
            });
          } catch (e) {
            setError(e instanceof Error ? e.message : String(e));
          }
        })();
      })
    );

    offs.push(
      window.purplePDF.onOcr((scope) => {
        void (async () => {
          if (!activeTab) {
            alert('Open a PDF first, then choose OCR.');
            return;
          }
          const pages =
            scope === 'all'
              ? Array.from({ length: activeTab.numPages }, (_, i) => i + 1)
              : [activeTab.currentPage];
          const tabId = activeTab.id;
          const tabSnapshot = activeTab;
          try {
            updateTab(tabId, {
              ocrStatus: `OCR 0 / ${pages.length}…`
            });
            const newBytes = await ocrPages({
              originalBytes: tabSnapshot.originalBytes,
              doc: tabSnapshot.doc,
              pageNumbers: pages,
              onProgress: (p) => {
                updateTab(tabId, {
                  ocrStatus: `OCR ${p.page} / ${p.total} (${p.phase})…`
                });
              }
            });
            // Replace tab originalBytes + reload the doc so the OCR text is
            // visible/selectable in the live viewer too.
            const newOriginal = newBytes.buffer.slice(
              newBytes.byteOffset,
              newBytes.byteOffset + newBytes.byteLength
            ) as ArrayBuffer;
            const newDoc = await loadDocument(newOriginal);
            tabSnapshot.doc.destroy();
            updateTab(tabId, {
              doc: newDoc,
              originalBytes: newOriginal,
              numPages: newDoc.numPages,
              dirty: true,
              ocrStatus: undefined
            });
          } catch (err) {
            updateTab(tabId, { ocrStatus: undefined });
            setError(err instanceof Error ? err.message : String(err));
          }
        })();
      })
    );

    // Right-click "Save Page As…" on a thumbnail dispatches this custom event.
    const onExtractPage = (e: Event): void => {
      const ce = e as CustomEvent<{ page: number }>;
      const pageNumber = ce.detail?.page;
      if (!pageNumber || !activeTab) return;
      void (async () => {
        const annotsByPage = new Map<number, typeof activeTab.annotations>();
        for (const a of activeTab.annotations) {
          const arr = annotsByPage.get(a.page) ?? [];
          arr.push(a);
          annotsByPage.set(a.page, arr);
        }
        const bytes = await buildModifiedPdf(
          activeTab.originalBytes,
          annotsByPage,
          activeTab.pageOps,
          activeTab.formValues
        );
        const buf = new ArrayBuffer(bytes.byteLength);
        new Uint8Array(buf).set(bytes);
        const res = await window.purplePDF.splitPdf({
          bytes: buf,
          sourceName: activeTab.name,
          mode: 'ranges',
          ranges: String(pageNumber)
        });
        if (res && res.files[0]) {
          await openPath(res.files[0]);
        }
      })();
    };
    window.addEventListener('purplepdf:extract-page', onExtractPage);
    offs.push(() => window.removeEventListener('purplepdf:extract-page', onExtractPage));

    // Crop tool drag-emits a custom event with the PDF-coord rect for the current page.
    const onCropRegion = (e: Event): void => {
      const ce = e as CustomEvent<{ page: number; x: number; y: number; width: number; height: number }>;
      const d = ce.detail;
      if (!d || !activeTab) return;
      const op: PageOp = {
        kind: 'crop',
        page: d.page,
        crop: { x: d.x, y: d.y, width: d.width, height: d.height }
      };
      updateActive({
        pageOps: [...activeTab.pageOps, op],
        dirty: true,
        tool: 'select'
      });
    };
    window.addEventListener('purplepdf:crop-region', onCropRegion);
    offs.push(() => window.removeEventListener('purplepdf:crop-region', onCropRegion));
    offs.push(
      window.purplePDF.onUndo(() => {
        if (!activeTab || activeTab.past.length === 0) return;
        const prev = activeTab.past[activeTab.past.length - 1];
        updateActive({
          past: activeTab.past.slice(0, -1),
          future: [
            { annotations: activeTab.annotations, pageOps: activeTab.pageOps },
            ...activeTab.future
          ],
          annotations: prev.annotations,
          pageOps: prev.pageOps,
          dirty: activeTab.past.length > 1
        });
      })
    );
    offs.push(
      window.purplePDF.onRedo(() => {
        if (!activeTab || activeTab.future.length === 0) return;
        const next = activeTab.future[0];
        updateActive({
          past: [
            ...activeTab.past,
            { annotations: activeTab.annotations, pageOps: activeTab.pageOps }
          ],
          future: activeTab.future.slice(1),
          annotations: next.annotations,
          pageOps: next.pageOps,
          dirty: true
        });
      })
    );
    offs.push(
      window.purplePDF.onZoom((cmd) => {
        if (!activeTab) return;
        if (cmd === 'in') updateActive({ zoom: Math.min(8, activeTab.zoom * 1.2), fitMode: 'custom' });
        else if (cmd === 'out') updateActive({ zoom: Math.max(0.1, activeTab.zoom / 1.2), fitMode: 'custom' });
        else if (cmd === 'reset') updateActive({ zoom: 1, fitMode: 'custom' });
        else if (cmd === 'fit-width') updateActive({ fitMode: 'fit-width' });
        else if (cmd === 'fit-page') updateActive({ fitMode: 'fit-page' });
      })
    );
    offs.push(
      window.purplePDF.onRotate((cmd) => {
        if (!activeTab) return;
        const delta = cmd === 'cw' ? 90 : -90;
        const next = (((activeTab.rotation + delta) % 360) + 360) % 360;
        updateActive({ rotation: next as 0 | 90 | 180 | 270 });
      })
    );
    offs.push(
      window.purplePDF.onPage((cmd) => {
        if (!activeTab) return;
        if (cmd === 'next')
          updateActive({ currentPage: Math.min(activeTab.numPages, activeTab.currentPage + 1) });
        else if (cmd === 'prev')
          updateActive({ currentPage: Math.max(1, activeTab.currentPage - 1) });
        else if (cmd === 'first') updateActive({ currentPage: 1 });
        else if (cmd === 'last') updateActive({ currentPage: activeTab.numPages });
      })
    );
    return () => offs.forEach((off) => off());
  }, [
    activeId,
    activeTab,
    closeTab,
    openPath,
    updateActive,
    doSave,
    doSaveAs,
    newFromImages,
    newFromUrl,
    newFromOffice,
    exportAs,
    exportImages,
    exportFormData,
    openProtectModal,
    removeMetadata,
    openSignatureModal,
    startRedact,
    openProperties,
    convertToStandard,
    triggerA11yCheck,
    updateTab
  ]);

  // ----- Keyboard navigation (P7 a11y) -----
  // Page navigation via ArrowLeft/ArrowRight and PageUp/PageDown when focus is
  // not in a typing context. Escape closes any open modal.
  useEffect(() => {
    const onKey = (ev: KeyboardEvent): void => {
      if (ev.key === 'Escape') {
        if (signatureModalOpen) setSignatureModalOpen(false);
        else if (protectModalOpen) setProtectModalOpen(false);
        else if (propertiesModalOpen) setPropertiesModalOpen(false);
        return;
      }
      const target = ev.target as HTMLElement | null;
      const tag = target?.tagName;
      if (
        tag === 'INPUT' ||
        tag === 'TEXTAREA' ||
        tag === 'SELECT' ||
        target?.isContentEditable
      ) {
        return;
      }
      if (!activeTab) return;
      const goto = (n: number): void =>
        updateActive({ currentPage: Math.max(1, Math.min(activeTab.numPages, n)) });
      if (ev.key === 'ArrowRight' || ev.key === 'PageDown') {
        ev.preventDefault();
        goto(activeTab.currentPage + 1);
      } else if (ev.key === 'ArrowLeft' || ev.key === 'PageUp') {
        ev.preventDefault();
        goto(activeTab.currentPage - 1);
      } else if (ev.key === 'Home') {
        ev.preventDefault();
        goto(1);
      } else if (ev.key === 'End') {
        ev.preventDefault();
        goto(activeTab.numPages);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [activeTab, updateActive, signatureModalOpen, protectModalOpen, propertiesModalOpen]);

  // Keep <html lang> in sync with the active doc's declared language so the
  // viewer chrome announces correctly to screen readers.
  useEffect(() => {
    if (activeTab?.properties.language) {
      document.documentElement.lang = activeTab.properties.language;
    }
  }, [activeTab?.properties.language]);

  const onClearRecents = useCallback(() => {
    window.purplePDF.clearRecents().then(setRecents).catch(() => undefined);
  }, []);

  return (
    <div className="app">
      <div className="tabbar" role="tablist" aria-label="Open documents">
        <button
          type="button"
          className={`tab tab-home${activeId === null ? ' active' : ''}`}
          onClick={() => setActiveId(null)}
          role="tab"
          aria-selected={activeId === null}
        >
          ⌂
        </button>
        {tabs.map((t) => (
          <div
            key={t.id}
            className={`tab${t.id === activeId ? ' active' : ''}`}
            role="tab"
            aria-selected={t.id === activeId}
          >
            <button type="button" className="tab-title" onClick={() => setActiveId(t.id)} title={t.path}>
              {t.dirty ? '• ' : ''}
              {t.name}
              {t.ocrStatus ? ` — ${t.ocrStatus}` : ''}
            </button>
            <button
              type="button"
              className="tab-close"
              onClick={() => closeTab(t.id)}
              aria-label={`Close ${t.name}`}
            >
              ✕
            </button>
          </div>
        ))}
        <button
          type="button"
          className="tab-add"
          onClick={() => window.purplePDF.openDialog()}
          aria-label="Open file"
        >
          +
        </button>
      </div>

      {error && (
        <div className="banner error">
          {error}
          <button type="button" onClick={() => setError(null)} aria-label="Dismiss" style={{ marginLeft: 'auto' }}>
            ✕
          </button>
        </div>
      )}

      <div className="app-body">
        {activeTab ? (
          <PDFViewer
            tab={activeTab}
            onUpdate={updateActive}
            onSave={doSave}
            onSaveAs={doSaveAs}
            onExportFormData={exportFormData}
            armedSignature={armedSignature}
            onNeedSignature={openSignatureModal}
            onOpenProperties={openProperties}
            a11yRefreshNonce={a11yRefreshNonce}
          />
        ) : (
          <Welcome
            recents={recents}
            onOpen={() => window.purplePDF.openDialog()}
            onOpenPath={(p) => void openPath(p)}
            onClearRecents={onClearRecents}
            onNewFromImages={() => void newFromImages()}
            onNewFromUrl={() => void newFromUrl()}
            onNewFromOffice={() => void newFromOffice()}
          />
        )}
      </div>
      <SignatureModal
        open={signatureModalOpen}
        onCancel={() => setSignatureModalOpen(false)}
        onConfirm={onSignatureCreated}
      />
      <ProtectModal
        open={protectModalOpen}
        onCancel={() => setProtectModalOpen(false)}
        onConfirm={(opts) => void onProtectConfirm(opts)}
      />
      <PropertiesModal
        open={propertiesModalOpen}
        initial={
          activeTab?.properties ?? {
            title: '',
            author: '',
            subject: '',
            keywords: '',
            language: ''
          }
        }
        onCancel={() => setPropertiesModalOpen(false)}
        onConfirm={onPropertiesApply}
      />
      {compare && (
        <CompareModal
          leftDoc={compare.leftDoc}
          leftName={compare.leftName}
          rightDoc={compare.rightDoc}
          rightName={compare.rightName}
          onClose={() => {
            compare.rightDoc.destroy();
            setCompare(null);
          }}
        />
      )}
    </div>
  );
}
