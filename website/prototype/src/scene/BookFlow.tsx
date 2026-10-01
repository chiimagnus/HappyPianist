import { songs } from '../model/data.ts';
import type { PrototypeEvent, PrototypeState } from '../model/state.ts';
import { ScoreBook } from './ScoreBook.tsx';

interface BookFlowProps {
  state: PrototypeState;
  dispatch: (event: PrototypeEvent) => void;
  reducedMotion: boolean;
}

export function BookFlow({ state, dispatch, reducedMotion }: BookFlowProps) {
  return (
    <group name="book-flow">
      {songs.map((song, index) => (
        <ScoreBook
          key={song.title}
          index={index}
          song={song}
          state={state}
          dispatch={dispatch}
          reducedMotion={reducedMotion}
        />
      ))}
    </group>
  );
}
