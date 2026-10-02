import { useFrame, useThree } from '@react-three/fiber';
import { forwardRef, useEffect, useImperativeHandle, useMemo, useRef } from 'react';
import { DoubleSide, MeshStandardMaterial, type Group } from 'three';
import type { WebGPURenderer } from 'three/webgpu';
import type { PrototypeState } from '../model.ts';
import { canvasTexture } from './bookTextures.ts';

const keys: { pitch: number; black: boolean; position: [number, number, number] }[] = [];
let whiteIndex = 0;
for (let pitch = 21; pitch <= 108; pitch += 1) {
  const black = [1, 3, 6, 8, 10].includes(pitch % 12);
  keys.push({ pitch, black, position: [
    -0.61 + (black ? whiteIndex - 0.5 : whiteIndex) * (1.22 / 52),
    black ? 0.757 : 0.745, black ? -0.025 : 0.017,
  ] });
  if (!black) whiteIndex += 1;
}

export interface PianoSceneHandle {
  snapshot: () => Record<string, unknown>;
}

export const PianoScene = forwardRef<PianoSceneHandle, { state: PrototypeState }>(
  function PianoScene({ state }, ref) {
    const gl = useThree((store) => store.gl as unknown as WebGPURenderer);
    const pianoRef = useRef<Group>(null);
    const companionRef = useRef<Group>(null);
    const guideRef = useRef<Group>(null);
    const materials = useMemo(() => ({
      body: new MeshStandardMaterial({ color: '#838b86', roughness: 0.8 }),
      white: new MeshStandardMaterial({ color: '#eaece6', roughness: 0.6 }),
      black: new MeshStandardMaterial({ color: '#323a38', roughness: 0.6 }),
      hand: new MeshStandardMaterial({ color: '#abc9c4', transparent: true, opacity: 0.6, roughness: 0.6, depthWrite: false }),
    }), []);
    const labels = useMemo(() => [-1, 1].map((side) => {
      const canvas = document.createElement('canvas');
      canvas.width = 256;
      canvas.height = 96;
      const context = canvas.getContext('2d');
      if (context === null) throw new Error('Canvas 2D is unavailable');
      context.font = '48px Georgia, serif';
      context.fillStyle = '#466552';
      context.textAlign = 'center';
      context.fillText(side < 0 ? 'A0' : 'C8', 128, 67);
      return canvasTexture(canvas, gl.getMaxAnisotropy());
    }), [gl]);

    useEffect(() => () => {
      Object.values(materials).forEach((material) => material.dispose());
      labels.forEach((texture) => texture.dispose());
    }, [materials, labels]);

    useImperativeHandle(ref, () => ({ snapshot: () => ({
      keyboardKeyCount: pianoRef.current?.children.filter((child) => child.userData.pitch !== undefined).length ?? 0,
      companionHandCount: companionRef.current?.children.length ?? 0,
      companionVisible: companionRef.current?.visible ?? false,
      guideVisible: guideRef.current?.visible ?? false,
    }) }), []);

    const visibleHands = state.stage === 'practice' && state.ready && !state.paused
      && !state.editing && state.companion !== 'off' && !state.yielding;
    const visiblePiano = ['input', 'permission', 'midi', 'a0', 'c8', 'ready', 'handoff',
      'practice', 'result', 'saving', 'save-error', 'discard-confirm', 'relocalize', 'suspended', 'settings'].includes(state.stage);

    useFrame(() => {
      const motionTime = performance.now() / 1000;
      companionRef.current?.children.forEach((hand, index) => {
        const side = index === 0 ? -1 : 1;
        hand.position.x = side * 0.17 + Math.sin(motionTime * 0.9 + index) * 0.028;
        hand.position.y = 0.795 + Math.sin(motionTime * 2 + index) * 0.007;
        for (let finger = 0; finger < 5; finger += 1) {
          const object = hand.getObjectByName(`finger-${finger}`);
          if (object) object.rotation.x = Math.sin(motionTime * 3 + finger * 1.5) * 0.12;
        }
      });
    });

    return (
      <>
        <group ref={pianoRef} visible={visiblePiano}>
          <mesh position={[0, 0.66, -0.02]} material={materials.body} castShadow>
            <boxGeometry args={[1.32, 0.13, 0.38]} />
          </mesh>
          {keys.map(({ pitch, black, position }) => (
            <mesh key={pitch} position={position} userData={{ pitch }}
              material={black ? materials.black : materials.white} castShadow receiveShadow>
              <boxGeometry args={[black ? 0.014 : 0.023, black ? 0.018 : 0.013, black ? 0.096 : 0.18]} />
            </mesh>
          ))}
          {[-1, 1].map((side) => (
            <mesh key={side} position={[side * 0.56, 0.31, -0.04]} material={materials.body}>
              <boxGeometry args={[0.045, 0.62, 0.29]} />
            </mesh>
          ))}
        </group>
        <group ref={guideRef} visible={state.stage === 'practice' && state.ready && !state.editing && !visibleHands}>
          {[-1, 1].map((side) => (
            <mesh key={side} rotation={[-Math.PI / 2, 0, 0]} position={[side * 0.145, 0.766, 0.04]}>
              <ringGeometry args={[0.015, 0.018, 32]} />
              <meshBasicMaterial color="#b69752" side={DoubleSide} />
            </mesh>
          ))}
        </group>
        <group visible={['a0', 'c8', 'ready'].includes(state.stage)}>
          {[-1, 1].map((side, index) => (
            <group key={side} visible={state.stage === (side < 0 ? 'a0' : 'c8') || state.stage === 'ready'}>
              <mesh position={[side * 0.6, 0.83, 0.11]}>
                <ringGeometry args={[0.025, 0.03, 40]} />
                <meshBasicMaterial color="#709b86" side={DoubleSide} />
              </mesh>
              <mesh position={[side * 0.6, 0.889, 0.11]}>
                <planeGeometry args={[0.095, 0.036]} />
                <meshBasicMaterial map={labels[index]} transparent depthWrite={false} />
              </mesh>
            </group>
          ))}
        </group>
        <group ref={companionRef} visible={visibleHands}>
          {[-1, 1].map((side) => (
            <group key={side} position={[side * 0.17, 0.795, 0.05]}>
              <mesh position={[0, 0, 0.044]} material={materials.hand}>
                <boxGeometry args={[0.065, 0.016, 0.072]} />
              </mesh>
              {[0, 1, 2, 3, 4].map((finger) => (
                <group key={finger} name={`finger-${finger}`} position={[(finger - 2) * 0.016, 0, 0.01]}>
                  <mesh rotation={[Math.PI / 2, 0, 0]} position={[0, 0, -0.02]} material={materials.hand}>
                    <capsuleGeometry args={[0.005, 0.047 - Math.abs(finger - 2) * 0.006, 4, 8]} />
                  </mesh>
                </group>
              ))}
            </group>
          ))}
        </group>
      </>
    );
  },
);
