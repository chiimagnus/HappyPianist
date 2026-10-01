import { Html } from '@react-three/drei/web/Html.js';
import type { PrototypeEvent, PrototypeState } from '../model/state.ts';
import { ProductControls } from '../ui/ProductControls.tsx';

interface SpatialProductControlsProps {
  owner: 'book' | 'piano';
  state: PrototypeState;
  dispatch: (event: PrototypeEvent) => void;
}

function controlPosition(owner: 'book' | 'piano'): [number, number, number] {
  return owner === 'piano' ? [0.58, 1.22, -0.02] : [0, 1.08, 0.08];
}

export function SpatialProductControls({ owner, state, dispatch }: SpatialProductControlsProps) {
  return (
    <Html
      center
      position={controlPosition(owner)}
      distanceFactor={1}
      wrapperClass="spatial-product-html"
      pointerEvents="auto"
    >
      <ProductControls state={state} dispatch={dispatch} spatial />
    </Html>
  );
}
