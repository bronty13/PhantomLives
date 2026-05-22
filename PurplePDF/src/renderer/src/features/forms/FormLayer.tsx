// HTML overlay rendering interactive form widgets on top of a single page.
import type { CSSProperties } from 'react';
import type { FormFieldInfo, FormValues } from './types';

interface Viewport {
  width: number;
  height: number;
  convertToViewportPoint: (x: number, y: number) => number[];
}

interface Props {
  pageIndex: number;
  viewport: Viewport;
  fields: FormFieldInfo[];
  values: FormValues;
  onChange: (fieldName: string, value: string | boolean) => void;
  enabled: boolean;
}

function rectStyle(viewport: Viewport, r: FormFieldInfo['rect']): CSSProperties {
  const [x1, y1] = viewport.convertToViewportPoint(r.x, r.y);
  const [x2, y2] = viewport.convertToViewportPoint(r.x + r.w, r.y + r.h);
  return {
    position: 'absolute',
    left: Math.min(x1, x2),
    top: Math.min(y1, y2),
    width: Math.abs(x2 - x1),
    height: Math.abs(y2 - y1),
    pointerEvents: 'auto'
  };
}

export default function FormLayer({
  pageIndex,
  viewport,
  fields,
  values,
  onChange,
  enabled
}: Props): JSX.Element {
  const pageFields = fields.filter((f) => f.page === pageIndex);
  return (
    <div
      className="form-layer"
      style={{
        position: 'absolute',
        inset: 0,
        width: viewport.width,
        height: viewport.height,
        pointerEvents: 'none'
      }}
      aria-hidden={!enabled}
    >
      {pageFields.map((f) => {
        const style = rectStyle(viewport, f.rect);
        const v = values[f.fieldName];
        const ro = !!f.readOnly || !enabled;

        if (f.fieldType === 'text') {
          return (
            <input
              key={f.id}
              className="ff ff-text"
              style={style}
              value={typeof v === 'string' ? v : ''}
              maxLength={f.maxLength}
              readOnly={ro}
              title={f.tooltip ?? f.fieldName}
              onChange={(e) => onChange(f.fieldName, e.target.value)}
            />
          );
        }
        if (f.fieldType === 'multiline') {
          return (
            <textarea
              key={f.id}
              className="ff ff-text ff-multiline"
              style={style}
              value={typeof v === 'string' ? v : ''}
              maxLength={f.maxLength}
              readOnly={ro}
              title={f.tooltip ?? f.fieldName}
              onChange={(e) => onChange(f.fieldName, e.target.value)}
            />
          );
        }
        if (f.fieldType === 'checkbox') {
          return (
            <input
              key={f.id}
              type="checkbox"
              className="ff ff-checkbox"
              style={style}
              checked={!!v}
              disabled={ro}
              title={f.tooltip ?? f.fieldName}
              onChange={(e) => onChange(f.fieldName, e.target.checked)}
            />
          );
        }
        if (f.fieldType === 'radio') {
          const checked = typeof v === 'string' && v === f.exportValue;
          return (
            <input
              key={f.id}
              type="radio"
              className="ff ff-radio"
              style={style}
              checked={checked}
              disabled={ro}
              name={f.fieldName}
              title={f.tooltip ?? f.fieldName}
              onChange={() => onChange(f.fieldName, f.exportValue ?? '')}
            />
          );
        }
        if (f.fieldType === 'dropdown') {
          return (
            <select
              key={f.id}
              className="ff ff-dropdown"
              style={style}
              value={typeof v === 'string' ? v : ''}
              disabled={ro}
              title={f.tooltip ?? f.fieldName}
              onChange={(e) => onChange(f.fieldName, e.target.value)}
            >
              <option value="">—</option>
              {(f.options ?? []).map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
          );
        }
        if (f.fieldType === 'listbox') {
          return (
            <select
              key={f.id}
              className="ff ff-listbox"
              style={style}
              value={typeof v === 'string' ? v : ''}
              disabled={ro}
              title={f.tooltip ?? f.fieldName}
              onChange={(e) => onChange(f.fieldName, e.target.value)}
              size={Math.max(2, (f.options ?? []).length)}
            >
              {(f.options ?? []).map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
          );
        }
        if (f.fieldType === 'signature') {
          return (
            <div
              key={f.id}
              className="ff ff-signature"
              style={style}
              title={f.tooltip ?? f.fieldName}
            >
              ✍ {typeof v === 'string' && v ? v : 'Signature'}
            </div>
          );
        }
        // 'button' (push button) — render an inert placeholder; we don't
        // execute embedded actions / JS.
        return (
          <div
            key={f.id}
            className="ff ff-button"
            style={style}
            title={f.tooltip ?? f.fieldName}
          />
        );
      })}
    </div>
  );
}
