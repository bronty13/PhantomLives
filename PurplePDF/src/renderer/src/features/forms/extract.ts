// Walk a PDF and extract form-field metadata from every page's annotations.
import type { PDFDocumentProxy } from '../viewer/pdfjs';
import type { FormFieldInfo, FormFieldType, FormFieldOption } from './types';

interface PdfWidgetAnnotation {
  subtype?: string;
  id?: string;
  fieldType?: string;
  fieldName?: string;
  fullName?: string;
  rect?: number[];
  fieldValue?: string | string[];
  defaultFieldValue?: string;
  buttonValue?: string;
  options?: Array<{ exportValue: string; displayValue: string }>;
  combo?: boolean;
  multiSelect?: boolean;
  multiLine?: boolean;
  checkBox?: boolean;
  radioButton?: boolean;
  pushButton?: boolean;
  readOnly?: boolean;
  required?: boolean;
  maxLen?: number;
  alternativeText?: string;
}

function classify(a: PdfWidgetAnnotation): FormFieldType | null {
  if (a.fieldType === 'Tx') return a.multiLine ? 'multiline' : 'text';
  if (a.fieldType === 'Btn') {
    if (a.checkBox) return 'checkbox';
    if (a.radioButton) return 'radio';
    if (a.pushButton) return 'button';
    return 'checkbox';
  }
  if (a.fieldType === 'Ch') return a.combo ? 'dropdown' : 'listbox';
  if (a.fieldType === 'Sig') return 'signature';
  return null;
}

export async function extractFormFields(doc: PDFDocumentProxy): Promise<FormFieldInfo[]> {
  const out: FormFieldInfo[] = [];
  for (let pageNum = 1; pageNum <= doc.numPages; pageNum++) {
    const page = await doc.getPage(pageNum);
    const raws = (await page.getAnnotations({ intent: 'display' })) as PdfWidgetAnnotation[];
    for (const a of raws) {
      if (a.subtype !== 'Widget') continue;
      const type = classify(a);
      if (!type) continue;
      const name = a.fieldName ?? a.fullName;
      if (!name) continue;

      const rect = a.rect ?? [0, 0, 0, 0];
      const [x1, y1, x2, y2] = rect;
      const x = Math.min(x1, x2);
      const y = Math.min(y1, y2);
      const w = Math.abs(x2 - x1);
      const h = Math.abs(y2 - y1);

      let options: FormFieldOption[] | undefined;
      if (a.options && Array.isArray(a.options)) {
        options = a.options.map((o) => ({ value: o.exportValue, label: o.displayValue }));
      }

      let defaultValue: string | boolean = '';
      if (type === 'checkbox') {
        const fv = Array.isArray(a.fieldValue) ? a.fieldValue[0] : (a.fieldValue ?? '');
        defaultValue = !!fv && fv !== 'Off';
      } else {
        defaultValue = Array.isArray(a.fieldValue) ? (a.fieldValue[0] ?? '') : (a.fieldValue ?? '');
      }

      out.push({
        id: a.id ?? `${name}-${pageNum}-${out.length}`,
        fieldName: name,
        fieldType: type,
        page: pageNum - 1,
        rect: { x, y, w, h },
        defaultValue,
        options,
        exportValue: a.buttonValue,
        readOnly: a.readOnly,
        required: a.required,
        maxLength: a.maxLen,
        tooltip: a.alternativeText
      });
    }
  }
  return out;
}

/**
 * Roll up widget defaults into a flat values record keyed by fieldName.
 * For groups with multiple widgets (e.g. radio), keep the first non-empty default.
 */
export function initialValues(fields: FormFieldInfo[]): Record<string, string | boolean> {
  const out: Record<string, string | boolean> = {};
  for (const f of fields) {
    if (f.fieldName in out) {
      const cur = out[f.fieldName];
      if (cur === '' || cur === false) out[f.fieldName] = f.defaultValue;
      continue;
    }
    out[f.fieldName] = f.defaultValue;
  }
  return out;
}
