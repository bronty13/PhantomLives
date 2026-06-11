import React, { useMemo, useState } from 'react';
import { useMutation, useQuery } from 'convex/react';
import { api } from '../../../../convex/_generated/api';
import type { Doc, Id } from '../../../../convex/_generated/dataModel';
import {
  parseDbConfig,
  parseRowValues,
  viewRows,
  freshId,
  type CellValue,
  type DbConfig,
  type FilterOp,
  type PropDef,
  type PropType,
  type RowData,
  type SelectOption
} from '../../../shared/dbmodel';
import { ArrowUpDown, FilterGlyph, Plus, TrashGlyph, RenameGlyph, TYPE_GLYPHS, PageGlyph } from '../lib/icons';
import { Menu, MenuItem, MenuSep, MenuNote, Popover } from './Popover';
import { Cell, makeOption } from './cells';

const PROP_TYPES: { type: PropType; label: string }[] = [
  { type: 'text', label: 'Text' },
  { type: 'number', label: 'Number' },
  { type: 'select', label: 'Select' },
  { type: 'multiSelect', label: 'Multi-select' },
  { type: 'date', label: 'Date' },
  { type: 'checkbox', label: 'Checkbox' },
  { type: 'url', label: 'URL' }
];

const FILTER_OPS: { op: FilterOp; label: string; needsValue: boolean }[] = [
  { op: 'contains', label: 'contains', needsValue: true },
  { op: 'notContains', label: 'does not contain', needsValue: true },
  { op: 'is', label: 'is', needsValue: true },
  { op: 'isNot', label: 'is not', needsValue: true },
  { op: 'isEmpty', label: 'is empty', needsValue: false },
  { op: 'isNotEmpty', label: 'is not empty', needsValue: false },
  { op: 'gt', label: '>', needsValue: true },
  { op: 'lt', label: '<', needsValue: true },
  { op: 'checked', label: 'is checked', needsValue: false },
  { op: 'unchecked', label: 'is unchecked', needsValue: false }
];

interface DatabaseViewProps {
  pageId: string;
  dbPropsJson: string | null;
  onOpenRow: (id: string) => void;
  rowsForExport: React.MutableRefObject<RowData[]>;
  showToast: (msg: string) => void;
}

