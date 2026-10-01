import { Canvas } from '@react-three/fiber';
import { useRef, useState } from 'react';
import { SceneReviewProbe, usePrototypeReview, type SceneReviewReader } from './dev/review.tsx';
import { usePrototypeRuntime } from './runtime/usePrototypeRuntime.ts';
import { ProductControls } from './ui/ProductControls.tsx';
import { createRenderer } from './scene/createRenderer.ts';
import { SpatialScene } from './scene/SpatialScene.tsx';
import type { CameraView } from './scene/cameraViews.ts';
import { productPlacement } from './scene/productPlacement.ts';

export function App() {
  const runtime = usePrototypeRuntime();
  const placement = productPlacement(runtime.state);
  const [view, setView] = useState<CameraView>('front');
  const sceneReaderRef = useRef<SceneReviewReader | null>(null);
  usePrototypeReview({
    state: runtime.state,
    replaceState: runtime.replaceState,
    view,
    setView,
    sceneReaderRef,
  });

  return (
    <main className="app-shell" data-stage={runtime.state.stage} data-reduced-motion={runtime.reducedMotion || undefined}>
      <header className="prototype-label">
        <strong>HappyPianist</strong>
        <span>Spatial Prototype</span>
      </header>
      {placement === 'screen' && <ProductControls state={runtime.state} dispatch={runtime.dispatch} />}
      <Canvas
        className="scene-canvas"
        camera={{ position: [0, 1.46, 1.75], fov: 43, near: 0.02, far: 12 }}
        dpr={[1, 2]}
        shadows
        gl={createRenderer}
      >
        <SpatialScene view={view} state={runtime.state} dispatch={runtime.dispatch} reducedMotion={runtime.reducedMotion} productPlacement={placement} />
        {import.meta.env.DEV && <SceneReviewProbe state={runtime.state} readerRef={sceneReaderRef} />}
      </Canvas>
      <footer className="prototype-footer">曲谱、设备、演奏、手部、保存均为模拟 · 不读写 App 数据</footer>
    </main>
  );
}
