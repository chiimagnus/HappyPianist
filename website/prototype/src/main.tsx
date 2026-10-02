import { Component, StrictMode, type ReactNode } from 'react';
import { createRoot } from 'react-dom/client';
import '../style.css';
import { App } from './App';

class PrototypeErrorBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() { return { failed: true }; }
  render() {
    return this.state.failed
      ? <div id="load-error" className="load-error" role="alert">原型未能运行。请确认浏览器支持 GPU 渲染，再重新加载；本原型未操作正式 App 数据。</div>
      : this.props.children;
  }
}

const rootElement = document.querySelector<HTMLDivElement>('#app');

if (rootElement === null) {
  throw new Error('Missing #app root element');
}

createRoot(rootElement).render(
  <StrictMode>
    <PrototypeErrorBoundary><App /></PrototypeErrorBoundary>
  </StrictMode>,
);
