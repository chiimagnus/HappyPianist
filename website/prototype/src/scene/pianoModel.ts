import type { PrototypeState } from '../model/state.ts';

export interface PianoKeySpec {
  pitch: number;
  black: boolean;
  size: readonly [number, number, number];
  position: readonly [number, number, number];
}

export interface PianoVisualState {
  pianoVisible: boolean;
  a0Visible: boolean;
  c8Visible: boolean;
  companionVisible: boolean;
  guideVisible: boolean;
}

const PIANO_STAGES = new Set<PrototypeState['stage']>([
  'input',
  'permission',
  'midi',
  'a0',
  'c8',
  'ready',
  'handoff',
  'practice',
  'result',
  'saving',
  'save-error',
  'discard-confirm',
  'relocalize',
  'suspended',
  'settings',
]);

export function pianoKeySpecs(): readonly PianoKeySpec[] {
  const keys: PianoKeySpec[] = [];
  let whiteIndex = 0;

  for (let pitch = 21; pitch <= 108; pitch += 1) {
    const black = [1, 3, 6, 8, 10].includes(pitch % 12);
    keys.push({
      pitch,
      black,
      size: black ? [0.014, 0.018, 0.096] : [0.023, 0.013, 0.18],
      position: [
        -0.61 + (black ? whiteIndex - 0.5 : whiteIndex) * (1.22 / 52),
        black ? 0.757 : 0.745,
        black ? -0.025 : 0.017,
      ],
    });
    if (!black) whiteIndex += 1;
  }

  return keys;
}

export function pianoVisualState(state: PrototypeState, reducedMotion: boolean): PianoVisualState {
  const companionVisible = state.stage === 'practice'
    && state.ready
    && !state.paused
    && !state.editing
    && state.companion !== 'off'
    && !state.yielding;

  return {
    pianoVisible: PIANO_STAGES.has(state.stage),
    a0Visible: state.stage === 'a0' || state.stage === 'ready',
    c8Visible: state.stage === 'c8' || state.stage === 'ready',
    companionVisible,
    guideVisible: state.stage === 'practice'
      && state.ready
      && !state.editing
      && (!companionVisible || reducedMotion),
  };
}