export default function DatabaseView(props: DatabaseViewProps): React.JSX.Element {
  const { pageId, dbPropsJson, onOpenRow } = props;
  const rowDocs = useQuery(api.pages.rows, { databaseId: pageId as Id<'pages'> });
  const setDbProps = useMutation(api.pages.setDbProps);
  const setRowValues = useMutation(api.pages.setRowValues);
  const renamePage = useMutation(api.pages.rename);
  const createPage = useMutation(api.pages.create);
  const trashPage = useMutation(api.pages.trash);

  const [headMenu, setHeadMenu] = useState<{ prop: PropDef; at: { x: number; y: number } } | null>(null);
  const [renamingProp, setRenamingProp] = useState<string | null>(null);
  const [filterAt, setFilterAt] = useState<{ x: number; y: number } | null>(null);
  const [sortAt, setSortAt] = useState<{ x: number; y: number } | null>(null);
  const [editingTitle, setEditingTitle] = useState<string | null>(null);

  const cfg = useMemo(() => parseDbConfig(dbPropsJson), [dbPropsJson]);

  const rows: RowData[] = useMemo(
    () =>
      (rowDocs ?? []).map((r) => ({
        id: r._id as string,
        title: r.title,
        icon: r.icon,
        values: parseRowValues(r.rowValuesJson),
        createdAt: r.createdAt
      })),
    [rowDocs]
  );

  const visible = useMemo(() => viewRows(rows, cfg), [rows, cfg]);
  props.rowsForExport.current = visible;

  const saveCfg = (next: DbConfig): void => {
    void setDbProps({ id: pageId as Id<'pages'>, dbPropsJson: JSON.stringify(next) });
  };

  const updateProp = (propId: string, patch: Partial<PropDef>): void => {
    saveCfg({
      ...cfg,
      properties: cfg.properties.map((p) => (p.id === propId ? { ...p, ...patch } : p))
    });
  };

  const addOption = (propId: string) => (name: string): SelectOption => {
    const prop = cfg.properties.find((p) => p.id === propId);
    const opt = makeOption(prop?.options ?? [], name);
    updateProp(propId, { options: [...(prop?.options ?? []), opt] });
    return opt;
  };

  const setValue = (row: RowData, propId: string, value: CellValue): void => {
    const next = { ...row.values, [propId]: value };
    if (value === null) delete next[propId];
    void setRowValues({ id: row.id as Id<'pages'>, rowValuesJson: JSON.stringify(next) });
  };

  const addRow = async (): Promise<void> => {
    const id = await createPage({ parentId: pageId as Id<'pages'>, type: 'doc' });
    setEditingTitle(id as string);
  };

  const activeSort = cfg.sorts[0] ?? null;
  const sortPropName = activeSort
    ? cfg.properties.find((p) => p.id === activeSort.propId)?.name
    : null;

  return (
    <div className="db-wrap scrolly">
      <div className="db-toolbar">
        <button className={`chip ${cfg.filters.length ? 'on' : ''}`} onClick={(e) => setFilterAt({ x: e.clientX, y: e.clientY + 6 })}>
          <FilterGlyph />
          {cfg.filters.length ? `${cfg.filters.length} filter${cfg.filters.length > 1 ? 's' : ''}` : 'Filter'}
        </button>
        <button className={`chip ${activeSort ? 'on' : ''}`} onClick={(e) => setSortAt({ x: e.clientX, y: e.clientY + 6 })}>
          <ArrowUpDown />
          {activeSort ? `Sorted by ${sortPropName} ${activeSort.dir === 'asc' ? '↑' : '↓'}` : 'Sort'}
        </button>
        <div className="spacer" />
        <button className="btn primary" onClick={() => void addRow()}>
          New row
        </button>
      </div>

      <table className="db-table">
        <thead>
          <tr>
            {cfg.properties.map((prop) => (
              <th key={prop.id} style={prop.type === 'title' ? { minWidth: 240 } : undefined}>
                {renamingProp === prop.id ? (
                  <input
                    autoFocus
                    type="text"
                    defaultValue={prop.name}
                    style={{
                      width: '100%',
                      border: 'none',
                      outline: '2px solid var(--accent)',
                      outlineOffset: -2,
                      padding: '6px 10px',
                      font: 'inherit',
                      background: 'var(--paper-elev)'
                    }}
                    onBlur={(e) => {
                      updateProp(prop.id, { name: e.target.value || prop.name });
                      setRenamingProp(null);
                    }}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter' || e.key === 'Escape') (e.target as HTMLInputElement).blur();
                    }}
                  />
                ) : (
                  <button
                    className="db-th"
                    onClick={(e) => setHeadMenu({ prop, at: { x: e.clientX, y: e.clientY + 4 } })}
                  >
                    <span className="type-glyph">{TYPE_GLYPHS[prop.type]}</span>
                    <span>{prop.name}</span>
                  </button>
                )}
              </th>
            ))}
            <th className="db-add-col">
              <button
                title="Add a property"
                onClick={() =>
                  saveCfg({
                    ...cfg,
                    properties: [...cfg.properties, { id: freshId('p'), name: 'New property', type: 'text' }]
                  })
                }
              >
                <Plus />
              </button>
            </th>
          </tr>
        </thead>
        <tbody>
          {visible.map((row) => (
            <tr key={row.id}>
              {cfg.properties.map((prop) =>
                prop.type === 'title' ? (
                  <td key={prop.id}>
                    {editingTitle === row.id ? (
                      <div className="db-cell editing">
                        <input
                          autoFocus
                          type="text"
                          defaultValue={row.title}
                          onBlur={(e) => {
                            void renamePage({ id: row.id as Id<'pages'>, title: e.target.value });
                            setEditingTitle(null);
                          }}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter' || e.key === 'Escape') (e.target as HTMLInputElement).blur();
                          }}
                        />
                      </div>
                    ) : (
                      <div className="db-cell db-title-cell" onClick={() => setEditingTitle(row.id)}>
                        <span className="tree-icon">{row.icon ?? <PageGlyph size={13} />}</span>
                        <span>{row.title || <span style={{ color: 'var(--ink-3)' }}>Untitled</span>}</span>
                        <button
                          className="db-open-row"
                          onClick={(e) => {
                            e.stopPropagation();
                            onOpenRow(row.id);
                          }}
                        >
                          ⤢ Open
                        </button>
                      </div>
                    )}
                  </td>
                ) : (
                  <td key={prop.id}>
                    <Cell
                      prop={prop}
                      value={row.values[prop.id] ?? null}
                      onChange={(v) => setValue(row, prop.id, v)}
                      onAddOption={addOption(prop.id)}
                    />
                  </td>
                )
              )}
              <td className="db-add-col">
                <button
                  title="Delete row"
                  onClick={() => {
                    void trashPage({ id: row.id as Id<'pages'> });
                    props.showToast(`Moved “${row.title || 'Untitled'}” to Trash`);
                  }}
                >
                  <TrashGlyph size={12} />
                </button>
              </td>
            </tr>
          ))}
          <tr>
            <td colSpan={cfg.properties.length + 1} style={{ border: '1px solid var(--line)' }}>
              <button className="db-add-row" onClick={() => void addRow()}>
                <Plus size={12} />
                New row
              </button>
            </td>
          </tr>
        </tbody>
      </table>
      <div className="db-count">
        {visible.length === rows.length
          ? `${rows.length} row${rows.length === 1 ? '' : 's'}`
          : `${visible.length} of ${rows.length} rows (filtered)`}
      </div>

      {headMenu && (
        <Menu at={headMenu.at} onClose={() => setHeadMenu(null)}>
          <MenuItem icon={<RenameGlyph />} label="Rename" onClick={() => setRenamingProp(headMenu.prop.id)} />
          {headMenu.prop.type !== 'title' && (
            <>
              <MenuSep />
              <MenuNote>Property type</MenuNote>
              {PROP_TYPES.map((t) => (
                <MenuItem
                  key={t.type}
                  icon={<span style={{ width: 16, textAlign: 'center', opacity: 0.7 }}>{TYPE_GLYPHS[t.type]}</span>}
                  label={`${t.label}${headMenu.prop.type === t.type ? '  ✓' : ''}`}
                  onClick={() => updateProp(headMenu.prop.id, { type: t.type, options: headMenu.prop.options ?? [] })}
                />
              ))}
            </>
          )}
          <MenuSep />
          <MenuItem
            icon={<ArrowUpDown />}
            label="Sort ascending"
            onClick={() => saveCfg({ ...cfg, sorts: [{ propId: headMenu.prop.id, dir: 'asc' }] })}
          />
          <MenuItem
            icon={<ArrowUpDown />}
            label="Sort descending"
            onClick={() => saveCfg({ ...cfg, sorts: [{ propId: headMenu.prop.id, dir: 'desc' }] })}
          />
          {headMenu.prop.type !== 'title' && (
            <>
              <MenuSep />
              <MenuItem
                icon={<TrashGlyph />}
                label="Delete property"
                danger
                onClick={() =>
                  saveCfg({
                    ...cfg,
                    properties: cfg.properties.filter((p) => p.id !== headMenu.prop.id),
                    sorts: cfg.sorts.filter((s) => s.propId !== headMenu.prop.id),
                    filters: cfg.filters.filter((f) => f.propId !== headMenu.prop.id)
                  })
                }
              />
            </>
          )}
        </Menu>
      )}

      {filterAt && (
        <FilterPopover at={filterAt} cfg={cfg} onSave={saveCfg} onClose={() => setFilterAt(null)} />
      )}
      {sortAt && (
        <Popover at={sortAt} onClose={() => setSortAt(null)} className="menu">
          <MenuNote>Sort by</MenuNote>
          {cfg.properties.map((p) => (
            <button
              key={p.id}
              className="opt-row"
              style={{ width: '100%', textAlign: 'left' }}
              onClick={() => {
                const dir = activeSort?.propId === p.id && activeSort.dir === 'asc' ? 'desc' : 'asc';
                saveCfg({ ...cfg, sorts: [{ propId: p.id, dir }] });
              }}
            >
              <span style={{ width: 16, textAlign: 'center', opacity: 0.7 }}>{TYPE_GLYPHS[p.type]}</span>
              <span style={{ flex: 1 }}>{p.name}</span>
              {activeSort?.propId === p.id && <span>{activeSort.dir === 'asc' ? '↑' : '↓'}</span>}
            </button>
          ))}
          {activeSort && (
            <>
              <MenuSep />
              <MenuItem icon={<TrashGlyph size={13} />} label="Remove sort" onClick={() => saveCfg({ ...cfg, sorts: [] })} />
            </>
          )}
        </Popover>
      )}
    </div>
  );
}

