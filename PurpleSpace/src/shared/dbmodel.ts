/**
 * @file dbmodel.ts — Notion-style database model: property definitions,
 * cell values, sorting and filtering. Pure (no Electron/React); unit-tested.
 *
 * A database page stores `dbPropsJson` = serialized `DbConfig`.
 * A row page stores `rowValuesJson` = serialized `Record<propId, CellValue>`.
 * The row's `title` doubles as the (required) title property, like Notion.
 */

export type PropType =
  | 'title'
  | 'text'
  | 'number'
  | 'select'
  | 'multiSelect'
  | 'date'
  | 'checkbox'
  | 'url';

export interface SelectOption {
  id: string;
  name: string;
  /** Index into the tag palette (renderer maps to colors). */
  color: number;
}

export interface PropDef {
  id: string;
  name: string;
  type: PropType;
  options?: SelectOption[];
}

export interface SortRule {
  propId: string;
  dir: 'asc' | 'desc';
}

export type FilterOp =
  | 'contains'
  | 'notContains'
  | 'is'
  | 'isNot'
  | 'isEmpty'
  | 'isNotEmpty'
  | 'gt'
  | 'lt'
  | 'checked'
  | 'unchecked';

export interface FilterRule {
  propId: string;
  op: FilterOp;
  value?: string;
}

export interface DbConfig {
  properties: PropDef[];
  sorts: SortRule[];
  filters: FilterRule[];
}

/** string for text/url/date(ISO)/select(optionId); number; boolean; string[] for multiSelect. */
export type CellValue = string | number | boolean | string[] | null;

export interface RowData {
  id: string;
  title: string;
  icon: string | null;
  values: Record<string, CellValue>;
  createdAt: number;
}

export const DEFAULT_DB_CONFIG: DbConfig = {
  properties: [
    { id: 'title', name: 'Name', type: 'title' },
    { id: 'p_tags', name: 'Tags', type: 'multiSelect', options: [] },
    { id: 'p_date', name: 'Date', type: 'date' }
  ],
  sorts: [],
  filters: []
};

export function parseDbConfig(json: string | null | undefined): DbConfig {
  if (!json) return structuredClone(DEFAULT_DB_CONFIG);
  try {
    const cfg = JSON.parse(json) as Partial<DbConfig>;
    return {
      properties:
        Array.isArray(cfg.properties) && cfg.properties.length
          ? (cfg.properties as PropDef[])
          : structuredClone(DEFAULT_DB_CONFIG.properties),
      sorts: Array.isArray(cfg.sorts) ? (cfg.sorts as SortRule[]) : [],
      filters: Array.isArray(cfg.filters) ? (cfg.filters as FilterRule[]) : []
    };
  } catch {
    return structuredClone(DEFAULT_DB_CONFIG);
  }
}

export function parseRowValues(json: string | null | undefined): Record<string, CellValue> {
  if (!json) return {};
  try {
    const v = JSON.parse(json);
    return v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, CellValue>) : {};
  } catch {
    return {};
  }
}

function rowValue(row: RowData, prop: PropDef): CellValue {
  if (prop.type === 'title') return row.title;
  return row.values[prop.id] ?? null;
}

/** Human/compare key for a cell under its property type. */
function compareKey(value: CellValue, prop: PropDef): string | number {
  if (value == null) return prop.type === 'number' ? Number.NEGATIVE_INFINITY : '';
  switch (prop.type) {
    case 'number':
      return typeof value === 'number' ? value : Number(value) || 0;
    case 'checkbox':
      return value ? 1 : 0;
    case 'select': {
      const opt = prop.options?.find((o) => o.id === value);
      return (opt?.name ?? '').toLowerCase();
    }
    case 'multiSelect': {
      const ids = Array.isArray(value) ? value : [];
      return ids
        .map((id) => prop.options?.find((o) => o.id === id)?.name ?? '')
        .join(',')
        .toLowerCase();
    }
    default:
      return String(value).toLowerCase();
  }
}

function isEmptyValue(value: CellValue): boolean {
  if (value == null || value === '' || value === false) return true;
  if (Array.isArray(value)) return value.length === 0;
  return false;
}

