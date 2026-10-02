import type { ReactNode } from 'react';
import type { PrototypeState } from '../model.ts';

interface AppShellProps {
  state: PrototypeState;
  viewport: ReactNode;
  product: ReactNode;
  review: ReactNode;
}

function sceneCaption(state: PrototypeState): string {
  if (state.stage === 'library') return '独立薄书册 · 真实深度 · 世界固定示意';
  if (state.session) return '同一本谱 · 琴上阅读\n灰色琴为现实乐器占位；手部与反馈为模拟';
  if (
    state.stage === 'detail'
    || state.stage === 'input'
    || state.stage === 'ready'
    || state.stage === 'a0'
    || state.stage === 'c8'
  ) {
    return '同一书册展开 · 双页与轻书脊';
  }
  return '';
}

export function AppShell({ state, viewport, product, review }: AppShellProps) {
  return (
    <>
      <div id="viewport">{viewport}</div>
      <header>
        <div>
          <span className="eyebrow">HAPPY PIANIST / SPATIAL STUDY</span>
          <h1>空间里的同一本书</h1>
        </div>
        <span className="badge">交互设计原型 · 非正式 App</span>
      </header>
      <nav id="views">
        <button type="button" data-view="front" className="selected">正视</button>
        <button type="button" data-view="oblique">斜视</button>
        <button type="button" data-view="side">侧视</button>
        <button type="button" data-view="top">俯视</button>
      </nav>
      <div id="scene-caption">{sceneCaption(state)}</div>
      {product}
      <footer>
        <span id="simulation">曲谱、设备、演奏、手部、保存均为模拟 · 不读写 App 数据</span>
        <span className="hint">拖动空白处观察空间 · 滚轮缩放</span>
      </footer>
      {review}
      <div id="load-error" hidden />
    </>
  );
}
