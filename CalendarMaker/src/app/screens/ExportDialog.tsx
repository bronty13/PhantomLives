import { useState } from 'react';
import type { AppSettings, CalendarBundle, ExportMode, Theme } from '../../model/types';
import { APP_NAME, MONTH_NAMES } from '../../model/types';
import { exportBundleJson } from '../../storage/bundleIO';
import { buildCalendarPdf } from '../../pdf/exportPdf';
import { Modal } from '../components/Modal';
import { downloadBlob, downloadText, slugify, timestamp } from '../util';

export function ExportDialog({ bundle, theme, settings, onClose }: { bundle: CalendarBundle; theme: Theme; settings: AppSettings; onClose: () => void }) {
  const [mode, setMode] = useState<ExportMode>(settings.defaultExportMode);
  const [busy, setBusy] = useState(false);

  const exportPdf = () => {
    setBusy(true);
    // Defer so the spinner paints before the (synchronous) PDF build.
    setTimeout(() => {
      try {
        const doc = buildCalendarPdf(bundle, theme, mode, settings.maxItemsPerMonthCell);
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
        <p className="hint">Tip: set your browser’s download folder to <code>~/Downloads/CalendarMaker/</code> to keep exports together.</p>
      </div>
    </Modal>
  );
}
