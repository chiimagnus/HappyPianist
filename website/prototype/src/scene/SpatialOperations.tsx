import { useFrame, useThree } from '@react-three/fiber';
import { useLayoutEffect, useRef } from 'react';
import { Group } from 'three';
import { CSS3DObject, CSS3DRenderer } from 'three/addons/renderers/CSS3DRenderer.js';
import type { PrototypeState } from '../model.ts';
import type { BookHandle } from './ScoreBook.tsx';
import { height, width } from './bookTextures.ts';

interface SpatialOperationsProps {
  state: PrototypeState;
  element: HTMLDivElement;
  books: Map<number, BookHandle>;
}

export function SpatialOperations({ state, element, books }: SpatialOperationsProps) {
  const { scene, camera, gl, size } = useThree();
  const rendererRef = useRef<CSS3DRenderer | null>(null);
  const objectRef = useRef<CSS3DObject | null>(null);
  const emptyRef = useRef<Group>(null);

  useLayoutEffect(() => {
    const renderer = new CSS3DRenderer();
    renderer.domElement.id = 'css-scene';
    document.querySelector('#viewport')?.append(renderer.domElement);
    const object = new CSS3DObject(element);
    object.userData.operations = true;
    object.scale.setScalar(0.00125);
    rendererRef.current = renderer;
    objectRef.current = object;
    return () => {
      object.removeFromParent();
      element.remove();
      renderer.domElement.remove();
      rendererRef.current = null;
      objectRef.current = null;
    };
  }, [element]);

  useLayoutEffect(() => {
    rendererRef.current?.setSize(size.width, size.height);
  }, [size]);

  useFrame(() => {
    const object = objectRef.current;
    let focused: Element | null = null;
    if (object !== null) {
      const auxiliary = ['entry', 'entry-error', 'opening', 'manager'].includes(state.stage);
      object.visible = !auxiliary;
      const owner = ['empty', 'library-error'].includes(state.stage)
        ? emptyRef.current : books.get(state.selected)?.root;
      if (owner && object.parent !== owner) {
        focused = element.contains(document.activeElement) ? document.activeElement : null;
        owner.add(object);
      }
      object.position.set(state.session ? 0.60 : state.stage === 'library' ? width / 2 : 0,
        state.stage === 'detail' ? 0 : state.session ? -0.02 : -height / 2 - 0.17, 0.045);
    }
    gl.render(scene, camera);
    rendererRef.current?.render(scene, camera);
    if (focused instanceof HTMLElement) focused.focus({ preventScroll: true });
  }, 1);

  return <group ref={emptyRef} position={[0, 1.45, 0]} />;
}