// ---- Filter builder -----------------------------------------------------------

function FilterPopover({
  at,
  cfg,
  onSave,
  onClose
}: {
  at: { x: number; y: number };
  cfg: DbConfig;
  onSave: (cfg: DbConfig) => void;
  onClose: () => void;
}): React.JSX.Element {
  const [propId, setPropId] = useState(cfg.properties[0]?.id ?? 'title');
  const [op, setOp] = useState<FilterOp>('contains');
  const [value, setValue] = useState('');
  const needsValue = FILTER_OPS.find((f) => f.op === op)?.needsValue ?? true;

  const selStyle: React.CSSProperties = {
    background: 'var(--paper-dim)',
    border: '1px solid var(--line-strong)',
    borderRadius: 6,
    padding: '4px 6px',
    fontSize: 12.5,
    color: 'var(--ink)'
  };

  return (
    <Popover at={at} onClose={onClose} className="menu">
      {cfg.filters.length > 0 && (
        <>
          <MenuNote>Active filters</MenuNote>
          {cfg.filters.map((f, i) => {
            const p = cfg.properties.find((pp) => pp.id === f.propId);
            return (
              <div key={i} className="opt-row">
                <span style={{ flex: 1 }}>
                  {p?.name ?? '?'} {FILTER_OPS.find((o) => o.op === f.op)?.label}
                  {f.value ? ` “${f.value}”` : ''}
                </span>
                <button
                  className="tree-action"
                  title="Remove filter"
                  onClick={() => onSave({ ...cfg, filters: cfg.filters.filter((_, j) => j !== i) })}
                >
                  <TrashGlyph size={12} />
                </button>
              </div>
            );
          })}
          <MenuSep />
        </>
      )}
      <MenuNote>Add a filter</MenuNote>
      <div style={{ display: 'flex', gap: 6, padding: '2px 6px 8px', flexWrap: 'wrap' }}>
        <select style={selStyle} value={propId} onChange={(e) => setPropId(e.target.value)}>
          {cfg.properties.map((p) => (
            <option key={p.id} value={p.id}>
              {p.name}
            </option>
          ))}
        </select>
        <select style={selStyle} value={op} onChange={(e) => setOp(e.target.value as FilterOp)}>
          {FILTER_OPS.map((o) => (
            <option key={o.op} value={o.op}>
              {o.label}
            </option>
          ))}
        </select>
        {needsValue && (
          <input
            style={{ ...selStyle, width: 110 }}
            type="text"
            placeholder="Value"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                onSave({ ...cfg, filters: [...cfg.filters, { propId, op, value }] });
                setValue('');
              }
            }}
          />
        )}
        <button
          className="btn primary"
          style={{ padding: '3px 10px', fontSize: 12.5 }}
          onClick={() => {
            onSave({ ...cfg, filters: [...cfg.filters, { propId, op, value: needsValue ? value : undefined }] });
            setValue('');
          }}
        >
          Add
        </button>
      </div>
    </Popover>
  );
}

