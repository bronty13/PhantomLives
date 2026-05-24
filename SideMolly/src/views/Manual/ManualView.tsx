// Phase 0 placeholder. Later phases will render USER_MANUAL.md via a
// ported markdownLite parser (same one Molly uses) with a right-rail TOC.
export function ManualView() {
  return (
    <div className="p-8 max-w-3xl">
      <h1 className="display-font text-4xl mb-2" style={{ color: 'rgb(var(--surface-accent))' }}>
        Manual
      </h1>
      <div className="sm-card mt-6">
        <p className="text-sm">
          The in-app manual is not wired yet. See <code>SideMolly/USER_MANUAL.md</code> in
          the repo for now. Phase 1 will start populating it.
        </p>
      </div>
    </div>
  );
}
