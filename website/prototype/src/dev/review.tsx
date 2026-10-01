import { useThree } from '@react-three/fiber';
import { useEffect, type MutableRefObject } from 'react';
import { Vector3 } from 'three';
import { songs } from '../model/data.ts';
import type { PrototypeState } from '../model/state.ts';
import { BOOK_WIDTH } from '../scene/bookPose.ts';
import type { CameraView } from '../scene/cameraViews.ts';
import { boardState, boards, type BoardId } from './fixtures.ts';

export interface SceneReviewFacts {
  selectedBook: {
    index: number;
    title: string;
    worldPosition: [number, number, number] | null;
    screenPoint: [number, number] | null;
  };
  visibleBookCount: number;
  flipActive: boolean;
  pianoKeyCount: number;
  handCount: number;
  guideVisible: boolean;
  companionVisible: boolean;
}

export type SceneReviewReader = () => SceneReviewFacts;

export interface PrototypeReviewSnapshot {
  state: PrototypeState;
  view: CameraView;
  scene: SceneReviewFacts;
}

interface ReviewAPI {
  loadBoard(id: BoardId): void;
  setView(view: CameraView): void;
  snapshot(): PrototypeReviewSnapshot;
}

declare global {
  interface Window {
    happyPianistPrototypeReview?: ReviewAPI;
  }
}

interface PrototypeReviewOptions {
  state: PrototypeState;
  replaceState: (state: PrototypeState) => void;
  view: CameraView;
  setView: (view: CameraView) => void;
  sceneReaderRef: MutableRefObject<SceneReviewReader | null>;
}

const validViews = new Set<CameraView>(['front', 'oblique', 'side', 'top']);
const validBoards = new Set<string>(boards.map(([id]) => id));

export function usePrototypeReview({ state, replaceState, view, setView, sceneReaderRef }: PrototypeReviewOptions): void {
  useEffect(() => {
    if (!import.meta.env.DEV) return;

    window.happyPianistPrototypeReview = {
      loadBoard(id) {
        if (!validBoards.has(id)) throw new Error(`Unknown board: ${id}`);
        replaceState(boardState(id));
      },
      setView(nextView) {
        if (!validViews.has(nextView)) throw new Error(`Unknown view: ${nextView}`);
        setView(nextView);
      },
      snapshot() {
        const scene = sceneReaderRef.current;
        if (!scene) throw new Error('Scene review snapshot is not ready');
        return {
          state: structuredClone(state),
          view,
          scene: scene(),
        };
      },
    };

    return () => {
      delete window.happyPianistPrototypeReview;
    };
  }, [replaceState, sceneReaderRef, setView, state, view]);
}

interface SceneReviewProbeProps {
  state: PrototypeState;
  readerRef: MutableRefObject<SceneReviewReader | null>;
}

export function SceneReviewProbe({ state, readerRef }: SceneReviewProbeProps) {
  const scene = useThree((value) => value.scene);
  const camera = useThree((value) => value.camera);
  const size = useThree((value) => value.size);

  useEffect(() => {
    readerRef.current = () => {
      scene.updateMatrixWorld(true);
      camera.updateMatrixWorld(true);

      const selected = scene.getObjectByName(`score-book-${state.selected}`);
      let worldPosition: [number, number, number] | null = null;
      let screenPoint: [number, number] | null = null;
      if (selected) {
        const center = selected.localToWorld(new Vector3(BOOK_WIDTH / 2, 0, 0.02));
        worldPosition = [center.x, center.y, center.z];
        const projected = center.clone().project(camera);
        screenPoint = [
          (projected.x + 1) * size.width / 2,
          (1 - projected.y) * size.height / 2,
        ];
      }

      const bookFlow = scene.getObjectByName('book-flow');
      let pianoKeyCount = 0;
      scene.traverse((object) => {
        if (object.name.startsWith('piano-key-')) pianoKeyCount += 1;
      });

      const hands = scene.getObjectByName('companion-hands');
      const guide = scene.getObjectByName('guide-rings');

      return {
        selectedBook: {
          index: state.selected,
          title: songs[state.selected]?.title ?? '',
          worldPosition,
          screenPoint,
        },
        visibleBookCount: bookFlow?.children.filter((object) => object.visible).length ?? 0,
        flipActive: scene.getObjectByName('page-turn-leaf')?.visible ?? false,
        pianoKeyCount,
        handCount: hands?.children.length ?? 0,
        guideVisible: guide?.visible ?? false,
        companionVisible: hands?.visible ?? false,
      };
    };

    return () => {
      readerRef.current = null;
    };
  }, [camera, readerRef, scene, size.height, size.width, state.selected]);

  return null;
}
