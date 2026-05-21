// Sidebar panel: list every form field with a live value, clickable to jump.
import type { FormFieldInfo, FormValues } from './types';

interface Props {
  fields: FormFieldInfo[];
  values: FormValues;
  onJump: (pageIndex: number) => void;
  onReset: () => void;
  onExportJson: () => void;
  onExportCsv: () => void;
}

function renderValue(v: string | boolean | undefined): string {
  if (v === undefined) return '';
  if (typeof v === 'boolean') return v ? '✓' : '';
  return v;
}

export default function FormsPanel({
  fields,
  values,
  onJump,
  onReset,
  onExportJson,
  onExportCsv
}: Props): JSX.Element {
  const grouped = new Map<string, FormFieldInfo>();
  for (const f of fields) {
    if (!grouped.has(f.fieldName)) grouped.set(f.fieldName, f);
  }
  const rows = Array.from(grouped.values());

  if (rows.length === 0) {
    return (
      <div className="forms-panel">
        <p className="empty">This document has no interactive form fields.</p>
      </div>
    );
  }

  const filled = rows.filter((f) => {
    const v = values[f.fieldName];
    return typeof v === 'boolean' ? v : (v ?? '') !== '';
  }).length;

  return (
    <div className="forms-panel">
      <div className="forms-head">
        <span>
          {filled} / {rows.length} filled
        </span>
        <div className="forms-actions">
          <button type="button" onClick={onExportJson} title="Export as JSON">
            JSON
          </button>
          <button type="button" onClick={onExportCsv} title="Export as CSV">
            CSV
          </button>
          <button type="button" onClick={onReset} title="Reset to original values">
            Reset
          </button>
        </div>
      </div>
      <ul className="forms-list">
        {rows.map((f) => (
          <li key={f.fieldName}>
            <button type="button" onClick={() => onJump(f.page)}>
              <span className="field-name">{f.fieldName}</span>
              <span className={`field-type ff-tag-${f.fieldType}`}>{f.fieldType}</span>
              <span className="field-value">{renderValue(values[f.fieldName])}</span>
              <span className="field-page">p.{f.page + 1}</span>
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
