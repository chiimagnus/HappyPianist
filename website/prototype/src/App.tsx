import { Canvas } from '@react-three/fiber';
import { WebGPURenderer } from 'three/webgpu';

function PrototypeScene() {
  return (
    <mesh rotation={[0.25, 0.45, 0]}>
      <boxGeometry args={[0.8, 0.8, 0.8]} />
      <meshBasicMaterial color="#d9dde8" />
    </mesh>
  );
}

export function App() {
  return (
    <main className="app-shell">
      <header className="prototype-label">
        <strong>HappyPianist</strong>
        <span>Spatial Prototype</span>
      </header>
      <Canvas
        camera={{ position: [0, 0, 3], fov: 43, near: 0.02, far: 12 }}
        gl={async (props) => {
          const renderer = new WebGPURenderer({
            canvas: props.canvas as HTMLCanvasElement,
            antialias: true,
          });
          await renderer.init();
          return renderer;
        }}
      >
        <PrototypeScene />
      </Canvas>
    </main>
  );
}
