import { Canvas } from '@react-three/fiber';

export function App() {
  return (
    <main style={{ width: '100vw', height: '100vh' }}>
      <Canvas camera={{ position: [0, 0.4, 2.4], fov: 45 }}>
        <color attach="background" args={['#e9e5df']} />
        <ambientLight intensity={1.2} />
        <directionalLight position={[2, 3, 2]} intensity={2} />
        <mesh rotation={[0.2, 0.35, 0]}>
          <boxGeometry args={[0.7, 0.9, 0.08]} />
          <meshStandardMaterial color="#d7cfbc" roughness={0.85} />
        </mesh>
      </Canvas>
    </main>
  );
}
