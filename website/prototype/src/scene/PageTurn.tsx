import { useFrame, useThree } from '@react-three/fiber';
import { useEffect, useLayoutEffect, useMemo, useRef } from 'react';
import type { Group, Mesh, PlaneGeometry } from 'three';
import type { PrototypeState } from '../model.ts';
import { height, pageSurface, paintPage, width, type PageSurface } from './bookTextures.ts';

interface PageTurnProps {
  state: PrototypeState;
  index: number;
  left: PageSurface;
  right: PageSurface;
}

export function PageTurn({ state, index, left, right }: PageTurnProps) {
  const { gl } = useThree();
  const leafRef = useRef<Group>(null);
  const frontRef = useRef<Mesh<PlaneGeometry>>(null);
  const backRef = useRef<Mesh<PlaneGeometry>>(null);
  const flipRef = useRef<{ progress: number; forward: boolean } | null>(null);
  const previousRef = useRef({ stage: state.stage, spread: state.spread });
  const surfaces = useMemo(() => {
    const anisotropy = gl.capabilities.getMaxAnisotropy();
    return { front: pageSurface(anisotropy), back: pageSurface(anisotropy) };
  }, [gl]);

  useLayoutEffect(() => {
    const previous = previousRef.current;
    previousRef.current = { stage: state.stage, spread: state.spread };
    const leaf = leafRef.current;
    if (leaf === null) return;
    if (state.selected !== index || !['detail', 'practice'].includes(state.stage)) {
      flipRef.current = null;
      leaf.visible = false;
    }
    if (state.selected !== index) return;
    if (previous.spread !== state.spread && previous.stage === state.stage
      && Math.abs(previous.spread - state.spread) === 1 && flipRef.current === null
      && ['detail', 'practice'].includes(state.stage)) {
      const forward = state.spread > previous.spread;
      paintPage(surfaces.front, (forward ? previous.spread : state.spread) * 2 + 2, state);
      paintPage(surfaces.back, (forward ? state.spread : previous.spread) * 2 + 1, state);
      paintPage(left, (forward ? previous.spread : state.spread) * 2 + 1, state);
      paintPage(right, (forward ? state.spread : previous.spread) * 2 + 2, state);
      flipRef.current = { progress: 0, forward };
      leaf.rotation.y = forward ? 0 : -Math.PI;
      leaf.visible = true;
    } else if (previous.spread !== state.spread || flipRef.current === null) {
      flipRef.current = null;
      leaf.visible = false;
      paintPage(left, state.spread * 2 + 1, state);
      paintPage(right, state.spread * 2 + 2, state);
    }
  }, [state, index, left, right, surfaces]);

  useFrame((_, frameDelta) => {
    const flip = flipRef.current;
    const leaf = leafRef.current;
    if (flip === null || leaf === null) return;
    flip.progress = Math.min(1, flip.progress + Math.min(frameDelta, 0.05) / 0.8);
    const eased = flip.progress * flip.progress * (3 - 2 * flip.progress);
    leaf.rotation.y = -Math.PI * (flip.forward ? eased : 1 - eased);
    for (const [mesh, sign] of [[frontRef.current, 1], [backRef.current, -1]] as const) {
      if (mesh === null) continue;
      const positions = mesh.geometry.attributes.position;
      for (let vertex = 0; vertex < positions.count; vertex += 1) {
        const ratio = (positions.getX(vertex) + width / 2) / width;
        positions.setZ(vertex, Math.sin(ratio * Math.PI) * Math.sin(eased * Math.PI) * 0.025 * sign);
      }
      positions.needsUpdate = true;
      mesh.geometry.computeVertexNormals();
    }
    if (flip.progress === 1) {
      flipRef.current = null;
      leaf.visible = false;
      paintPage(left, state.spread * 2 + 1, state);
      paintPage(right, state.spread * 2 + 2, state);
    }
  });

  useEffect(() => () => {
    surfaces.front.texture.dispose();
    surfaces.back.texture.dispose();
  }, [surfaces]);

  return (
    <group name="page-turn" ref={leafRef} position={[0, 0, 0.023]}>
      <mesh ref={frontRef} position={[width / 2, 0, 0.0005]} receiveShadow>
        <planeGeometry args={[width, height, 24, 1]} />
        <meshStandardMaterial map={surfaces.front.texture} roughness={1} />
      </mesh>
      <mesh ref={backRef} position={[width / 2, 0, -0.0005]} rotation={[0, Math.PI, 0]} receiveShadow>
        <planeGeometry args={[width, height, 24, 1]} />
        <meshStandardMaterial map={surfaces.back.texture} roughness={1} />
      </mesh>
    </group>
  );
}
