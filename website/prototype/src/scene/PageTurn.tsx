import { useFrame } from '@react-three/fiber';
import {
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import {
  Group,
  MathUtils,
  Mesh,
  type BufferAttribute,
  type CanvasTexture,
} from 'three';
import { pageCount, type PrototypeSong } from '../model/data.ts';
import type { PrototypeEvent, PrototypeState } from '../model/state.ts';
import { BOOK_HEIGHT, BOOK_HINGE_Z, BOOK_WIDTH } from './bookPose.ts';
import { createPageTexture } from './bookTextures.ts';
import { pageTurnPages } from './pageTurn.ts';

interface PageTurnProps {
  song: PrototypeSong;
  state: PrototypeState;
  dispatch: (event: PrototypeEvent) => void;
  open: boolean;
  reducedMotion: boolean;
}

interface FlipDescriptor {
  from: number;
  to: number;
}

function usePageTexture(song: PrototypeSong, page: number, state: PrototypeState): CanvasTexture {
  const texture = useMemo(
    () => createPageTexture({
      song,
      page,
      pageCount,
      measure: state.measure,
      stage: state.stage,
      session: state.session,
      feedback: state.feedback,
    }),
    [page, song, state.feedback, state.measure, state.session, state.stage],
  );

  useEffect(() => () => texture.dispose(), [texture]);
  return texture;
}

function useOptionalPageTexture(song: PrototypeSong, page: number | null, state: PrototypeState): CanvasTexture | null {
  const texture = useMemo(
    () => page === null
      ? null
      : createPageTexture({
          song,
          page,
          pageCount,
          measure: state.measure,
          stage: state.stage,
          session: state.session,
          feedback: state.feedback,
        }),
    [page, song, state.feedback, state.measure, state.session, state.stage],
  );

  useEffect(() => () => texture?.dispose(), [texture]);
  return texture;
}

function bendLeaf(mesh: Mesh | null, eased: number, sign: number): void {
  if (!mesh) return;
  const positions = mesh.geometry.getAttribute('position') as BufferAttribute;
  for (let vertex = 0; vertex < positions.count; vertex += 1) {
    const ratio = (positions.getX(vertex) + BOOK_WIDTH / 2) / BOOK_WIDTH;
    positions.setZ(vertex, Math.sin(ratio * Math.PI) * Math.sin(eased * Math.PI) * 0.025 * sign);
  }
  positions.needsUpdate = true;
  mesh.geometry.computeVertexNormals();
}

function resetLeaf(mesh: Mesh | null): void {
  if (!mesh) return;
  const positions = mesh.geometry.getAttribute('position') as BufferAttribute;
  for (let vertex = 0; vertex < positions.count; vertex += 1) positions.setZ(vertex, 0);
  positions.needsUpdate = true;
  mesh.geometry.computeVertexNormals();
}

export function PageTurn({ song, state, dispatch, open, reducedMotion }: PageTurnProps) {
  const leftGroupRef = useRef<Group>(null);
  const leafRef = useRef<Group>(null);
  const leafFrontRef = useRef<Mesh>(null);
  const leafBackRef = useRef<Mesh>(null);
  const previousTargetRef = useRef(state.spread);
  const progressRef = useRef(0);
  const [flip, setFlip] = useState<FlipDescriptor | null>(null);

  useLayoutEffect(() => {
    if (reducedMotion) {
      previousTargetRef.current = state.spread;
      setFlip(null);
      return;
    }

    if (state.spread === previousTargetRef.current) return;
    const from = previousTargetRef.current;
    previousTargetRef.current = state.spread;
    setFlip({ from, to: state.spread });
  }, [reducedMotion, state.spread]);

  useEffect(() => {
    progressRef.current = 0;
    if (!leafRef.current) return;
    leafRef.current.visible = Boolean(flip) && !reducedMotion;
    if (flip) {
      const pages = pageTurnPages(flip.from, flip.to);
      leafRef.current.rotation.y = pages.direction === 1 ? 0 : -Math.PI;
    }
  }, [flip, reducedMotion]);

  const steadyLeft = state.spread * 2 + 1;
  const steadyRight = state.spread * 2 + 2;
  const pages = flip ? pageTurnPages(flip.from, flip.to) : null;
  const leftPage = pages?.left ?? steadyLeft;
  const rightPage = pages?.right ?? steadyRight;

  const leftTexture = usePageTexture(song, leftPage, state);
  const rightTexture = usePageTexture(song, rightPage, state);
  const leafFrontTexture = useOptionalPageTexture(song, pages?.leafFront ?? null, state);
  const leafBackTexture = useOptionalPageTexture(song, pages?.leafBack ?? null, state);

  useFrame((_, delta) => {
    const leftGroup = leftGroupRef.current;
    if (leftGroup) {
      const amount = reducedMotion ? 1 : 1 - Math.exp(-Math.min(delta, 0.05) * 9);
      leftGroup.rotation.y = MathUtils.lerp(leftGroup.rotation.y, open ? -Math.PI : 0, amount);
    }

    const leaf = leafRef.current;
    if (!flip || reducedMotion || !leaf) {
      if (leaf) leaf.visible = false;
      return;
    }

    progressRef.current = Math.min(1, progressRef.current + delta / 0.8);
    const progress = progressRef.current;
    const eased = progress * progress * (3 - 2 * progress);
    const direction = pageTurnPages(flip.from, flip.to).direction;
    leaf.visible = true;
    leaf.rotation.y = -Math.PI * (direction === 1 ? eased : 1 - eased);
    bendLeaf(leafFrontRef.current, eased, 1);
    bendLeaf(leafBackRef.current, eased, -1);

    if (progress >= 1) {
      leaf.visible = false;
      resetLeaf(leafFrontRef.current);
      resetLeaf(leafBackRef.current);
      setFlip((current) => current === flip ? null : current);
    }
  });

  const lastSpread = Math.ceil(pageCount / 2) - 1;
  const turn = (amount: -1 | 1) => (event: { stopPropagation(): void }) => {
    event.stopPropagation();
    if (state.stage !== 'detail') return;
    if (amount < 0 && state.spread === 0) return;
    if (amount > 0 && state.spread === lastSpread) return;
    dispatch({ type: 'page', value: amount });
  };

  return (
    <group name="page-turn">
      <group ref={leftGroupRef} position={[0, 0, BOOK_HINGE_Z]}>
        <mesh position={[BOOK_WIDTH / 2, 0, -0.0012]} rotation={[0, Math.PI, 0]} receiveShadow>
          <planeGeometry args={[BOOK_WIDTH, BOOK_HEIGHT]} />
          <meshStandardMaterial map={leftTexture} roughness={1} />
        </mesh>
      </group>

      <mesh position={[BOOK_WIDTH / 2, 0, 0.006]} receiveShadow>
        <planeGeometry args={[BOOK_WIDTH, BOOK_HEIGHT]} />
        <meshStandardMaterial map={rightTexture} roughness={1} />
      </mesh>

      <group ref={leafRef} position={[0, 0, 0.023]} visible={false}>
        <mesh ref={leafFrontRef} position={[BOOK_WIDTH / 2, 0, 0.0005]} receiveShadow>
          <planeGeometry args={[BOOK_WIDTH, BOOK_HEIGHT, 24, 1]} />
          <meshStandardMaterial map={leafFrontTexture ?? rightTexture} roughness={1} />
        </mesh>
        <mesh ref={leafBackRef} position={[BOOK_WIDTH / 2, 0, -0.0005]} rotation={[0, Math.PI, 0]} receiveShadow>
          <planeGeometry args={[BOOK_WIDTH, BOOK_HEIGHT, 24, 1]} />
          <meshStandardMaterial map={leafBackTexture ?? leftTexture} roughness={1} />
        </mesh>
      </group>

      <mesh
        visible={state.stage === 'detail'}
        position={[-BOOK_WIDTH + 0.015, 0, 0.03]}
        onClick={turn(-1)}
      >
        <planeGeometry args={[0.03, BOOK_HEIGHT]} />
        <meshBasicMaterial transparent opacity={0} depthWrite={false} />
      </mesh>
      <mesh
        visible={state.stage === 'detail'}
        position={[BOOK_WIDTH - 0.015, 0, 0.03]}
        onClick={turn(1)}
      >
        <planeGeometry args={[0.03, BOOK_HEIGHT]} />
        <meshBasicMaterial transparent opacity={0} depthWrite={false} />
      </mesh>
    </group>
  );
}
