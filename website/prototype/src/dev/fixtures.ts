import { initialState, transition, type PrototypeState } from '../model/state.ts';

export const boards = [
  ['D01', '进入与返回'],
  ['D02', '空间曲库'],
  ['D03', '展开与详情'],
  ['D04', '翻页与末页'],
  ['D05', '准备与校准'],
  ['D06', '移琴与谱位'],
  ['D07', '练习与反馈'],
  ['D08', '示范与陪弹'],
  ['D09', '结果与复测'],
  ['D10', '保存与中断'],
] as const;

export type BoardId = (typeof boards)[number][0];

function run(state: PrototypeState, ...events: Parameters<typeof transition>[1][]): PrototypeState {
  return events.reduce(transition, state);
}

export function boardState(id: BoardId): PrototypeState {
  let state = initialState();
  if (id === 'D01') return state;

  state = run(state, { type: 'enter' }, { type: 'placed' });
  if (id === 'D02') return state;

  state = run(state, { type: 'open' }, { type: 'loaded' });
  if (id === 'D03') return state;
  if (id === 'D04') return transition(state, { type: 'page', value: 1 });

  state = transition(state, { type: 'start' });
  if (id === 'D05') return state;

  state = run(
    state,
    { type: 'input', value: 'audio' },
    { type: 'connect' },
    { type: 'calibrate' },
    { type: 'calibrate' },
    { type: 'confirm' },
    { type: 'arrived' },
  );
  if (id === 'D06') return transition(state, { type: 'edit' });
  if (id === 'D07') return transition(state, { type: 'play' });
  if (id === 'D08') return transition(state, { type: 'companion', value: 'duet' });

  state = transition(state, { type: 'finish' });
  if (id === 'D09') return state;

  state = run(
    state,
    { type: 'return', value: 'library' },
    { type: 'progress-saved' },
    { type: 'facts-saved', ok: false },
  );
  return state;
}
