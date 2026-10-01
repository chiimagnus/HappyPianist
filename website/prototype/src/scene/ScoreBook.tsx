import { useFrame } from '@react-three/fiber';
import { useEffect, useMemo, useRef } from 'react';
import {
  Group,
  MathUtils,
  type CanvasTexture,
} from 'three';
import type { PrototypeSong } from '../model/data.ts';
import type { PrototypeEvent, PrototypeState } from '../model/state.ts';
import {
  BOOK_HEIGHT,
  BOOK_HINGE_Z,
  BOOK_WIDTH,
  bookPose,
} from './bookPose.ts';
import { createCoverTexture } from './bookTextures.ts';
import { PageTurn } from './PageTurn.tsx';

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
  const hingeRef = useRef<Group>(null);
  const target = bookPose(state, index);
  const selected = index === state.selected;
  const coverTexture = useDisposableTexture(useMemo(() => createCoverTexture(song, index), [index, song]));

  useFrame((_, delta) => {
    const hinge = hingeRef.current;
    if (!hinge) return;

    const amount = reducedMotion ? 1 : 1 - Math.exp(-Math.min(delta, 0.05) * 9);
    hinge.rotation.y = MathUtils.lerp(hinge.rotation.y, target.open ? -Math.PI : 0, amount);
  });

  const handleClick = (event: { stopPropagation(): void }) => {
    event.stopPropagation();
    if (state.stage !== 'library') return;
    dispatch(index === state.selected ? { type: 'open' } : { type: 'select', value: index });
  };

  return (
    <group
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

      <group ref={hingeRef} position={[0, 0, BOOK_HINGE_Z]}>
        <mesh position={[BOOK_WIDTH / 2, 0, 0]} castShadow>
          <boxGeometry args={[BOOK_WIDTH, BOOK_HEIGHT, 0.002]} />
          <meshStandardMaterial color="#ece5d4" roughness={1} />
        </mesh>
        <mesh position={[BOOK_WIDTH / 2, 0, 0.0012]}>
          <planeGeometry args={[BOOK_WIDTH, BOOK_HEIGHT]} />
          <meshStandardMaterial map={coverTexture} roughness={1} />
        </mesh>
      </group>

      {selected && (
        <PageTurn
          song={song}
          state={state}
          dispatch={dispatch}
          open={target.open}
          reducedMotion={reducedMotion}
        />
      )}

      <mesh>
        <cylinderGeometry args={[0.003, 0.003, BOOK_HEIGHT, 8]} />
        <meshStandardMaterial color="#c8bea6" roughness={1} />
      </mesh>
    </group>
  );
}