// ---- Row-page property strip ----------------------------------------------------

export function RowProperties({
  rowId,
  row,
  database
}: {
  rowId: string;
  row: Doc<'pages'>;
  database: Doc<'pages'>;
}): React.JSX.Element {
  const setRowValues = useMutation(api.pages.setRowValues);
  const setDbProps = useMutation(api.pages.setDbProps);
  const cfg = useMemo(() => parseDbConfig(database.dbPropsJson), [database.dbPropsJson]);
  const values = useMemo(() => parseRowValues(row.rowValuesJson), [row.rowValuesJson]);

  const setValue = (propId: string, value: CellValue): void => {
    const next = { ...values, [propId]: value };
    if (value === null) delete next[propId];
    void setRowValues({ id: rowId as Id<'pages'>, rowValuesJson: JSON.stringify(next) });
  };

  const addOption = (propId: string) => (name: string): SelectOption => {
    const prop = cfg.properties.find((p) => p.id === propId);
    const opt = makeOption(prop?.options ?? [], name);
    void setDbProps({
      id: database._id,
      dbPropsJson: JSON.stringify({
        ...cfg,
        properties: cfg.properties.map((p) =>
          p.id === propId ? { ...p, options: [...(p.options ?? []), opt] } : p
        )
      })
    });
    return opt;
  };

  const props = cfg.properties.filter((p) => p.type !== 'title');
  if (!props.length) return <></>;

  return (
    <div style={{ margin: '6px 0 2px', borderBottom: '1px solid var(--line)', paddingBottom: 10 }}>
      {props.map((prop) => (
        <div key={prop.id} style={{ display: 'flex', alignItems: 'flex-start', gap: 8, fontSize: 13.5 }}>
          <div style={{ width: 140, flex: '0 0 auto', color: 'var(--ink-3)', padding: '7px 0', display: 'flex', gap: 6 }}>
            <span style={{ opacity: 0.8 }}>{TYPE_GLYPHS[prop.type]}</span>
            {prop.name}
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <Cell
              prop={prop}
              value={values[prop.id] ?? null}
              onChange={(v) => setValue(prop.id, v)}
              onAddOption={addOption(prop.id)}
            />
          </div>
        </div>
      ))}
    </div>
  );
}

export { databaseToMarkdown } from '../../../shared/dbmodel';
