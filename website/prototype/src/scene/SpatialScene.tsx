import { Canvas, useFrame, useThree } from '@react-three/fiber';
import {
  forwardRef,
  useEffect,
  useImperativeHandle,
  useRef,
  type RefObject,
} from 'react';
import {
  ACESFilmicToneMapping,
  PCFShadowMap,
  REVISION,
  SRGBColorSpace,
  type Camera,
  Vector3,
} from 'three';
import { WebGPURenderer } from 'three/webgpu';
import { output, rangeFogFactor, vec4 } from 'three/tsl';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import type { ReviewView } from '../reviewFixtures.ts';
import type { PrototypeEvent, PrototypeState } from '../model.ts';
import { BookFlow } from './BookFlow.tsx';
import { SpatialOperations } from './SpatialOperations.tsx';
import type { BookHandle } from './ScoreBook.tsx';
import { width } from './bookTextures.ts';
import { PianoScene, type PianoSceneHandle } from './PianoScene.tsx';

const viewPositions: Readonly<Record<ReviewView, readonly [number, number, number]>> = {
  front: [0, 1.46, 1.75],
  oblique: [0.85, 1.58, 1.45],
  side: [1.55, 1.47, 0.56],
  top: [0.06, 2.45, 0.95],
};

export interface SpatialSceneHandle {
  snapshot: () => Record<string, unknown>;
  setView: (view: ReviewView) => void;
}

interface SpatialSceneProps {
  view: ReviewView;
  state: PrototypeState;
  dispatch: (event: PrototypeEvent) => void;
  operationsElement: HTMLDivElement;
}

function applyView(camera: Camera, controls: OrbitControls | null, view: ReviewView) {
  if (controls) {
    controls.enableDamping = false;
    controls.update();
    controls.enableDamping = true;
  }
  camera.position.set(...viewPositions[view]);
  controls?.target.set(0, 1.25, 0);
  controls?.update();
}

function OrbitRig({ view, controlsRef }: Pick<SpatialSceneProps, 'view'> & {
  controlsRef: RefObject<OrbitControls | null>;
}) {
  const { camera, gl } = useThree();

  useEffect(() => {
    const controls = new OrbitControls(camera, gl.domElement);
    controls.enableDamping = true;
    controls.enablePan = false;
    controls.minDistance = 0.8;
    controls.maxDistance = 3.5;
    controls.minPolarAngle = 0.15;
    controls.maxPolarAngle = Math.PI * 0.65;
    controls.target.set(0, 1.25, 0);
    controlsRef.current = controls;

    return () => {
      controls.dispose();
      controlsRef.current = null;
    };
  }, [camera, gl, controlsRef]);

  useEffect(() => {
    applyView(camera, controlsRef.current, view);
  }, [camera, view, controlsRef]);

  useFrame(() => {
    controlsRef.current?.update();
  });

  return null;
}

export const SpatialScene = forwardRef<SpatialSceneHandle, SpatialSceneProps>(
  function SpatialScene({ view, state, dispatch, operationsElement }, ref) {
    const cameraRef = useRef<Camera | null>(null);
    const rendererRef = useRef<WebGPURenderer | null>(null);
    const booksRef = useRef(new Map<number, BookHandle>());
    const pianoRef = useRef<PianoSceneHandle>(null);
    const controlsRef = useRef<OrbitControls | null>(null);

    useImperativeHandle(ref, () => ({
      setView: (requestedView) => {
        if (cameraRef.current) applyView(cameraRef.current, controlsRef.current, requestedView);
      },
      snapshot: () => {
        const camera = cameraRef.current;
        const renderer = rendererRef.current;
        const book = booksRef.current.get(state.selected);
        const center = book && camera
          ? book.root.localToWorld(new Vector3(width / 2, 0, 0.02)).project(camera) : null;
        const operations = book?.root.children.find((child) => child.userData.operations);
        return {
          ...pianoRef.current?.snapshot(),
          threeRevision: REVISION,
          cameraPosition: camera?.position.toArray() ?? [],
          rendererCalls: renderer?.info.render.calls ?? 0,
          rendererPixelRatio: renderer?.getPixelRatio() ?? 0,
          rendererShadowType: renderer?.shadowMap.type ?? null,
          rendererOutputColorSpace: renderer?.outputColorSpace ?? '',
          rendererToneMapping: renderer?.toneMapping ?? null,
          rendererToneMappingExposure: renderer?.toneMappingExposure ?? 0,
          rendererBackend: renderer?.backend.constructor.name,
          reviewView: view,
          visibleBooks: [...booksRef.current.values()].filter((item) => item.root.visible).length,
          selectedBookUUID: book?.root.uuid,
          bookPosition: book?.root.position.toArray(),
          openAngle: book?.hinge.rotation.y,
          flipping: book?.root.getObjectByName('page-turn')?.visible ?? false,
          selectedBookScreen: center ? [(center.x + 1) * innerWidth / 2, (1 - center.y) * innerHeight / 2] : [],
          controlsWorldMatrix: operations?.matrixWorld.toArray(),
          controlsCSSTransform: operationsElement.style.transform,
        };
      },
    }), [view, state.selected, operationsElement]);

    return (
      <Canvas
        dpr={[1, 2]}
        shadows={{ type: PCFShadowMap }}
        camera={{
          fov: 43,
          near: 0.02,
          far: 12,
          position: viewPositions.front,
        }}
        gl={async (defaults) => {
          const renderer = new WebGPURenderer({
            canvas: defaults.canvas as HTMLCanvasElement,
            antialias: true,
            alpha: true,
            powerPreference: 'high-performance',
          });
          await renderer.init();
          return renderer;
        }}
        onCreated={({ camera, gl, scene }) => {
          cameraRef.current = camera;
          rendererRef.current = gl as unknown as WebGPURenderer;
          gl.shadowMap.enabled = true;
          gl.shadowMap.type = PCFShadowMap;
          gl.outputColorSpace = SRGBColorSpace;
          gl.toneMapping = ACESFilmicToneMapping;
          gl.toneMappingExposure = 1.12;
          scene.fogNode = vec4(output.rgb, output.a.mul(rangeFogFactor(4, 9).oneMinus()));
        }}
      >
        <hemisphereLight args={['#ffffff', '#ada994', 2.2]} />
        <directionalLight
          color="#fff5e2"
          intensity={3}
          position={[-2, 4, 3]}
          castShadow
          shadow-mapSize-width={2048}
          shadow-mapSize-height={2048}
          shadow-camera-left={-2}
          shadow-camera-right={2}
          shadow-camera-top={3}
          shadow-camera-bottom={-1}
          shadow-bias={-0.0002}
        />
        <mesh rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
          <planeGeometry args={[20, 20]} />
          <meshStandardMaterial color="#dedbd2" roughness={1} transparent />
        </mesh>
        <gridHelper
          args={[8, 32, '#c4c8be', '#d2d5cb']}
          position={[0, 0.001, 0]}
          material-transparent
          material-opacity={0.2}
        />
        <OrbitRig view={view} controlsRef={controlsRef} />
        <BookFlow state={state} dispatch={dispatch} books={booksRef.current} />
        <PianoScene ref={pianoRef} state={state} />
        <SpatialOperations state={state} element={operationsElement} books={booksRef.current} />
      </Canvas>
    );
  },
);
