import {
  initialState,
  transition,
  type FaultCase,
  type PrototypeState,
} from './model.ts';

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

export type BoardID = (typeof boards)[number][0];

export const faultCases = [
  { value: 'entry', label: '进入失败', board: 'D01' },
  { value: 'busy', label: '原会话占用', board: 'D01' },
  { value: 'empty', label: '曲库为空', board: 'D02' },
  { value: 'library-error', label: '曲库加载失败', board: 'D02' },
  { value: 'score', label: '曲谱加载失败', board: 'D02' },
  { value: 'permission', label: '音频权限拒绝', board: 'D05' },
  { value: 'midi', label: 'MIDI 连接失败', board: 'D05' },
  { value: 'calibration', label: '钢琴定位无效', board: 'D05' },
  { value: 'tracking', label: '追踪丢失 / 重定位失败', board: 'D07' },
  { value: 'rig', label: '伙伴手不可用', board: 'D07' },
  { value: 'ai', label: '陪弹生成失败', board: 'D07' },
  { value: 'unknown', label: '证据不足', board: 'D07' },
  { value: 'progress', label: '进度保存失败', board: 'D09' },
  { value: 'facts', label: '会话事实保存失败', board: 'D09' },
  { value: 'suspend', label: '系统中断', board: 'D07' },
] as const satisfies readonly {
  value: FaultCase;
  label: string;
  board: BoardID;
}[];

export function boardForFault(value: FaultCase): BoardID {
  const fixture = faultCases.find((candidate) => candidate.value === value);
  if (fixture === undefined) throw new Error(`Unknown fault case: ${value}`);
  return fixture.board;
}

export function boardState(id: BoardID): PrototypeState {
  let state = initialState();
  if (id === 'D01') return state;

  state = transition(state, { type: 'enter' });
  state = transition(state, { type: 'placed' });
  if (id === 'D02') return state;

  state = transition(state, { type: 'open' });
  state = transition(state, { type: 'loaded' });
  if (id === 'D03') return state;
  if (id === 'D04') return transition(state, { type: 'page', value: 1 });

  state = transition(state, { type: 'start' });
  if (id === 'D05') return state;

  state = transition(state, { type: 'input', value: 'audio' });
  state = transition(state, { type: 'connect' });
  state = transition(state, { type: 'calibrate' });
  state = transition(state, { type: 'calibrate' });
  state = transition(state, { type: 'confirm' });
  state = transition(state, { type: 'arrived' });
  if (id === 'D06') return transition(state, { type: 'edit' });
  if (id === 'D07') return transition(state, { type: 'play' });
  if (id === 'D08') return transition(state, { type: 'companion', value: 'duet' });

  state = transition(state, { type: 'finish' });
  if (id === 'D09') return state;

  state = transition(state, { type: 'fault', value: 'facts' });
  state = transition(state, { type: 'return', value: 'library' });
  state = transition(state, { type: 'progress-saved' });
  return transition(state, { type: 'facts-saved' });
}

export function faultState(value: FaultCase): PrototypeState {
  let state = boardState(boardForFault(value));
  state = transition(state, { type: 'fault', value });

  switch (value) {
    case 'entry':
    case 'busy':
      return transition(state, { type: 'enter' });
    case 'empty':
    case 'library-error':
      return transition(state, { type: 'library-case', value });
    case 'score':
      return transition(state, { type: 'open' });
    case 'permission':
    case 'midi':
      state = transition(state, { type: 'input', value: value === 'permission' ? 'audio' : 'midi' });
      return transition(state, { type: 'connect' });
    case 'calibration':
      state = transition(state, { type: 'input', value: 'audio' });
      state = transition(state, { type: 'connect' });
      state = transition(state, { type: 'calibrate' });
      return transition(state, { type: 'calibrate' });
    case 'tracking':
      state = transition(state, { type: 'tracking-lost' });
      return transition(state, { type: 'relocalized' });
    case 'rig':
      return transition(state, { type: 'companion', value: 'teaching' });
    case 'ai':
      return transition(state, { type: 'companion', value: 'duet' });
    case 'unknown':
      return transition(state, { type: 'feedback', value: 'unknown' });
    case 'progress':
    case 'facts':
      return transition(state, { type: 'return', value: 'library' });
    case 'suspend':
      return transition(state, { type: 'suspend' });
  }
}
