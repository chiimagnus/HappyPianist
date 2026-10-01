import type { PrototypeState } from '../model/state.ts';

export type ProductPlacement = 'screen' | 'book' | 'piano';

const SCREEN_STAGES = new Set<PrototypeState['stage']>([
  'entry',
  'entry-error',
  'opening',
  'empty',
  'library-error',
  'manager',
]);

export function productPlacement(state: PrototypeState): ProductPlacement {
  if (SCREEN_STAGES.has(state.stage)) return 'screen';
  if (state.session) return 'piano';
  return 'book';
}
