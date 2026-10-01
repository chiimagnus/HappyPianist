import { useFrame, useThree } from '@react-three/fiber';
import { useEffect, useRef } from 'react';
import { Color, Fog, GridHelper } from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import type { PrototypeEvent, PrototypeState } from '../model/state.ts';
import { BookFlow } from './BookFlow.tsx';
import { PianoScene } from './PianoScene.tsx';
import {
  CAMERA_TARGET,
  CAMERA_VIEWS,
  type CameraView,
} from './cameraViews.ts';

interface SpatialSceneProps {
  view: CameraView;
  state: PrototypeState;
  dispatch: (event: PrototypeEvent) => void;
  reducedMotion: boolean;
}

function CameraRig({ view }: { view: CameraView }) {
  const camera = useThree((state) => state.camera);
  const domElement = useThree((state) => state.gl.domElement);
  const controlsRef = useRef<OrbitControls | null>(null);

  useEffect(() => {
    const controls = new OrbitControls(camera, domElement);
    controls.enableDamping = true;
    controls.enablePan = false;
    controls.minDistance = 0.8;
    controls.maxDistance = 3.5;
    controls.minPolarAngle = 0.15;
    controls.maxPolarAngle = Math.PI * 0.65;
    controls.target.set(...CAMERA_TARGET);
    controlsRef.current = controls;

    return () => {
      controls.dispose();
      if (controlsRef.current === controls) controlsRef.current = null;
    };
  }, [camera, domElement]);

  useEffect(() => {
    camera.position.fromArray(CAMERA_VIEWS[view]);
    camera.lookAt(...CAMERA_TARGET);
    camera.updateProjectionMatrix();
    controlsRef.current?.target.set(...CAMERA_TARGET);
    controlsRef.current?.update();
  }, [camera, view]);

  useFrame(() => controlsRef.current?.update());

  return null;
}

function Environment() {
  const scene = useThree((state) => state.scene);
  const gridRef = useRef<GridHelper>(null);

  useEffect(() => {
    scene.background = new Color('#e9e5df');
    scene.fog = new Fog('#e9e5df', 4, 9);
    return () => {
      scene.background = null;
      scene.fog = null;
    };
  }, [scene]);

  useEffect(() => {
    if (!gridRef.current) return;
    const material = gridRef.current.material;
    if (Array.isArray(material)) return;
    material.transparent = true;
    material.opacity = 0.2;
  }, []);

  return (
    <>
      <hemisphereLight args={['#ffffff', '#ada994', 2.2]} />
      <directionalLight
        color="#fff5e2"
        intensity={3}
        position={[-2, 4, 3]}
        castShadow
        shadow-mapSize={[2048, 2048]}
        shadow-camera-left={-2}
        shadow-camera-right={2}
        shadow-camera-top={3}
        shadow-camera-bottom={-1}
        shadow-bias={-0.0002}
      />
      <mesh rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
        <planeGeometry args={[20, 20]} />
        <meshStandardMaterial color="#dedbd2" roughness={1} />
      </mesh>
      <gridHelper
        ref={gridRef}
        args={[8, 32, '#c4c8be', '#d2d5cb']}
        position={[0, 0.001, 0]}
      />
    </>
  );
}

export function SpatialScene({ view, state, dispatch, reducedMotion }: SpatialSceneProps) {
  return (
    <>
      <CameraRig view={view} />
      <Environment />
      <BookFlow state={state} dispatch={dispatch} reducedMotion={reducedMotion} />
      <PianoScene state={state} reducedMotion={reducedMotion} />
    </>
  );
}
