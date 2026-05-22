import { useState } from 'react';
import type { Persona } from '../../state/personas';
import type { C4SClip } from '../../data/c4sClips';
import { C4SDashboard, type DrillFilter } from './C4SDashboard';
import { C4SGrid } from './C4SGrid';
import { C4SDetail } from './C4SDetail';
import { C4SImportWizard } from './C4SImportWizard';

interface Props {
  active: Persona;
}

type SubView = 'dashboard' | 'grid' | 'detail';

export function C4SView({ active }: Props) {
  const [sub, setSub] = useState<SubView>('dashboard');
  const [selected, setSelected] = useState<C4SClip | null>(null);
  const [showImport, setShowImport] = useState(false);
  // Bumping this on any successful import triggers a re-fetch in
  // children so the user sees fresh data immediately after closing
  // the wizard.
  const [refreshToken, setRefreshToken] = useState(0);
  // The most recent drill-down click on the dashboard. Sent into the
  // grid via prop on each click; the grid copies into its own state on
  // change so the user can refine further (or clear via the pill).
  // Reset to undefined when the user goes back to dashboard or clicks
  // the Grid tab directly — that's the "show me everything" intent.
  const [drillFilter, setDrillFilter] = useState<DrillFilter | undefined>(undefined);
  // Bumping this each time a drill-down fires forces the grid's
  // useEffect to re-seed even if the user re-clicks the same value.
  const [drillNonce, setDrillNonce] = useState(0);

  return (
    <div className="p-8 max-w-6xl space-y-4">
      <div className="flex items-center gap-2 mb-2">
        <button
          type="button"
          onClick={() => setSub('dashboard')}
          className="px-3 py-1 rounded-full text-xs font-semibold"
          style={{
            background: sub === 'dashboard' ? 'rgb(var(--persona-accent))' : 'rgba(255,255,255,0.55)',
            color: sub === 'dashboard' ? 'white' : 'rgb(var(--persona-text))',
            border: '1px solid rgb(var(--persona-primary) / 0.45)',
          }}
        >
          🏠 Dashboard
        </button>
        <button
          type="button"
          onClick={() => { setSelected(null); setDrillFilter(undefined); setSub('grid'); }}
          className="px-3 py-1 rounded-full text-xs font-semibold"
          style={{
            background: sub === 'grid' || sub === 'detail' ? 'rgb(var(--persona-accent))' : 'rgba(255,255,255,0.55)',
            color: sub === 'grid' || sub === 'detail' ? 'white' : 'rgb(var(--persona-text))',
            border: '1px solid rgb(var(--persona-primary) / 0.45)',
          }}
        >
          🗂 Grid
        </button>
        <div className="flex-1" />
        <button type="button" className="pretty-button" onClick={() => setShowImport(true)}>
          ✨ Import C4S CSV
        </button>
      </div>

      {sub === 'dashboard' && (
        <C4SDashboard
          active={active}
          onImport={() => setShowImport(true)}
          onOpenGrid={(filter) => {
            setDrillFilter(filter);
            setDrillNonce((n) => n + 1);
            setSub('grid');
          }}
          refreshToken={refreshToken}
        />
      )}

      {sub === 'grid' && (
        <C4SGrid
          active={active}
          onSelect={(c) => { setSelected(c); setSub('detail'); }}
          refreshToken={refreshToken}
          // Tag the drill filter with a nonce so the grid sees a fresh
          // object reference even when the same status/category is
          // clicked twice in a row.
          drillFilter={drillFilter && { ...drillFilter, __nonce: drillNonce } as DrillFilter}
        />
      )}

      {sub === 'detail' && selected && (
        <C4SDetail clip={selected} onBack={() => { setSelected(null); setSub('grid'); }} />
      )}

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
