import { pageCount, songs, totalMeasures } from './data.ts';

export type PrototypeStage =
  | 'entry'
  | 'entry-error'
  | 'opening'
  | 'library'
  | 'empty'
  | 'library-error'
  | 'loading'
  | 'detail'
  | 'detail-error'
  | 'input'
  | 'permission'
  | 'midi'
  | 'a0'
  | 'c8'
  | 'ready'
  | 'handoff'
  | 'practice'
  | 'result'
  | 'saving'
  | 'save-error'
  | 'discard-confirm'
  | 'relocalize'
  | 'suspended'
  | 'manager'
  | 'settings';

export type InputMode = 'audio' | 'midi';
export type CompanionMode = 'off' | 'teaching' | 'duet';
export type FeedbackMode = 'observed' | 'unknown';
export type Destination = 'entry' | 'library';
export type Range = [number, number];
export type Offset = [number, number, number];

export interface PrototypeState {
  stage: PrototypeStage;
  selected: number;
  spread: number;
  measure: number;
  input: InputMode;
  ready: boolean;
  usingStored: boolean;
  session: boolean;
  paused: boolean;
  dirty: boolean;
  progressSaved: boolean;
  factsSaved: boolean;
  savedMeasure: number;
  controls: boolean;
  recording: boolean;
  metronome: boolean;
  companion: CompanionMode;
  yielding: boolean;
  guide: boolean;
  audition: boolean;
  loop: boolean;
  range: Range;
  teachingBeat: number;
  feedback: FeedbackMode;
  offset: Offset;
  editing: boolean;
  editStart: Offset;
  destination: Destination;
  resumeStage: 'practice' | 'result' | 'ready';
  message: string;
  search: string;
}

export type PrototypeEvent =
  | { type: 'enter'; ok?: boolean }
  | { type: 'placed'; ok?: boolean }
  | { type: 'cancel' }
  | { type: 'select'; value: number }
  | { type: 'search'; value: string }
  | { type: 'listen' }
  | { type: 'open' }
  | { type: 'loaded'; ok?: boolean }
  | { type: 'page'; value: number }
  | { type: 'start'; value?: 'begin' | 'resume' | 'focus' }
  | { type: 'input'; value: InputMode }
  | { type: 'connect'; ok?: boolean }
  | { type: 'calibrate'; ok?: boolean }
  | { type: 'recalibrate' }
  | { type: 'restore' }
  | { type: 'confirm' }
  | { type: 'arrived' }
  | { type: 'play' }
  | { type: 'tick' }
  | { type: 'finish' }
  | { type: 'seek'; value: number }
  | { type: 'loop' }
  | { type: 'controls' }
  | { type: 'record' }
  | { type: 'metronome' }
  | { type: 'companion'; value: CompanionMode; failure?: 'rig' | 'ai' }
  | { type: 'yield' }
  | { type: 'feedback'; value: FeedbackMode }
  | { type: 'edit' }
  | { type: 'move'; axis: 0 | 1 | 2; value: number }
  | { type: 'reset-position' }
  | { type: 'edit-done'; cancel?: boolean }
  | { type: 'retest'; value: 'focus' | 'all' }
  | { type: 'continue' }
  | { type: 'return'; value: 'entry' | '2d' | 'library' }
  | { type: 'progress-saved'; ok?: boolean }
  | { type: 'facts-saved'; ok?: boolean }
  | { type: 'retry-save' }
  | { type: 'stay' }
  | { type: 'discard' }
  | { type: 'discard-confirm' }
  | { type: 'tracking-lost' }
  | { type: 'relocalized'; ok?: boolean }
  | { type: 'suspend' }
  | { type: 'resume' }
  | { type: 'settings' }
  | { type: 'manage' }
  | { type: 'managed' }
  | { type: 'library-case'; value: 'empty' | 'library-error' }
  | { type: 'retry-library' };

