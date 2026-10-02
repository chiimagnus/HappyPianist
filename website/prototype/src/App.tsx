import { useCallback, useRef, useState } from 'react';
import type { FaultCase, PrototypeState } from './model.ts';
import {
  boardForFault,
  boardState,
  boards,
  faultState,
  type BoardID,
  type ReviewView,
} from './reviewFixtures.ts';
import { SpatialScene, type SpatialSceneHandle } from './scene/SpatialScene.tsx';
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
  view: ReviewView;
  onViewChange: (view: ReviewView) => void;
}

function PrototypeRuntime({
  seed,
  currentBoard,
  onLoadBoard,
  onInjectFault,
  onReset,
  view,
  onViewChange,
}: PrototypeRuntimeProps) {
  const sceneRef = useRef<SpatialSceneHandle>(null);
  const reviewSnapshot = useCallback(
    () => sceneRef.current?.snapshot() ?? {},
    [],
  );
  const { state, dispatch } = usePrototypeController(seed, { reviewSnapshot });
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
      viewport={<SpatialScene ref={sceneRef} view={view} />}
      product={auxiliary ? product : null}
      view={view}
      onViewChange={onViewChange}
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
  const [view, setView] = useState<ReviewView>('front');
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
    setView('front');
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
      view={view}
      onViewChange={setView}
    />
  );
}
