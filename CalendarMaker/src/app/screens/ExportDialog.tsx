import { useState } from 'react';
import type { AppSettings, CalendarBundle, ExportMode, Theme } from '../../model/types';
import { APP_NAME, MONTH_NAMES } from '../../model/types';
import { exportBundleJson } from '../../storage/bundleIO';
import { buildCalendarPdf, type VerseExportOrder } from '../../pdf/exportPdf';
import { hasVerseOrSayingItems } from '../../pdf/versePdf';
import { Modal } from '../components/Modal';
import { downloadBlob, downloadText, slugify, timestamp } from '../util';

export function ExportDialog({ bundle, theme, settings, onClose }: { bundle: CalendarBundle; theme: Theme; settings: AppSettings; onClose: () => void }) {
  const [mode, setMode] = useState<ExportMode>(settings.defaultExportMode);
  const [verseOrder, setVerseOrder] = useState<VerseExportOrder>('verse-before-detail');
  const [busy, setBusy] = useState(false);

  const isSeparate = (bundle.verseMode ?? 'force') === 'separate';
  const hasVerses = hasVerseOrSayingItems(bundle);
  // The verse-page ordering choice only matters for 'both' in separate mode with verses.
  const showVerseOrder = isSeparate && hasVerses && mode === 'both';

  const exportPdf = () => {
    setBusy(true);
    // Defer so the spinner paints before the (synchronous) PDF build.
    setTimeout(() => {
      try {
        const doc = buildCalendarPdf(bundle, theme, mode, settings.maxItemsPerMonthCell, { verseOrder });
        const name = `${APP_NAME}_${MONTH_NAMES[bundle.month - 1]}-${bundle.year}_${mode}_${timestamp()}.pdf`;
        downloadBlob(name, doc.output('blob'));
      } finally {
        setBusy(false);
        onClose();
      }
    }, 30);
  };

  const exportJson = () => {
    downloadText(`${slugify(bundle.title)}.cmcal.json`, exportBundleJson(bundle, theme));
  };

  return (
    <Modal
      title="Export"
      onClose={onClose}
      footer={<>
        <button onClick={exportJson}>Export bundle (.cmcal.json)</button>
        <div style={{ flex: 1 }} />
        <button onClick={onClose}>Cancel</button>
        <button className="primary" onClick={exportPdf} disabled={busy}>{busy ? 'Building…' : 'Export PDF'}</button>
      </>}
    >
      <div className="col">
        <label style={{ margin: 0 }}>Which view?</label>
        {([['month', 'Month view', 'A printable calendar grid (landscape).'],
          ['detail', 'Detail view', 'A date-ordered list of every day and its events (portrait).'],
          ['both', 'Both', 'Month grid first, then the detail list — one PDF.']] as const).map(([val, title, desc]) => (
          <label key={val} className="pill-toggle" style={{ cursor: 'pointer' }}>
            <div>
              <div style={{ fontWeight: 600 }}>{title}</div>
              <div className="hint">{desc}</div>
            </div>
            <input type="radio" name="mode" checked={mode === val} onChange={() => setMode(val)} style={{ width: 'auto' }} />
          </label>
        ))}

        {isSeparate && hasVerses && mode !== 'detail' && (
          <p className="hint" style={{ margin: '4px 0' }}>
            📖 A separate <b>Scripture &amp; Sayings</b> calendar page will be included (verse mode is “Separate”).
          </p>
        )}

        {showVerseOrder && (
          <div className="col" style={{ gap: 6, marginTop: 4 }}>
            <label style={{ margin: 0 }}>Page order</label>
            {([['verse-before-detail', 'Calendar → Scripture & Sayings → Detail'],
              ['verse-after-detail', 'Calendar → Detail → Scripture & Sayings']] as const).map(([val, title]) => (
              <label key={val} className="pill-toggle" style={{ cursor: 'pointer' }}>
                <div style={{ fontWeight: 600 }}>{title}</div>
                <input type="radio" name="verseOrder" checked={verseOrder === val} onChange={() => setVerseOrder(val)} style={{ width: 'auto' }} />
              </label>
            ))}
          </div>
        )}

        <p className="hint">Tip: set your browser’s download folder to <code>~/Downloads/CalendarMaker/</code> to keep exports together.</p>
      </div>
    </Modal>
  );
}
