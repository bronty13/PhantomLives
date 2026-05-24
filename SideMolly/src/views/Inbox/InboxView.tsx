// Phase 0 placeholder. Phase 1 will populate this with ingested bundles
// (watched folder + drag-drop), hash verification status, and a click-
// through to the per-bundle workspace.
export function InboxView() {
  return (
    <div className="p-8 max-w-3xl">
      <h1 className="display-font text-4xl mb-2" style={{ color: 'rgb(var(--surface-accent))' }}>
        Inbox
      </h1>
      <p className="text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
        Drop a Molly bundle ZIP here, or wait for the watched folder to pick one up.
      </p>

      <div className="sm-card mt-6">
        <div className="text-sm" style={{ color: 'rgb(var(--surface-muted))' }}>
          <strong>Phase 0:</strong> empty app shell. Bundle ingest lands in Phase 1
          (see <code>SideMolly/PLAN.md</code> §11).
        </div>
      </div>
    </div>
  );
}
