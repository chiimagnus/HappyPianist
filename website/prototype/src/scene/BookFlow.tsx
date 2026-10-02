import { useFrame } from '@react-three/fiber';
import { useMemo } from 'react';
import { MathUtils, Vector3 } from 'three';
import { songs, type PrototypeEvent, type PrototypeState } from '../model.ts';
import { ScoreBook, type BookHandle } from './ScoreBook.tsx';
import { width } from './bookTextures.ts';

interface BookFlowProps {
  state: PrototypeState;
  dispatch: (event: PrototypeEvent) => void;
  books: Map<number, BookHandle>;
}

export function BookFlow({ state, dispatch, books }: BookFlowProps) {
  const target = useMemo(() => new Vector3(), []);

  useFrame((_, frameDelta) => {
    const amount = 1 - Math.exp(-Math.min(frameDelta, 0.05) * 9);
    const isLibrary = state.stage === 'library';
    const hidden = ['entry', 'entry-error', 'opening', 'empty', 'library-error', 'manager'].includes(state.stage);
    const unfolded = !['library', 'loading', 'detail-error'].includes(state.stage);
    for (const [index, book] of books) {
      const distance = index - state.selected;
      book.root.visible = !hidden && (isLibrary ? Math.abs(distance) <= 2 : index === state.selected);
      if (!book.root.visible) continue;
      book.open = MathUtils.lerp(book.open, index === state.selected && unfolded ? 1 : 0, amount);
      book.hinge.rotation.y = -Math.PI * book.open;
      const targetX = isLibrary
        ? Math.sign(distance) * (Math.abs(distance) === 1 ? 0.36 : Math.abs(distance) * 0.30) - width / 2
        : -width / 2 * (1 - book.open) + (state.session ? state.offset[0] : 0);
      target.set(targetX, state.session ? 1.24 + state.offset[1] : 1.45,
        isLibrary ? -Math.abs(distance) * 0.23 : state.session ? -0.13 + state.offset[2] : 0.08);
      book.root.position.lerp(target, amount);
      book.root.rotation.y = MathUtils.lerp(book.root.rotation.y,
        isLibrary ? -Math.sign(distance) * Math.min(Math.abs(distance) * 0.5, 0.85) : 0, amount);
      book.root.rotation.x = MathUtils.lerp(book.root.rotation.x, state.session ? -0.13 : 0, amount);
    }
  });

  return songs.map((_, index) => (
    <ScoreBook key={index} index={index} state={state} dispatch={dispatch} books={books} />
  ));
}
