import { Canvas } from '@react-three/fiber';
import { useState } from 'react';
import type { FaultCase, PrototypeState } from './model.ts';
import {
  boardForFault,
  boards,
  boardState,
  faultState,
  type BoardID,
} from './reviewFixtures.ts';
import { usePrototypeController } from './runtime/usePrototypeController.ts';
import { AppShell } from './ui/AppShell.tsx';
import { ProductUI } from './ui/ProductUI.tsx';
import { ReviewPanel } from './ui/ReviewPanel.tsx';

interface ReviewRoute {
  board: BoardID;
  fault?: FaultCase;
  revision: number;
}

interface PrototypeRuntimeProps {
  seed: PrototypeState;
  currentBoard: BoardID;
  onLoadBoard: (board: BoardID) => void;
  onInjectFault: (fault: FaultCase) => void;
  onReset: () => void;
}

function PrototypeRuntime({
  seed,
  currentBoard,
  onLoadBoard,
  onInjectFault,
  onReset,
}: PrototypeRuntimeProps) {
  const { state, dispatch } = usePrototypeController(seed);
  const auxiliary = state.stage === 'entry'
    || state.stage === 'entry-error'
    || state.stage === 'opening'
    || state.stage === 'manager';
  const product = (
    <ProductUI
      state={state}
      dispatch={dispatch}
      reviewOnly={!auxiliary}
    />
  );

  return (
    <AppShell
      state={state}
      viewport={(
        <Canvas camera={{ position: [0, 0.4, 2.4], fov: 45 }}>
          <color attach="background" args={['#e9e5df']} />
          <ambientLight intensity={1.2} />
          <directionalLight position={[2, 3, 2]} intensity={2} />
          <mesh rotation={[0.2, 0.35, 0]}>
            <boxGeometry args={[0.7, 0.9, 0.08]} />
            <meshStandardMaterial color="#d7cfbc" roughness={0.85} />
          </mesh>
        </Canvas>
      )}
      product={auxiliary ? product : null}
      review={(
        <ReviewPanel
          state={state}
          currentBoard={currentBoard}
          onLoadBoard={onLoadBoard}
          onInjectFault={onInjectFault}
          onReset={onReset}
        >
          {auxiliary ? null : product}
        </ReviewPanel>
      )}
    />
  );
}

export function App() {
  const [route, setRoute] = useState<ReviewRoute>({
    board: boards.find(([id]) => id === new URLSearchParams(location.search).get('board'))?.[0] ?? 'D01',
    revision: 0,
  });
  const seed = route.fault === undefined
    ? boardState(route.board)
    : faultState(route.fault);

  const loadBoard = (board: BoardID) => {
    setRoute((current) => ({
      board,
      revision: current.revision + 1,
    }));
  };

  const injectFault = (fault: FaultCase) => {
    setRoute((current) => ({
      board: boardForFault(fault),
      fault,
      revision: current.revision + 1,
    }));
  };

  const reset = () => {
    setRoute((current) => ({
      board: 'D01',
      revision: current.revision + 1,
    }));
  };

  return (
    <PrototypeRuntime
      key={route.revision}
      seed={seed}
      currentBoard={route.board}
      onLoadBoard={loadBoard}
      onInjectFault={injectFault}
      onReset={reset}
    />
  );
}
