// Phase 7 — Settings → Platforms editor.
//
// CRUD on posting_targets. The user maintains their own platform
// list independent of Molly (locked-in decision #12). Each row maps
// to a card in the Bundle workspace Post tab.
//
// Kind filter (content/custom/fansite/any) gates which bundles each
// platform shows up on. Persona filter (CoC/PoA/Sa or null) further
// scopes by which persona's bundles. Default kind 'any', default
// persona null = "show everywhere".

import { useEffect, useState } from 'react';
import {
  createPostingTarget, deletePostingTarget, listPostingTargets,
  seedFanSiteTargets, updatePostingTarget,
  type PostingTarget, type PostingTargetInput, type PostingKind,
} from '../../data/bundles';

const KINDS: PostingKind[] = ['any', 'content', 'custom', 'fansite', 'youtube'];
const PERSONAS: Array<{ code: string | null; label: string }> = [
  { code: null,  label: 'Any persona' },
  { code: 'CoC', label: 'CoC' },
  { code: 'PoA', label: 'PoA' },
  { code: 'Sa',  label: 'Sa'  },
];

export function PlatformsSettings() {
  const [targets, setTargets] = useState<PostingTarget[]>([]);
  const [status, setStatus] = useState<string>('');
  const [draft, setDraft] = useState<PostingTargetInput | null>(null);

  const refresh = async () => {
    try {
      setTargets(await listPostingTargets());
    } catch (e) { setStatus(`Load failed: ${e}`); }
  };
  useEffect(() => { refresh(); }, []);

  const startAdd = () => setDraft({
    name: '', urlTemplate: '', personaCode: null,
    color: '#888888', icon: '🎯', position: 100, kind: 'any', enabled: true,
  });

  const cancelDraft = () => setDraft(null);

  const seedFanSites = async () => {
    try {
      const targets = await seedFanSiteTargets();
      setTargets(targets);
      setStatus('✓ Fan-site roster ready (CoC + PoA)');
    } catch (e) { setStatus(`Seed failed: ${e}`); }
  };

  const saveDraft = async () => {
    if (!draft || !draft.name.trim()) {
      setStatus('Name required');
      return;
    }
    try {
      await createPostingTarget(draft);
      setStatus(`✓ Added ${draft.name}`);
      setDraft(null);
      await refresh();
    } catch (e) {
      setStatus(`Create failed: ${e}`);
    }
  };

  const updateRow = async (t: PostingTarget, patch: Partial<PostingTarget>) => {
    try {
      await updatePostingTarget(t.id, { ...t, ...patch });
      setTargets((arr) => arr.map((x) => x.id === t.id ? { ...x, ...patch } : x));
    } catch (e) { setStatus(`Update failed: ${e}`); }
  };

  const deleteRow = async (t: PostingTarget) => {
    if (!confirm(`Delete platform "${t.name}"? This also wipes its per-bundle posting history.`)) return;
    try {
      await deletePostingTarget(t.id);
      await refresh();
      setStatus(`✓ Deleted ${t.name}`);
    } catch (e) { setStatus(`Delete failed: ${e}`); }
  };

  return (
    <div className="flex flex-col gap-4">
      <div className="sm-card">
        <div className="font-semibold mb-1">Posting platforms</div>
        <div className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>
          Your own platform list — independent of Molly's. Each row
          becomes a card in <em>Bundle → Post</em>. <strong>Kind</strong>{' '}
          filters which bundles see this platform; set to <code>any</code>{' '}
          to show everywhere. <strong>URL template</strong> supports{' '}
          <code>{'{uid}'}</code> <code>{'{title}'}</code>{' '}
          <code>{'{persona}'}</code> <code>{'{date}'}</code> — the values
          get URL-encoded automatically.
        </div>
      </div>

      <div className="sm-card flex flex-col gap-2">
        <div className="flex items-center justify-between">
          <div className="text-sm font-semibold">{targets.length} platform{targets.length === 1 ? '' : 's'}</div>
          <div className="flex items-center gap-2">
            {status && <span className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>{status}</span>}
            <button type="button" className="sm-button secondary text-sm" onClick={seedFanSites}
                    title="Create OnlyFans/ManyVids/Niteflirt (CoC) + OnlyFans/Niteflirt/LoyalFans (PoA). Idempotent.">
              📅 Seed fan-sites
            </button>
            <button type="button" className="sm-button text-sm" onClick={startAdd}>
              ➕ Add platform
            </button>
          </div>
        </div>

        {targets.length === 0 && !draft && (
          <div className="text-xs italic" style={{ color: 'rgb(var(--surface-muted))' }}>
            No platforms yet. Click ➕ Add platform to get started.
          </div>
        )}

        <ul className="flex flex-col gap-1">
          {targets.map((t) => (
            <TargetRow
              key={t.id}
              target={t}
              onChange={(patch) => updateRow(t, patch)}
              onDelete={() => deleteRow(t)}
            />
          ))}
        </ul>

        {draft && (
          <div
            className="sm-card mt-2"
            style={{ borderColor: 'rgb(var(--surface-accent))', borderWidth: 2 }}
          >
            <div className="font-semibold mb-2 text-sm">New platform</div>
            <DraftEditor
              draft={draft}
              onChange={(patch) => setDraft({ ...draft, ...patch })}
            />
            <div className="flex justify-end items-center gap-2 mt-3">
              <button type="button" className="sm-button secondary text-xs" onClick={cancelDraft}>
                Cancel
              </button>
              <button type="button" className="sm-button text-xs" onClick={saveDraft}>
                💾 Save
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function TargetRow({ target, onChange, onDelete }: {
  target: PostingTarget;
  onChange: (patch: Partial<PostingTarget>) => void;
  onDelete: () => void;
}) {
  const [expanded, setExpanded] = useState(false);
  return (
    <li
      className="rounded"
      style={{
        borderLeft: `4px solid ${target.color}`,
        background: 'rgb(var(--surface-card))',
        padding: '6px 10px',
      }}
    >
      <div className="flex items-center gap-2">
        <span style={{ fontSize: 18 }}>{target.icon}</span>
        <span className="font-semibold flex-1 text-sm">{target.name}</span>
        <span
          className="text-[10px] px-1.5 py-0.5 rounded font-mono"
          style={{ background: 'rgb(var(--surface-base))', color: 'rgb(var(--surface-muted))' }}
        >
          {target.kind}{target.personaCode ? ` · ${target.personaCode}` : ''}
        </span>
        <label className="flex items-center gap-1 text-xs cursor-pointer">
          <input
            type="checkbox"
            checked={target.enabled}
            onChange={(e) => onChange({ enabled: e.target.checked })}
          />
          enabled
        </label>
        <button
          type="button"
          className="sm-button secondary text-xs"
          onClick={() => setExpanded((v) => !v)}
        >
          {expanded ? '▾ Hide' : '✎ Edit'}
        </button>
        <button
          type="button"
          className="sm-button secondary text-xs"
          style={{ color: '#7a0000' }}
          onClick={onDelete}
          title="Delete"
        >
          🗑
        </button>
      </div>
      {expanded && (
        <div className="mt-2">
          <DraftEditor
            draft={{
              name: target.name,
              urlTemplate: target.urlTemplate,
              personaCode: target.personaCode,
              color: target.color,
              icon: target.icon,
              position: target.position,
              kind: target.kind,
              enabled: target.enabled,
            }}
            onChange={(patch) => onChange(patch as Partial<PostingTarget>)}
          />
        </div>
      )}
    </li>
  );
}

function DraftEditor({ draft, onChange }: {
  draft: PostingTargetInput;
  onChange: (patch: Partial<PostingTargetInput>) => void;
}) {
  return (
    <div className="grid grid-cols-[120px_1fr] gap-x-3 gap-y-2 text-sm items-center">
      <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Name</label>
      <input
        type="text"
        className="sm-input"
        value={draft.name ?? ''}
        onChange={(e) => onChange({ name: e.target.value })}
        placeholder="C4S Store"
      />

      <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>URL template</label>
      <input
        type="text"
        className="sm-input font-mono text-xs"
        value={draft.urlTemplate ?? ''}
        onChange={(e) => onChange({ urlTemplate: e.target.value })}
        placeholder="https://example.com/upload?title={title}"
      />

      <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Icon</label>
      <input
        type="text"
        className="sm-input w-20"
        value={draft.icon ?? ''}
        onChange={(e) => onChange({ icon: e.target.value })}
        placeholder="🎯"
      />

      <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Color</label>
      <div className="flex items-center gap-2">
        <input
          type="color"
          className="rounded"
          style={{ width: 36, height: 28, padding: 0, border: '1px solid rgb(var(--surface-border))' }}
          value={draft.color ?? '#888888'}
          onChange={(e) => onChange({ color: e.target.value })}
        />
        <code className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>{draft.color}</code>
      </div>

      <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Kind</label>
      <select
        className="sm-input text-xs"
        style={{ width: 'auto' }}
        value={draft.kind ?? 'any'}
        onChange={(e) => onChange({ kind: e.target.value as PostingKind })}
      >
        {KINDS.map((k) => <option key={k} value={k}>{k}</option>)}
      </select>

      <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Persona</label>
      <select
        className="sm-input text-xs"
        style={{ width: 'auto' }}
        value={draft.personaCode ?? ''}
        onChange={(e) => onChange({ personaCode: e.target.value === '' ? null : e.target.value })}
      >
        {PERSONAS.map((p) => (
          <option key={p.code ?? '_any'} value={p.code ?? ''}>{p.label}</option>
        ))}
      </select>

      <label className="text-xs" style={{ color: 'rgb(var(--surface-muted))' }}>Position</label>
      <input
        type="number"
        className="sm-input w-20"
        value={draft.position ?? 100}
        onChange={(e) => onChange({ position: Number(e.target.value) })}
      />
    </div>
  );
}
