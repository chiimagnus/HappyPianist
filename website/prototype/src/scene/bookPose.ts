import type { PrototypeState } from '../model/state.ts';

export const BOOK_WIDTH = 0.32;
export const BOOK_HEIGHT = 0.43;

export interface BookPose {
  visible: boolean;
  open: boolean;
  position: readonly [number, number, number];
  rotation: readonly [number, number, number];
}

const HIDDEN_STAGES = new Set<PrototypeState['stage']>([
  'entry',
  'entry-error',
  'opening',
  'empty',
  'library-error',
  'manager',
]);

const CLOSED_STAGES = new Set<PrototypeState['stage']>([
  'library',
  'loading',
  'detail-error',
]);

export function bookPose(state: PrototypeState, index: number): BookPose {
  const distance = index - state.selected;
  const inLibrary = state.stage === 'library';
  const visible = !HIDDEN_STAGES.has(state.stage)
    && (inLibrary ? Math.abs(distance) <= 2 : index === state.selected);
  const open = index === state.selected && !CLOSED_STAGES.has(state.stage);
  const onPiano = state.session;

  if (inLibrary) {
    const absoluteDistance = Math.abs(distance);
    const x = distance === 0
      ? -BOOK_WIDTH / 2
      : Math.sign(distance) * (absoluteDistance === 1 ? 0.36 : absoluteDistance * 0.30) - BOOK_WIDTH / 2;

    return {
      visible,
      open: false,
      position: [x, 1.45, absoluteDistance === 0 ? 0 : -absoluteDistance * 0.23],
      rotation: [0, -Math.sign(distance) * Math.min(absoluteDistance * 0.5, 0.85), 0],
    };
  }

  return {
    visible,
    open,
    position: [(open ? 0 : -BOOK_WIDTH / 2) + (onPiano ? state.offset[0] : 0), onPiano ? 1.24 + state.offset[1] : 1.45, onPiano ? -0.13 + state.offset[2] : 0.08],
    rotation: [onPiano ? -0.13 : 0, 0, 0],
  };
}
