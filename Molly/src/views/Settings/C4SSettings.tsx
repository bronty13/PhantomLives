import { useEffect, useState } from 'react';
import { useC4SPrefs, type C4SColumnPrefs } from '../../state/c4sPrefs';
import {
  c4sLastImports,
  deleteAllC4SData,
  type C4SImportRow,
} from '../../data/c4sClips';
import type { PersonaCode } from '../../lib/c4sClassify';
import { C4SImportWizard } from '../C4S/C4SImportWizard';
import { ConfirmButton } from '../../components/ConfirmButton';

const COLUMN_TOGGLES: { key: keyof C4SColumnPrefs; label: string; defaultOn: boolean; note?: string }[] = [
  { key: 'clipId',          label: 'Clip ID',           defaultOn: true },
  { key: 'clipStatus',      label: 'Status',            defaultOn: true },
  { key: 'categories',      label: 'Categories',        defaultOn: true },
  { key: 'keywords',        label: 'Keywords',          defaultOn: true },
  { key: 'price',           label: 'Price',             defaultOn: true },
  { key: 'salesCount',      label: 'Sales #',           defaultOn: true },
  { key: 'income6mo',       label: 'Income (6mo)',      defaultOn: true },
  { key: 'clipFilename',    label: 'Clip filename',     defaultOn: true },
  { key: 'clipThumbnail',   label: 'Thumbnail filename',defaultOn: true },
  { key: 'clipTrackingTag', label: 'Tracking tag',      defaultOn: false, note: '(usually empty)' },
  { key: 'clipPreview',     label: 'Preview filename',  defaultOn: false, note: '(usually empty)' },
];

const PERSONA_TINT: Record<string, { bg: string; fg: string; label: string }> = {
  CoC: { bg: '#FFC0CB', fg: '#5B2540', label: 'Curse Of Curves' },
  PoA: { bg: '#C8102E', fg: '#FFFFFF', label: 'Princess of Addiction' },
};

export function C4SSettings() {
  const [prefs, applyPrefs, applyColumns, resetPrefs] = useC4SPrefs();
  const [imports, setImports] = useState<C4SImportRow[]>([]);
  const [showImport, setShowImport] = useState(false);
  const [refreshToken, setRefreshToken] = useState(0);
  const [status, setStatus] = useState<string>('');

  useEffect(() => {
    let alive = true;
    c4sLastImports()
      .then((r) => { if (alive) setImports(r); })
      .catch((e) => { if (alive) setStatus(`Error loading imports: ${e}`); });
    return () => { alive = false; };
  }, [refreshToken]);

  async function onDeleteAll() {
    try {
      const r = await deleteAllC4SData();
      setStatus(`🗑 Wiped ${r.deletedClips} clip${r.deletedClips === 1 ? '' : 's'} + ${r.deletedImports} audit row${r.deletedImports === 1 ? '' : 's'}.`);
      setRefreshToken((t) => t + 1);
    } catch (e) {
      setStatus(`Delete failed: ${String(e)}`);
    }
  }

  return (
    <div className="space-y-4">
      <div className="pretty-card">
        <h3 className="display-font text-lg font-semibold persona-accent mb-2">Stale-data banner</h3>
        <p className="text-xs opacity-70 mb-2">
          Cute reminder on the C4S dashboard that shows how old the imported snapshot is.
        </p>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={prefs.showStaleBanner}
            onChange={(e) => applyPrefs({ showStaleBanner: e.target.checked })}
          />
          Show the “data is X days old” banner
        </label>
      </div>

      <div className="pretty-card">
        <h3 className="display-font text-lg font-semibold persona-accent mb-2">Visible columns</h3>
        <p className="text-xs opacity-70 mb-2">
          <strong>Persona</strong> and <strong>Title</strong> always show; everything else is optional.
        </p>
        <div className="grid grid-cols-2 gap-1.5">
          {COLUMN_TOGGLES.map((c) => (
            <label key={c.key} className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked={prefs.columns[c.key]}
                onChange={(e) => applyColumns({ [c.key]: e.target.checked } as Partial<C4SColumnPrefs>)}
              />
              {c.label}
              {c.note && <span className="text-xs opacity-50">{c.note}</span>}
            </label>
          ))}
        </div>
        <div className="mt-3">
          <button type="button" className="pretty-button secondary text-xs" onClick={resetPrefs}>
            Reset to defaults
          </button>
        </div>
      </div>

      <div className="pretty-card">
        <h3 className="display-font text-lg font-semibold persona-accent mb-2">Import</h3>
        <p className="text-xs opacity-70 mb-2">
          Replaces all data for the matched store in a single atomic transaction.
        </p>
        <button type="button" className="pretty-button" onClick={() => setShowImport(true)}>
          ✨ Import C4S CSV
        </button>
        {imports.length > 0 && (
          <div className="mt-3 space-y-1.5">
            <div className="text-xs uppercase tracking-wider opacity-60">Last imports</div>
            {imports.map((r) => {
              const tint = PERSONA_TINT[r.personaCode as PersonaCode];
              return (
                <div key={r.personaCode} className="flex items-center gap-2 text-sm">
                  <span
                    className="px-1.5 py-0.5 rounded-md text-[11px] font-semibold"
                    style={{ background: tint?.bg ?? '#ddd', color: tint?.fg ?? '#222' }}
                  >
                    {r.personaCode}
                  </span>
                  <span className="opacity-80">{tint?.label ?? r.personaCode}</span>
                  <span className="opacity-60">·</span>
                  <span className="font-mono text-xs opacity-70">{r.importedAt}</span>
                  <span className="opacity-60">·</span>
                  <span className="font-mono text-xs">{r.rowCount.toLocaleString()} clip{r.rowCount === 1 ? '' : 's'}</span>
                  <span className="opacity-60 text-xs truncate">{r.sourceFile}</span>
                </div>
              );
            })}
          </div>
        )}
      </div>

      <div className="pretty-card">
        <h3 className="display-font text-lg font-semibold persona-accent mb-2">Danger zone</h3>
        <p className="text-xs opacity-70 mb-2">
          Wipes all imported Clips4Sale data across both stores. Your MasterClipper clips, customers, expenses, etc. are <strong>not</strong> affected.
        </p>
        <ConfirmButton
          label="🗑 Delete all C4S data"
          confirmLabel="Really? This wipes both stores."
          variant="danger"
          onConfirm={onDeleteAll}
        />
      </div>

      {status && <div className="pretty-card text-sm"><strong>Status:</strong> {status}</div>}

      {showImport && (
        <C4SImportWizard
          onClose={() => setShowImport(false)}
          onImported={async () => {
            setRefreshToken((t) => t + 1);
          }}
        />
      )}
    </div>
  );
}