export function initialState(): PrototypeState {
  return {
    stage: 'entry',
    selected: 2,
    spread: 0,
    measure: 1,
    input: 'audio',
    ready: false,
    usingStored: false,
    session: false,
    paused: true,
    dirty: false,
    progressSaved: false,
    factsSaved: false,
    savedMeasure: 0,
    controls: false,
    recording: false,
    metronome: false,
    companion: 'off',
    yielding: false,
    guide: true,
    audition: false,
    loop: false,
    range: [1, totalMeasures],
    teachingBeat: 0,
    feedback: 'observed',
    offset: [0, 0, 0],
    editing: false,
    editStart: [0, 0, 0],
    destination: 'library',
    resumeStage: 'practice',
    message: '',
    search: '',
  };
}

export function spreadForMeasure(measure: number): number {
  return Math.floor((Math.min(totalMeasures, Math.max(1, measure)) - 1) / 16);
}

function cloneOffset(offset: Offset): Offset {
  return [offset[0], offset[1], offset[2]];
}

export function transition(previous: PrototypeState, event: PrototypeEvent): PrototypeState {
  const state = structuredClone(previous);
  const stage = state.stage;

  const stop = () => {
    state.paused = true;
    state.companion = 'off';
    state.recording = false;
    state.audition = false;
    state.yielding = false;
  };

  const leave = () => {
    stop();
    state.session = false;
    state.dirty = false;
    state.ready = false;
    state.editing = false;
    state.controls = false;
    state.stage = state.destination;
    state.message = '';
  };

  switch (event.type) {
    case 'enter':
      if (!['entry', 'entry-error'].includes(stage)) break;
      if (event.ok === false) {
        state.stage = 'entry-error';
        state.message = '原练习或导入仍在使用资源，请先结束。';
      } else {
        state.stage = 'opening';
        state.message = '';
      }
      break;
    case 'placed':
      if (stage !== 'opening') break;
      state.stage = event.ok === false ? 'entry-error' : 'library';
      state.message = state.stage === 'entry-error' ? '空间摆放未成功。原二维曲库仍保留。' : '';
      break;
    case 'cancel':
      if (['opening', 'entry-error'].includes(stage)) state.stage = 'entry';
      else if (['loading', 'detail-error'].includes(stage)) state.stage = 'library';
      else if (['input', 'permission', 'midi', 'a0', 'c8', 'ready'].includes(stage)) {
        state.stage = 'detail';
        state.ready = false;
      } else if (stage === 'relocalize' && !state.session) state.stage = 'detail';
      else if (stage === 'discard-confirm') state.stage = 'save-error';
      break;
    case 'select':
      if (stage !== 'library' || !Number.isInteger(event.value) || event.value < 0 || event.value >= songs.length) break;
      state.selected = event.value;
      state.audition = false;
      state.search = '';
      break;
    case 'search':
      if (stage === 'library') state.search = event.value;
      break;
    case 'listen':
      if (['library', 'detail'].includes(stage)) state.audition = !state.audition;
      break;
    case 'open':
      if (!['library', 'detail-error'].includes(stage)) break;
      state.stage = 'loading';
      state.spread = 0;
      state.audition = false;
      state.message = '';
      break;
    case 'loaded':
      if (stage !== 'loading') break;
      state.stage = event.ok === false ? 'detail-error' : 'detail';
      break;
    case 'page':
      if (stage === 'detail' && Number.isInteger(event.value)) {
        state.spread = Math.max(0, Math.min(Math.ceil(pageCount / 2) - 1, state.spread + event.value));
      }
      break;
    case 'start':
      if (stage !== 'detail') break;
      state.stage = 'input';
      state.measure = event.value === 'resume' || event.value === 'focus' ? 9 : 1;
      state.range = event.value === 'focus' ? [9, 12] : [1, totalMeasures];
      state.spread = spreadForMeasure(state.measure);
      state.audition = false;
      state.usingStored = false;
      break;
    case 'input':
      if (stage !== 'input') break;
      state.input = event.value;
      state.stage = event.value === 'audio' ? 'permission' : 'midi';
      break;
    case 'connect':
      if (!['permission', 'midi'].includes(stage)) break;
      if (event.ok === false) {
        state.message = stage === 'permission' ? '权限未允许，尚未开始练习。' : '设备未连接，尚未开始练习。';
      } else {
        state.stage = state.usingStored ? 'relocalize' : 'a0';
        if (state.usingStored) state.resumeStage = 'ready';
        state.message = '';
      }
      break;
    case 'calibrate':
      if (stage === 'a0') state.stage = 'c8';
      else if (stage === 'c8') {
        if (event.ok === false) state.message = '两端距离或演奏侧无效，请重做定位。';
        else {
          state.stage = 'ready';
          state.ready = true;
          state.message = '';
        }
      }
      break;
    case 'recalibrate':
      if (['a0', 'c8', 'ready'].includes(stage)) {
        state.stage = 'a0';
        state.ready = false;
        state.message = '';
      }
      break;
    case 'restore':
      if (stage === 'input') {
        state.usingStored = true;
        state.stage = 'permission';
        state.input = 'audio';
        state.ready = false;
      }
      break;
    case 'confirm':
      if (stage !== 'ready' || !state.ready) break;
      state.stage = 'handoff';
      state.session = true;
      state.progressSaved = false;
      state.factsSaved = false;
      state.offset = [0, 0, 0];
      break;
    case 'arrived':
      if (stage === 'handoff') {
        state.stage = 'practice';
        state.paused = true;
      }
      break;
    case 'play':
      if (stage === 'practice' && state.ready && !state.editing) state.paused = !state.paused;
      break;
    case 'tick':
      if (stage !== 'practice' || state.paused || state.editing || !state.ready) break;
      state.dirty = true;
      if (state.companion === 'teaching') {
        state.teachingBeat += 1;
        if (state.teachingBeat >= 4) {
          state.companion = 'off';
          state.paused = true;
        }
      } else if (state.measure < state.range[1]) state.measure += 1;
      else if (state.loop) state.measure = state.range[0];
      else {
        state.stage = 'result';
        stop();
      }
      state.spread = spreadForMeasure(state.measure);
      break;
    case 'finish':
      if (stage === 'practice') {
        state.stage = 'result';
        state.dirty = true;
        stop();
      }
      break;
    case 'seek':
      if (stage !== 'practice' || !Number.isFinite(event.value) || state.editing) break;
      state.measure = Math.max(state.range[0], Math.min(state.range[1], Math.round(event.value)));
      state.spread = spreadForMeasure(state.measure);
      state.companion = 'off';
      state.paused = true;
      break;
    case 'loop':
      if (stage === 'practice') {
        state.loop = !state.loop;
        state.range = state.loop ? [9, 16] : [1, totalMeasures];
        state.measure = state.range[0];
        state.spread = spreadForMeasure(state.measure);
        state.paused = true;
        state.companion = 'off';
      }
      break;
    case 'controls':
      if (['practice', 'result'].includes(stage)) state.controls = !state.controls;
      break;
    case 'record':
      if (stage === 'practice' && !state.editing && state.companion === 'off') {
        state.recording = !state.recording;
        state.dirty ||= state.recording;
      }
      break;
    case 'metronome':
      if (stage === 'practice') state.metronome = !state.metronome;
      break;
    case 'companion':
      if (stage !== 'practice' || !state.ready || state.editing) break;
      if (event.failure === 'ai' && event.value === 'duet') {
        state.companion = 'off';
        state.message = '本次陪弹失败，已停止。未切换 AI 后端。';
        break;
      }
      if (event.failure === 'rig') {
        state.companion = 'off';
        state.guide = true;
        state.message = '手部动作不可用，保留琴键 Guide。';
        break;
      }
      state.guide = true;
      state.companion = event.value;
      state.message = '';
      state.teachingBeat = 0;
      state.yielding = false;
      if (state.companion !== 'off') {
        state.paused = false;
        state.recording = false;
      }
      break;
    case 'yield':
      if (stage === 'practice' && state.companion === 'duet') state.yielding = !state.yielding;
      break;
    case 'feedback':
      if (['practice', 'result'].includes(stage)) state.feedback = event.value;
      break;
    case 'edit':
      if (stage === 'practice') {
        stop();
        state.editing = true;
        state.editStart = cloneOffset(state.offset);
      }
      break;
    case 'move':
      if (stage !== 'practice' || !state.editing || !Number.isFinite(event.value)) break;
      state.offset[event.axis] = Math.max(-0.12, Math.min(0.12, state.offset[event.axis] + event.value));
      break;
    case 'reset-position':
      if (stage === 'practice' && state.editing) state.offset = [0, 0, 0];
      break;
    case 'edit-done':
      if (stage === 'practice' && state.editing) {
        if (event.cancel) state.offset = cloneOffset(state.editStart);
        state.editing = false;
      }
      break;
    case 'retest':
      if (stage !== 'result' || (event.value === 'focus' && state.feedback === 'unknown')) break;
      state.stage = 'practice';
      state.range = event.value === 'focus' ? [9, 12] : [1, totalMeasures];
      state.measure = state.range[0];
      state.spread = spreadForMeasure(state.measure);
      state.loop = false;
      state.paused = true;
      break;
    case 'continue':
      if (stage !== 'result') break;
      state.stage = 'practice';
      state.measure = state.measure < totalMeasures ? state.measure + 1 : 1;
      state.range = [state.measure, totalMeasures];
      state.spread = spreadForMeasure(state.measure);
      state.loop = false;
      state.paused = true;
      break;
    case 'return':
      if (state.session) {
        if (!['practice', 'result', 'save-error', 'relocalize', 'suspended', 'settings'].includes(stage)) break;
        state.destination = event.value === '2d' ? 'entry' : event.value === 'entry' ? 'entry' : 'library';
        if (stage === 'practice' || stage === 'result') state.resumeStage = stage;
        state.stage = 'saving';
        state.progressSaved = false;
        state.factsSaved = false;
        stop();
        state.editing = false;
      } else if (['library', 'detail', 'empty', 'library-error'].includes(stage)) {
        state.destination = event.value === '2d' || event.value === 'entry' ? 'entry' : 'library';
        leave();
      }
      break;
    case 'progress-saved':
      if (stage !== 'saving') break;
      if (event.ok === false) {
        state.stage = 'save-error';
        state.message = '练习进度保存失败。仍保留当前书与未保存部分。';
      } else {
        state.progressSaved = true;
        state.savedMeasure = state.measure;
      }
      break;
    case 'facts-saved':
      if (stage !== 'saving' || !state.progressSaved) break;
      if (event.ok === false) {
        state.stage = 'save-error';
        state.message = '会话事实保存失败。已保存进度保留，其余部分仍在。';
      } else {
        state.factsSaved = true;
        leave();
      }
      break;
    case 'retry-save':
      if (stage === 'save-error') {
        state.stage = 'saving';
        state.message = '';
      }
      break;
    case 'stay':
      if (stage === 'save-error') {
        state.stage = state.resumeStage;
        state.paused = true;
        state.message = '';
      }
      break;
    case 'discard':
      if (stage === 'save-error') state.stage = 'discard-confirm';
      break;
    case 'discard-confirm':
      if (stage === 'discard-confirm') leave();
      break;
    case 'tracking-lost':
      if (!state.session || !['practice', 'result', 'handoff', 'settings'].includes(stage)) break;
      state.resumeStage = stage === 'result' ? 'result' : 'practice';
      state.stage = 'relocalize';
      state.ready = false;
      stop();
      state.editing = false;
      break;
    case 'relocalized':
      if (stage !== 'relocalize') break;
      if (event.ok === false) state.message = '仍无法确认钢琴位置，请重试；尚未恢复播放。';
      else {
        state.stage = state.resumeStage;
        state.ready = true;
        state.paused = true;
        state.message = '';
      }
      break;
    case 'suspend':
      if (!state.session || !['practice', 'result', 'settings', 'relocalize'].includes(stage)) break;
      if (stage === 'practice' || stage === 'result') state.resumeStage = stage;
      state.stage = 'suspended';
      state.ready = false;
      stop();
      state.editing = false;
      break;
    case 'resume':
      if (stage === 'suspended') state.stage = 'relocalize';
      break;
    case 'settings':
      if (stage === 'practice') {
        state.stage = 'settings';
        stop();
      } else if (stage === 'settings') state.stage = 'practice';
      break;
    case 'manage':
      if (!state.session && ['library', 'empty', 'library-error'].includes(stage)) {
        state.stage = 'manager';
        stop();
      }
      break;
    case 'managed':
      if (stage === 'manager') state.stage = 'entry';
      break;
    case 'library-case':
      if (stage === 'library') state.stage = event.value;
      break;
    case 'retry-library':
      if (['empty', 'library-error'].includes(stage)) state.stage = 'library';
      break;
  }

  return state;
}
