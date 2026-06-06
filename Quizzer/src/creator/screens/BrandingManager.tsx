import { useState } from 'react';
import type { Branding, BuiltinFontName, FontChoice } from '../../shared/model';
import { BUILTIN_FONT_NAMES } from '../../shared/model';
import { resolveAsset } from '../../shared/assets';
import { resolveFont } from '../../shared/fonts';
import { makeBranding } from '../../shared/factory';
import { deleteBranding, saveBranding } from '../storage/db';
import { fileToAssetRef } from '../components/uploadAsset';
import { ColorField } from '../components/ColorField';

export function BrandingManager({
  brandings,
  onChange,
}: {
  brandings: Branding[];
  onChange: () => void;
}) {
  const [editing, setEditing] = useState<Branding | null>(null);

  async function save() {
    if (!editing) return;
    await saveBranding(editing);
    setEditing(null);
    onChange();
  }

  async function remove(id: string) {
    if (!confirm('Delete this branding profile?')) return;
    await deleteBranding(id);
    if (editing?.id === id) setEditing(null);
    onChange();
  }

  if (editing) {
    return <BrandingEditor branding={editing} setBranding={setEditing} onSave={save} onCancel={() => setEditing(null)} />;
  }

  return (
    <div className="screen">
      <div className="screen-head">
        <h1>Branding</h1>
        <button className="btn" onClick={() => setEditing(makeBranding(`Brand ${brandings.length + 1}`))}>
          + New Branding
        </button>
      </div>
      <p className="meta">Reusable colors, logo, and font applied to a quiz and every page of the deployed quiz.</p>

      {brandings.length === 0 && <p className="empty">No branding profiles yet.</p>}
      <div className="card-list">
        {brandings.map((b) => (
          <div key={b.id} className="list-card" style={resolveFont(b.font).fontFamily ? { fontFamily: resolveFont(b.font).fontFamily } : undefined}>
            <div className="brand-preview">
              {resolveAsset(b.logo) && <img src={resolveAsset(b.logo)} alt="" />}
              <div className="swatches">
                {[b.colors.primary, b.colors.secondary, b.colors.accent].map((c, i) => (
                  <span key={i} className="dot" style={{ background: c }} />
                ))}
              </div>
            </div>
            <div className="grow">
              <strong>{b.name}</strong>
              <div className="meta">{b.font.kind === 'builtin' ? b.font.family : `Custom: ${b.font.family}`}</div>
            </div>
            <div className="row-actions">
              <button className="btn small" onClick={() => setEditing(b)}>Edit</button>
              <button className="btn small danger" onClick={() => remove(b.id)}>Delete</button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function BrandingEditor({
  branding,
  setBranding,
  onSave,
  onCancel,
}: {
  branding: Branding;
  setBranding: (b: Branding) => void;
  onSave: () => void;
  onCancel: () => void;
}) {
  const b = branding;
  const setColor = (k: keyof Branding['colors']) => (hex: string) =>
    setBranding({ ...b, colors: { ...b.colors, [k]: hex } });

  async function uploadLogo(file: File | undefined) {
    if (!file) return;
    setBranding({ ...b, logo: await fileToAssetRef(file) });
  }

  async function uploadFont(file: File | undefined) {
    if (!file) return;
    const ttf = await fileToAssetRef(file);
    const family = file.name.replace(/\.(ttf|otf|woff2?|sfnt)$/i, '');
    setBranding({ ...b, font: { kind: 'custom', family, ttf } });
  }

  function setFont(choice: FontChoice) {
    setBranding({ ...b, font: choice });
  }

  const resolved = resolveFont(b.font);

  return (
    <div className="screen">
      {resolved.faceCss && <style dangerouslySetInnerHTML={{ __html: resolved.faceCss }} />}
      <div className="screen-head">
        <h1>Edit Branding</h1>
        <div className="btn-row">
          <button className="btn secondary" onClick={onCancel}>Cancel</button>
          <button className="btn" onClick={onSave}>Save</button>
        </div>
      </div>

      <label className="field full">
        <span className="field-label">Profile name</span>
        <input value={b.name} onChange={(e) => setBranding({ ...b, name: e.target.value })} />
      </label>

      <div className="form-grid">
        <ColorField label="Primary" value={b.colors.primary} onChange={setColor('primary')} />
        <ColorField label="Secondary" value={b.colors.secondary} onChange={setColor('secondary')} />
        <ColorField label="Accent" value={b.colors.accent} onChange={setColor('accent')} />
        <ColorField label="Background" value={b.colors.bg} onChange={setColor('bg')} />
        <ColorField label="Text" value={b.colors.text} onChange={setColor('text')} />
      </div>

      <div className="field full">
        <span className="field-label">Logo</span>
        <div className="upload-row">
          {resolveAsset(b.logo) && <img className="logo-thumb" src={resolveAsset(b.logo)} alt="" />}
          <input type="file" accept="image/*" onChange={(e) => uploadLogo(e.target.files?.[0])} />
          {b.logo && <button className="btn small secondary" onClick={() => setBranding({ ...b, logo: undefined })}>Remove</button>}
        </div>
      </div>

      <div className="field full">
        <span className="field-label">Font</span>
        <div className="upload-row">
          <select
            value={b.font.kind === 'builtin' ? b.font.family : '__custom__'}
            onChange={(e) => {
              if (e.target.value !== '__custom__') setFont({ kind: 'builtin', family: e.target.value as BuiltinFontName });
            }}
          >
            {BUILTIN_FONT_NAMES.map((f) => <option key={f} value={f}>{f}</option>)}
            {b.font.kind === 'custom' && <option value="__custom__">Custom: {b.font.family}</option>}
          </select>
          <label className="btn small secondary file-btn">
            Upload TTF…
            <input type="file" accept=".ttf,.otf,font/ttf,font/otf" hidden onChange={(e) => uploadFont(e.target.files?.[0])} />
          </label>
        </div>
        <div className="font-sample" style={{ fontFamily: resolved.fontFamily }}>
          The quick brown fox — 0123456789
        </div>
      </div>

      <div className="preview-panel" style={{ background: b.colors.bg, color: b.colors.text, fontFamily: resolved.fontFamily }}>
        <div style={{ color: b.colors.primary, fontWeight: 700, fontSize: '1.2rem' }}>{b.name} preview</div>
        <p>Sample quiz text on the branded background.</p>
        <button style={{ background: b.colors.primary, color: '#fff', border: 'none', padding: '8px 16px', borderRadius: 8 }}>Primary</button>
        {' '}
        <button style={{ background: b.colors.accent, color: '#fff', border: 'none', padding: '8px 16px', borderRadius: 8 }}>Accent</button>
      </div>
    </div>
  );
}
