import { useThree, type ThreeEvent } from '@react-three/fiber';
import { useEffect, useLayoutEffect, useMemo, useRef } from 'react';
import { Group, type Object3D } from 'three';
import { songs, type PrototypeEvent, type PrototypeState } from '../model.ts';
import { coverTexture, height, pageSurface, width, type PageSurface } from './bookTextures.ts';
import { PageTurn } from './PageTurn.tsx';

export interface BookHandle {
  root: Group;
  hinge: Group;
  open: number;
  left: PageSurface;
  right: PageSurface;
}

interface ScoreBookProps {
  index: number;
  state: PrototypeState;
  dispatch: (event: PrototypeEvent) => void;
  books: Map<number, BookHandle>;
}

export function ScoreBook({ index, state, dispatch, books }: ScoreBookProps) {
  const { gl } = useThree();
  const rootRef = useRef<Group>(null);
  const hingeRef = useRef<Group>(null);
  const textures = useMemo(() => {
    const anisotropy = gl.capabilities.getMaxAnisotropy();
    return {
      cover: coverTexture(songs[index], index, anisotropy),
      left: pageSurface(anisotropy),
      right: pageSurface(anisotropy),
    };
  }, [gl, index]);

  useLayoutEffect(() => {
    if (rootRef.current === null || hingeRef.current === null) return;
    books.set(index, {
      root: rootRef.current,
      hinge: hingeRef.current,
      open: 0,
      left: textures.left,
      right: textures.right,
    });
    rootRef.current.position.set((index - 2) * 0.35 - width / 2, 1.45, -Math.abs(index - 2) * 0.18);
    return () => { books.delete(index); };
  }, [books, index, textures]);

  useEffect(() => () => {
    textures.cover.dispose();
    textures.left.texture.dispose();
    textures.right.texture.dispose();
  }, [textures]);

  const clickBook = (event: ThreeEvent<MouseEvent>) => {
    if (event.delta > 6 || !rootRef.current?.visible) return;
    let hit: Object3D | null = event.object;
    while (hit !== null) {
      if (!hit.visible) return;
      hit = hit.parent;
    }
    event.stopPropagation();
    if (state.stage === 'library') {
      dispatch(state.selected === index ? { type: 'open' } : { type: 'select', value: index });
    } else if (state.stage === 'detail' && state.selected === index) {
      const local = rootRef.current.worldToLocal(event.point.clone());
      if (Math.abs(local.x) > width * 0.72) dispatch({ type: 'page', value: local.x > 0 ? 1 : -1 });
    }
  };

  return (
    <group ref={rootRef} onClick={clickBook} userData={{ song: index }}>
      <mesh position={[width / 2, 0, 0]} castShadow receiveShadow>
        <boxGeometry args={[width, height, 0.01]} />
        <meshStandardMaterial color="#e1dac8" roughness={1} />
      </mesh>
      <group ref={hingeRef} position={[0, 0, 0.013]}>
        <mesh position={[width / 2, 0, 0]} castShadow>
          <boxGeometry args={[width, height, 0.002]} />
          <meshStandardMaterial color="#ece5d4" roughness={1} />
        </mesh>
        <mesh position={[width / 2, 0, 0.0012]}>
          <planeGeometry args={[width, height]} />
          <meshStandardMaterial map={textures.cover} roughness={1} />
        </mesh>
        <mesh position={[width / 2, 0, -0.0012]} rotation={[0, Math.PI, 0]} receiveShadow>
          <planeGeometry args={[width, height, 24, 1]} />
          <meshStandardMaterial map={textures.left.texture} roughness={1} />
        </mesh>
      </group>
      <mesh position={[width / 2, 0, 0.006]} receiveShadow>
        <planeGeometry args={[width, height, 24, 1]} />
        <meshStandardMaterial map={textures.right.texture} roughness={1} />
      </mesh>
      <mesh>
        <cylinderGeometry args={[0.003, 0.003, height, 8]} />
        <meshStandardMaterial color="#c8bea6" roughness={1} />
      </mesh>
      <PageTurn state={state} index={index} left={textures.left} right={textures.right} />
    </group>
  );
}
