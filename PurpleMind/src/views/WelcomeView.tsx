interface WelcomeViewProps {
  hasMaps: boolean;
  onNewMap: () => void;
}

export function WelcomeView({ hasMaps, onNewMap }: WelcomeViewProps) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-5 px-8 text-center">
      <div className="text-6xl">🧠💜</div>
      <div>
        <h1 className="font-display text-3xl text-brand-600">Welcome to PurpleMind</h1>
        <p className="mt-2 max-w-md text-surface-muted">
          A soft little studio for your ideas. Drop thoughts on an infinite
          canvas, connect them into a map, tidy them with one click, and export
          to PNG, SVG, PDF, JSON, or a Markdown outline.
        </p>
      </div>
      <button type="button" className="btn-primary text-base" onClick={onNewMap}>
        ＋ {hasMaps ? 'Start a new map' : 'Create your first map'}
      </button>
      {hasMaps && (
        <p className="text-sm text-surface-muted">…or pick a map from the sidebar.</p>
      )}
    </div>
  );
}
