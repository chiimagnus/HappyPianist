import { useFrame } from '@react-three/fiber';
import { useEffect, useMemo, useRef } from 'react';
import {
  Group,
  MathUtils,
  Mesh,
  type CanvasTexture,
} from 'three';
import { pageCount, type PrototypeSong } from '../model/data.ts';
import type { PrototypeEvent, PrototypeState } from '../model/state.ts';
import {
  BOOK_HEIGHT,
  BOOK_WIDTH,
  bookPose,
} from './bookPose.ts';
import {
  createCoverTexture,
  createPageTexture,
} from './bookTextures.ts';

interface ScoreBookProps {
  index: number;
  song: PrototypeSong;
  state: PrototypeState;
  dispatch: (event: PrototypeEvent) => void;
  reducedMotion: boolean;
}

function useDisposableTexture(texture: CanvasTexture): CanvasTexture {
  useEffect(() => () => texture.dispose(), [texture]);
  return texture;
}

export function ScoreBook({ index, song, state, dispatch, reducedMotion }: ScoreBookProps) {
  const rootRef = useRef<Group>(null);
  const hingeRef = useRef<Group>(null);
  const target = bookPose(state, index);
  const selected = index === state.selected;
  const pageSpread = selected ? state.spread : 0;
  const pageMeasure = selected ? state.measure : 1;
  const pageStage = selected ? state.stage : 'library';
  const pageSession = selected && state.session;
  const pageFeedback = selected ? state.feedback : 'observed';
  const leftPage = pageSpread * 2 + 1;
  const rightPage = pageSpread * 2 + 2;

  const coverTexture = useDisposableTexture(useMemo(() => createCoverTexture(song, index), [index, song]));
  const leftTexture = useDisposableTexture(useMemo(
    () => createPageTexture({ song, page: leftPage, pageCount, measure: pageMeasure, stage: pageStage, session: pageSession, feedback: pageFeedback }),
    [leftPage, pageFeedback, pageMeasure, pageSession, pageStage, song],
  ));
  const rightTexture = useDisposableTexture(useMemo(
    () => createPageTexture({ song, page: rightPage, pageCount, measure: pageMeasure, stage: pageStage, session: pageSession, feedback: pageFeedback }),
    [pageFeedback, pageMeasure, pageSession, pageStage, rightPage, song],
  ));

  useFrame((_, delta) => {
    const root = rootRef.current;
    const hinge = hingeRef.current;
    if (!root || !hinge) return;

    const amount = reducedMotion ? 1 : 1 - Math.exp(-Math.min(delta, 0.05) * 9);
    root.position.x = MathUtils.lerp(root.position.x, target.position[0], amount);
    root.position.y = MathUtils.lerp(root.position.y, target.position[1], amount);
    root.position.z = MathUtils.lerp(root.position.z, target.position[2], amount);
    root.rotation.x = MathUtils.lerp(root.rotation.x, target.rotation[0], amount);
    root.rotation.y = MathUtils.lerp(root.rotation.y, target.rotation[1], amount);
    root.rotation.z = MathUtils.lerp(root.rotation.z, target.rotation[2], amount);
    hinge.rotation.y = MathUtils.lerp(hinge.rotation.y, target.open ? -Math.PI : 0, amount);
  });

  const handleClick = (event: { stopPropagation(): void }) => {
    event.stopPropagation();
    if (state.stage !== 'library') return;
    dispatch(index === state.selected ? { type: 'open' } : { type: 'select', value: index });
  };

  return (
    <group
      ref={rootRef}
      visible={target.visible}
      position={target.position}
      rotation={target.rotation}
      name={`score-book-${index}`}
      userData={{ songIndex: index }}
      onClick={handleClick}
    >
      <mesh position={[BOOK_WIDTH / 2, 0, 0]} castShadow receiveShadow>
        <boxGeometry args={[BOOK_WIDTH, BOOK_HEIGHT, 0.01]} />
        <meshStandardMaterial color="#e1dac8" roughness={1} />
      </mesh>

      <group ref={hingeRef} position={[0, 0, 0.013]}>
        <mesh position={[BOOK_WIDTH / 2, 0, 0]} castShadow>
          <boxGeometry args={[BOOK_WIDTH, BOOK_HEIGHT, 0.002]} />
          <meshStandardMaterial color="#ece5d4" roughness={1} />
        </mesh>
        <mesh position={[BOOK_WIDTH / 2, 0, 0.0012]}>
          <planeGeometry args={[BOOK_WIDTH, BOOK_HEIGHT]} />
          <meshStandardMaterial map={coverTexture} roughness={1} />
        </mesh>
        <mesh position={[BOOK_WIDTH / 2, 0, -0.0012]} rotation={[0, Math.PI, 0]} receiveShadow>
          <planeGeometry args={[BOOK_WIDTH, BOOK_HEIGHT]} />
          <meshStandardMaterial map={leftTexture} roughness={1} />
        </mesh>
      </group>

      <mesh position={[BOOK_WIDTH / 2, 0, 0.006]} receiveShadow>
        <planeGeometry args={[BOOK_WIDTH, BOOK_HEIGHT]} />
        <meshStandardMaterial map={rightTexture} roughness={1} />
      </mesh>

      <mesh>
        <cylinderGeometry args={[0.003, 0.003, BOOK_HEIGHT, 8]} />
        <meshStandardMaterial color="#c8bea6" roughness={1} />
      </mesh>
    </group>
  );
}
