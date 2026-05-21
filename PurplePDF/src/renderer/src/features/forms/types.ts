// AcroForm support — extract / render / persist form field values.
import type { PdfRect } from '../annotate/types';

export type FormFieldType =
  | 'text'
  | 'multiline'
  | 'checkbox'
  | 'radio'
  | 'dropdown'
  | 'listbox'
  | 'signature'
  | 'button';

export interface FormFieldOption {
  value: string;
  label: string;
}

export interface FormFieldInfo {
  /** Stable per-widget id (multiple widgets can share a fieldName, e.g. radio). */
  id: string;
  fieldName: string;
  fieldType: FormFieldType;
  page: number; // 0-based
  rect: PdfRect; // PDF coords (origin bottom-left)
  defaultValue: string | boolean;
  options?: FormFieldOption[];
  /** For radio button widgets: the value this specific widget represents. */
  exportValue?: string;
  readOnly?: boolean;
  required?: boolean;
  maxLength?: number;
  tooltip?: string;
}

/** Renderer-side form value map. Key = fieldName. */
export type FormValues = Record<string, string | boolean>;
