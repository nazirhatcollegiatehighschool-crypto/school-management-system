import { Component } from 'react';

export default class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, message: '' };
  }

  static getDerivedStateFromError(err) {
    return { hasError: true, message: err?.message || String(err) };
  }

  componentDidCatch(err, info) {
    console.error('Page crashed:', err, info);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div style={{
          padding: 24,
          fontFamily: 'system-ui',
          textAlign: 'center'
        }}>
          <h2 style={{ color: '#b71c1c' }}>Something went wrong</h2>
          <p>The page crashed while rendering. Your data is safe.</p>
          {this.state.message && (
            <pre style={{
              background: '#f5f5f5', border: '1px solid #ddd', borderRadius: 6,
              padding: 12, textAlign: 'left', fontSize: 12, whiteSpace: 'pre-wrap', maxWidth: 640, margin: '0 auto'
            }}>{this.state.message}</pre>
          )}
          <div style={{ marginTop: 16 }}>
            <button className="btn" onClick={() => this.setState({ hasError: false, message: '' })}>
              Try Again
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}