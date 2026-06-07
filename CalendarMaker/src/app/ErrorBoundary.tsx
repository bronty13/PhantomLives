import { Component, type ErrorInfo, type ReactNode } from 'react';

interface State {
  error: Error | null;
}

/** Catches render errors so the app shows a message instead of a blank screen. */
export class ErrorBoundary extends Component<{ children: ReactNode }, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('CalendarMaker crashed:', error, info);
  }

  render() {
    if (this.state.error) {
      return (
        <div style={{ maxWidth: 560, margin: '80px auto', padding: 24, fontFamily: 'system-ui, sans-serif' }}>
          <h1 style={{ marginTop: 0 }}>Something went wrong</h1>
          <p>CalendarMaker hit an unexpected error. Try reloading the page.</p>
          <pre style={{ whiteSpace: 'pre-wrap', background: '#faf0f2', border: '1px solid #f0c9d1', padding: 12, borderRadius: 8, fontSize: 12 }}>
            {String(this.state.error?.message || this.state.error)}
          </pre>
          <button onClick={() => location.reload()} style={{ padding: '8px 14px' }}>Reload</button>
        </div>
      );
    }
    return this.props.children;
  }
}
