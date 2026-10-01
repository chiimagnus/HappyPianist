import { useFrame } from '@react-three/fiber';
import { useEffect, useMemo, useRef } from 'react';
import {
  CanvasTexture,
  DoubleSide,
  Group,
  MeshStandardMaterial,
  SRGBColorSpace,
} from 'three';
import type { PrototypeState } from '../model/state.ts';
import { pianoKeySpecs, pianoVisualState } from './pianoModel.ts';

interface PianoSceneProps {
  state: PrototypeState;
  reducedMotion: boolean;
}

function createLabelTexture(label: string): CanvasTexture {
  const canvas = document.createElement('canvas');
  canvas.width = 256;
  canvas.height = 96;
  const context = canvas.getContext('2d');
  if (!context) throw new Error('2D canvas context unavailable');
  context.font = '48px Georgia, serif';
  context.fillStyle = '#466552';
  context.textAlign = 'center';
  context.fillText(label, 128, 67);
  const texture = new CanvasTexture(canvas);
  texture.colorSpace = SRGBColorSpace;
  texture.needsUpdate = true;
  return texture;
}

function CalibrationMarker({ side, visible }: { side: -1 | 1; visible: boolean }) {
  const texture = useMemo(() => createLabelTexture(side < 0 ? 'A0' : 'C8'), [side]);
  useEffect(() => () => texture.dispose(), [texture]);

  return (
    <group visible={visible} name={side < 0 ? 'calibration-a0' : 'calibration-c8'}>
      <mesh position={[side * 0.6, 0.83, 0.11]}>
        <ringGeometry args={[0.025, 0.03, 40]} />
        <meshBasicMaterial color="#709b86" side={DoubleSide} />
      </mesh>
      <mesh position={[side * 0.6, 0.889, 0.11]}>
        <planeGeometry args={[0.095, 0.036]} />
        <meshBasicMaterial map={texture} transparent depthWrite={false} />
      </mesh>
    </group>
  );
}

function CompanionHand({ side, active, reducedMotion, material }: { side: -1 | 1; active: boolean; reducedMotion: boolean; material: MeshStandardMaterial }) {
  const handRef = useRef<Group>(null);
  const fingerRefs = useRef<Array<Group | null>>([]);

  useFrame(({ clock }) => {
    const hand = handRef.current;
    if (!hand) return;
    const time = reducedMotion ? 0 : clock.elapsedTime;
    hand.position.x = side * 0.17 + (active && !reducedMotion ? Math.sin(time * 0.9 + (side > 0 ? 1 : 0)) * 0.028 : 0);
    hand.position.y = 0.795 + (active && !reducedMotion ? Math.sin(time * 2 + (side > 0 ? 1 : 0)) * 0.007 : 0);
    hand.position.z = 0.05;
    fingerRefs.current.forEach((finger, index) => {
      if (finger) finger.rotation.x = active && !reducedMotion ? Math.sin(time * 3 + index * 1.5) * 0.12 : 0;
    });
  });

  return (
    <group ref={handRef} name={side < 0 ? 'companion-hand-left' : 'companion-hand-right'}>
      <mesh position={[0, 0, 0.044]} material={material}>
        <boxGeometry args={[0.065, 0.016, 0.072]} />
      </mesh>
      {Array.from({ length: 5 }, (_, finger) => (
        <group
          key={finger}
          ref={(node) => { fingerRefs.current[finger] = node; }}
          position={[(finger - 2) * 0.016, 0, 0.01]}
        >
          <mesh rotation={[Math.PI / 2, 0, 0]} position={[0, 0, -0.02]} material={material}>
            <capsuleGeometry args={[0.005, 0.047 - Math.abs(finger - 2) * 0.006, 4, 8]} />
          </mesh>
        </group>
      ))}
    </group>
  );
}

export function PianoScene({ state, reducedMotion }: PianoSceneProps) {
  const keys = useMemo(() => pianoKeySpecs(), []);
  const visual = pianoVisualState(state, reducedMotion);
  const whiteMaterial = useMemo(() => new MeshStandardMaterial({ color: '#eaece6', roughness: 0.6 }), []);
  const blackMaterial = useMemo(() => new MeshStandardMaterial({ color: '#323a38', roughness: 0.6 }), []);
  const pianoMaterial = useMemo(() => new MeshStandardMaterial({ color: '#838b86', roughness: 0.8 }), []);
  const handMaterial = useMemo(() => new MeshStandardMaterial({ color: '#abc9c4', transparent: true, opacity: 0.6, roughness: 0.6, depthWrite: false }), []);

  useEffect(() => () => {
    whiteMaterial.dispose();
    blackMaterial.dispose();
    pianoMaterial.dispose();
    handMaterial.dispose();
  }, [blackMaterial, handMaterial, pianoMaterial, whiteMaterial]);

  return (
    <group name="piano-scene" visible={visual.pianoVisible}>
      <mesh position={[0, 0.66, -0.02]} castShadow material={pianoMaterial}>
        <boxGeometry args={[1.32, 0.13, 0.38]} />
      </mesh>

      {keys.map((key) => (
        <mesh
          key={key.pitch}
          name={`piano-key-${key.pitch}`}
          position={key.position}
          castShadow
          receiveShadow
          material={key.black ? blackMaterial : whiteMaterial}
        >
          <boxGeometry args={key.size} />
        </mesh>
      ))}

      {([-1, 1] as const).map((side) => (
        <mesh key={side} position={[side * 0.56, 0.31, -0.04]} material={pianoMaterial}>
          <boxGeometry args={[0.045, 0.62, 0.29]} />
        </mesh>
      ))}

      <CalibrationMarker side={-1} visible={visual.a0Visible} />
      <CalibrationMarker side={1} visible={visual.c8Visible} />

      <group name="guide-rings" visible={visual.guideVisible}>
        {([-1, 1] as const).map((side) => (
          <mesh key={side} position={[side * 0.145, 0.766, 0.04]} rotation={[-Math.PI / 2, 0, 0]}>
            <ringGeometry args={[0.015, 0.018, 32]} />
            <meshBasicMaterial color="#b69752" side={DoubleSide} />
          </mesh>
        ))}
      </group>

      <group name="companion-hands" visible={visual.companionVisible}>
        <CompanionHand side={-1} active={visual.companionVisible} reducedMotion={reducedMotion} material={handMaterial} />
        <CompanionHand side={1} active={visual.companionVisible} reducedMotion={reducedMotion} material={handMaterial} />
      </group>
    </group>
  );
}