export function matchesFilter(row: RowData, rule: FilterRule, props: PropDef[]): boolean {
  const prop = props.find((p) => p.id === rule.propId);
  if (!prop) return true;
  const value = rowValue(row, prop);
  const needle = (rule.value ?? '').toLowerCase();
  const key = String(compareKey(value, prop)).toLowerCase();
  switch (rule.op) {
    case 'contains':
      return key.includes(needle);
    case 'notContains':
      return !key.includes(needle);
    case 'is':
      return prop.type === 'select' || prop.type === 'multiSelect'
        ? Array.isArray(value)
          ? value.includes(rule.value ?? '')
          : value === (rule.value ?? '')
        : key === needle;
    case 'isNot':
      return prop.type === 'select' || prop.type === 'multiSelect'
        ? Array.isArray(value)
          ? !value.includes(rule.value ?? '')
          : value !== (rule.value ?? '')
        : key !== needle;
    case 'isEmpty':
      return isEmptyValue(value);
    case 'isNotEmpty':
      return !isEmptyValue(value);
    case 'gt':
      return Number(compareKey(value, prop)) > Number(rule.value ?? 0);
    case 'lt':
      return Number(compareKey(value, prop)) < Number(rule.value ?? 0);
    case 'checked':
      return value === true;
    case 'unchecked':
      return value !== true;
    default:
      return true;
  }
}

/** Apply filters then sorts (stable; falls back to creation order). */
export function viewRows(rows: RowData[], cfg: DbConfig): RowData[] {
  let out = rows.filter((r) => cfg.filters.every((f) => matchesFilter(r, f, cfg.properties)));
  out = [...out].sort((a, b) => {
    for (const s of cfg.sorts) {
      const prop = cfg.properties.find((p) => p.id === s.propId);
      if (!prop) continue;
      const ka = compareKey(rowValue(a, prop), prop);
      const kb = compareKey(rowValue(b, prop), prop);
      const cmp =
        typeof ka === 'number' && typeof kb === 'number'
          ? ka - kb
          : String(ka).localeCompare(String(kb));
      if (cmp !== 0) return s.dir === 'asc' ? cmp : -cmp;
    }
    return a.createdAt - b.createdAt;
  });
  return out;
}

let idCounter = 0;
export function freshId(prefix: string): string {
  idCounter = (idCounter + 1) % 0xffff;
  return `${prefix}_${Date.now().toString(36)}${idCounter.toString(36)}`;
}

export const TAG_PALETTE_SIZE = 8;

export function nextTagColor(options: SelectOption[]): number {
  return options.length % TAG_PALETTE_SIZE;
}

/** A database rendered as a Markdown table (used by Export as Markdown). */
export function databaseToMarkdown(
  title: string,
  dbPropsJson: string | null | undefined,
  rows: RowData[]
): string {
  const cfg = parseDbConfig(dbPropsJson);
  const props = cfg.properties;
  const esc = (s: string): string => s.replace(/\|/g, '\\|').replace(/\n/g, ' ');
  const header = `| ${props.map((p) => esc(p.name)).join(' | ')} |`;
  const sep = `| ${props.map(() => '---').join(' | ')} |`;
  const lines = rows.map(
    (r) =>
      `| ${props
        .map((p) => esc(p.type === 'title' ? r.title || 'Untitled' : cellToText(r.values[p.id] ?? null, p)))
        .join(' | ')} |`
  );
  return `# ${title}\n\n${[header, sep, ...lines].join('\n')}\n`;
}

/** Display string for a cell (markdown export, plain rendering). */
export function cellToText(value: CellValue, prop: PropDef): string {
  if (value == null) return '';
  switch (prop.type) {
    case 'checkbox':
      return value ? '✓' : '';
    case 'select':
      return prop.options?.find((o) => o.id === value)?.name ?? '';
    case 'multiSelect':
      return (Array.isArray(value) ? value : [])
        .map((id) => prop.options?.find((o) => o.id === id)?.name ?? '')
        .filter(Boolean)
        .join(', ');
    default:
      return String(value);
  }
}
