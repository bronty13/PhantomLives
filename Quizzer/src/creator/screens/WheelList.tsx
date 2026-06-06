import { useRef, useState } from 'react';
import type { Branding, Wheel } from '../../shared/model';
import { newId } from '../../shared/factory';
import { deleteWheel, getBranding, saveWheel } from '../storage/db';
import { exportWheelBundleJson } from '../storage/wheelBundle';
import { downloadText } from '../deploy/download';
import { slugify } from '../../shared/util';
import { WheelDeployDialog } from './WheelDeployDialog';

export function WheelList({
  wheels,
  brandings,
  onOpen,
  onNew,
  onImport,
  reload,
}: {
  wheels: Wheel[];
  brandings: Branding[];
  onOpen: (w: Wheel) => void;
  onNew: () => void;
  onImport: (file: File) => void;
  reload: () => void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [deploy, setDeploy] = useState<{ wheel: Wheel; branding: Branding } | null>(null);

  async function duplicate(w: Wheel) {
    const copy: Wheel = { ...w, id: newId(), name: `${w.name} (copy)`, createdAt: Date.now(), updatedAt: Date.now() };
    await saveWheel(copy);
    reload();
  }

  async function remove(w: Wheel) {
    if (!confirm(`Delete "${w.name}"? This cannot be undone.`)) return;
    await deleteWheel(w.id);
    reload();
  }

  async function exportBundle(w: Wheel) {
    const branding = (await getBranding(w.brandingId)) ?? brandings[0];
    if (!branding) return;
    downloadText(`${slugify(w.name)}.wheelzer.json`, exportWheelBundleJson(w, branding), 'application/json');
  }

  async function openDeploy(w: Wheel) {
    const branding = (await getBranding(w.brandingId)) ?? brandings[0];
    if (!branding) {
      alert('Create a branding profile first.');
      return;
    }
    setDeploy({ wheel: w, branding });
  }

  return (
    <div className="screen">
      <div className="screen-head">
        <h1 className="grow">My Wheels</h1>
        <button className="btn secondary" onClick={() => fileRef.current?.click()}>Import…</button>
        <button className="btn" onClick={onNew}>+ New Spin the Wheel</button>
        <input ref={fileRef} type="file" accept=".json,application/json" hidden
          onChange={(e) => { const f = e.target.files?.[0]; if (f) onImport(f); e.target.value = ''; }} />
      </div>

      {wheels.length === 0 && (
        <p className="empty">No wheels yet. Click <strong>New Spin the Wheel</strong> to build your first one.</p>
      )}

      <div className="card-list">
        {wheels.map((w) => (
          <div key={w.id} className="list-card">
            <div className="grow">
              <strong>{w.name}</strong>
              <div className="meta">
                {w.choices.length} choice{w.choices.length === 1 ? '' : 's'} · {w.spinsPermitted === 0 ? 'unlimited spins' : `${w.spinsPermitted} spin${w.spinsPermitted === 1 ? '' : 's'}`}
              </div>
            </div>
            <div className="row-actions">
              <button className="btn small" onClick={() => onOpen(w)}>Edit</button>
              <button className="btn small accent" onClick={() => openDeploy(w)}>Deploy</button>
              <button className="btn small secondary" onClick={() => duplicate(w)}>Duplicate</button>
              <button className="btn small secondary" onClick={() => exportBundle(w)}>Export</button>
              <button className="btn small danger" onClick={() => remove(w)}>Delete</button>
            </div>
          </div>
        ))}
      </div>

      {deploy && (
        <WheelDeployDialog wheel={deploy.wheel} branding={deploy.branding} onClose={() => setDeploy(null)} />
      )}
    </div>
  );
}
