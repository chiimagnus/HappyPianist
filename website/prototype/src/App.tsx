import { Canvas } from '@react-three/fiber';
import { usePrototypeRuntime } from './runtime/usePrototypeRuntime.ts';
import { ProductControls } from './ui/ProductControls.tsx';
import { createRenderer } from './scene/createRenderer.ts';
import { SpatialScene } from './scene/SpatialScene.tsx';

export function App() {
  const runtime = usePrototypeRuntime();

  return (
    <main className="app-shell" data-stage={runtime.state.stage} data-reduced-motion={runtime.reducedMotion || undefined}>
      <header className="prototype-label">
        <strong>HappyPianist</strong>
        <span>Spatial Prototype</span>
      </header>
      <ProductControls state={runtime.state} dispatch={runtime.dispatch} />
      <Canvas
        className="scene-canvas"
        camera={{ position: [0, 1.46, 1.75], fov: 43, near: 0.02, far: 12 }}
        dpr={[1, 2]}
        shadows
        gl={createRenderer}
      >
        <SpatialScene view="front" state={runtime.state} dispatch={runtime.dispatch} reducedMotion={runtime.reducedMotion} />
      </Canvas>
      <footer className="prototype-footer">曲谱、设备、演奏、手部、保存均为模拟 · 不读写 App 数据</footer>
    </main>
  );
}
