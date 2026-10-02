export interface Song {
  title: string;
  composer: string;
  tint: string;
}

export type Stage =
  | 'entry'
  | 'entry-error'
  | 'opening'
  | 'library'
  | 'empty'
  | 'library-error'
  | 'loading'
  | 'detail-error'
  | 'detail'
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

export type InputMethod = 'audio' | 'midi';
export type CompanionMode = 'off' | 'teaching' | 'duet';
export type FeedbackMode = 'observed' | 'unknown';
export type StartMode = 'begin' | 'resume' | 'focus';
export type RetestMode = 'focus' | 'all';
export type Destination = 'entry' | 'library';
export type ResumeStage = 'practice' | 'result' | 'ready';
export type FaultCase =
  | 'entry'
  | 'busy'
  | 'empty'
  | 'library-error'
  | 'score'
  | 'permission'
  | 'midi'
  | 'calibration'
  | 'tracking'
  | 'rig'
  | 'ai'
  | 'unknown'
  | 'progress'
  | 'facts'
  | 'suspend';

export interface PrototypeState {
  stage: Stage;
  selected: number;
  spread: number;
  measure: number;
  input: InputMethod;
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
  range: [number, number];
  teachingBeat: number;
  feedback: FeedbackMode;
  offset: [number, number, number];
  editing: boolean;
  editStart: [number, number, number];
  destination: Destination;
  resumeStage: ResumeStage;
  fault: FaultCase | '';
  message: string;
  search: string;
}

export type PrototypeEvent =
  | { type: 'fault'; value: FaultCase }
  | { type: 'enter' }
  | { type: 'placed' }
  | { type: 'cancel' }
  | { type: 'select'; value: number }
  | { type: 'search'; value: string }
  | { type: 'listen' }
  | { type: 'open' }
  | { type: 'loaded' }
  | { type: 'page'; value: number }
  | { type: 'start'; value?: StartMode }
  | { type: 'input'; value: InputMethod }
  | { type: 'connect' }
  | { type: 'calibrate' }
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
  | { type: 'companion'; value: CompanionMode }
  | { type: 'yield' }
  | { type: 'feedback'; value: FeedbackMode }
  | { type: 'edit' }
  | { type: 'move'; axis: number; value: number }
  | { type: 'reset-position' }
  | { type: 'edit-done'; cancel?: boolean }
  | { type: 'retest'; value: RetestMode }
  | { type: 'continue' }
  | { type: 'return'; value: 'entry' | '2d' | 'library' }
  | { type: 'progress-saved' }
  | { type: 'facts-saved' }
  | { type: 'retry-save' }
  | { type: 'stay' }
  | { type: 'discard' }
  | { type: 'discard-confirm' }
  | { type: 'tracking-lost' }
  | { type: 'relocalized' }
  | { type: 'suspend' }
  | { type: 'resume' }
  | { type: 'settings' }
  | { type: 'manage' }
  | { type: 'managed' }
  | { type: 'library-case'; value: 'empty' | 'library-error' }
  | { type: 'retry-library' };

export const songs: readonly Song[] = [
  { title: 'Moonlight Sonata', composer: 'Ludwig van Beethoven', tint: '#72819a' },
  { title: 'Nocturne', composer: 'Frédéric Chopin', tint: '#687c83' },
  { title: 'Clair de Lune', composer: 'Claude Debussy', tint: '#9c9cab' },
  { title: 'Arabesque', composer: 'Claude Debussy', tint: '#8c9c80' },
  { title: 'Kinderszenen', composer: 'Robert Schumann', tint: '#b39378' },
  { title: 'Impromptu', composer: 'Franz Schubert', tint: '#8a8d9c' },
  { title: 'Gymnopédie', composer: 'Erik Satie', tint: '#97a8a4' },
];

export const pageCount = 5;
export const totalMeasures = 40;
export function initialState(): PrototypeState {
  return {
    stage: 'entry', selected: 2, spread: 0, measure: 1, input: 'audio',
    ready: false, usingStored: false, session: false, paused: true, dirty: false,
    progressSaved: false, factsSaved: false, savedMeasure: 0,
    controls: false, recording: false, metronome: false, companion: 'off',
    yielding: false, guide: true, audition: false, loop: false,
    range: [1, totalMeasures], teachingBeat: 0, feedback: 'observed',
    offset: [0, 0, 0], editing: false, editStart: [0, 0, 0],
    destination: 'library', resumeStage: 'practice', fault: '', message: '',
    search: '',
  };
}

export function spreadForMeasure(measure: number): number {
  return Math.floor((Math.min(totalMeasures, Math.max(1, measure)) - 1) / 16);
}

function oneOf<T>(value: T, values: readonly T[]): boolean {
  return values.includes(value);
}

export function transition(previous: PrototypeState, event: PrototypeEvent): PrototypeState {
  const state = structuredClone(previous);
  const stage = state.stage;
  const fail = (fault: FaultCase) => {
    if (state.fault !== fault) return false;
    state.fault = '';
    return true;
  };
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
    case 'fault':
      state.fault = event.value;
      break;
    case 'enter':
      if (!oneOf(stage, ['entry', 'entry-error'])) break;
      if (fail('busy')) {
        state.stage = 'entry-error';
        state.message = '原练习或导入仍在使用资源，请先结束。';
      } else {
        state.stage = 'opening';
        state.message = '';
      }
      break;
    case 'placed':
      if (stage !== 'opening') break;
      state.stage = fail('entry') ? 'entry-error' : 'library';
      state.message = state.stage === 'entry-error' ? '空间摆放未成功。原二维曲库仍保留。' : '';
      break;
    case 'cancel':
      if (oneOf(stage, ['opening', 'entry-error'])) state.stage = 'entry';
      else if (oneOf(stage, ['loading', 'detail-error'])) state.stage = 'library';
      else if (oneOf(stage, ['input', 'permission', 'midi', 'a0', 'c8', 'ready'])) {
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
      if (oneOf(stage, ['library', 'detail'])) state.audition = !state.audition;
      break;
    case 'open':
      if (!oneOf(stage, ['library', 'detail-error'])) break;
      state.stage = 'loading';
      state.spread = 0;
      state.audition = false;
      state.message = '';
      break;
    case 'loaded':
      if (stage !== 'loading') break;
      state.stage = fail('score') ? 'detail-error' : 'detail';
      break;
    case 'page':
      if (stage === 'detail' && Number.isInteger(event.value)) {
        state.spread = Math.max(0, Math.min(Math.ceil(pageCount / 2) - 1, state.spread + event.value));
      }
      break;
    case 'start':
      if (stage !== 'detail') break;
      state.stage = 'input';
      state.measure = event.value === 'resume' ? 9 : event.value === 'focus' ? 9 : 1;
      state.range = event.value === 'focus' ? [9, 12] : [1, totalMeasures];
      state.spread = spreadForMeasure(state.measure);
      state.audition = false;
      state.usingStored = false;
      break;
    case 'input':
      if (stage !== 'input' || !['audio', 'midi'].includes(event.value)) break;
      state.input = event.value;
      state.stage = event.value === 'audio' ? 'permission' : 'midi';
      break;
    case 'connect':
      if (!oneOf(stage, ['permission', 'midi'])) break;
      if (fail(stage === 'permission' ? 'permission' : 'midi')) state.message = stage === 'permission' ? '权限未允许，尚未开始练习。' : '设备未连接，尚未开始练习。';
      else {
        state.stage = state.usingStored ? 'relocalize' : 'a0';
        if (state.usingStored) state.resumeStage = 'ready';
        state.message = '';
      }
      break;
    case 'calibrate':
      if (stage === 'a0') state.stage = 'c8';
      else if (stage === 'c8') {
        if (fail('calibration')) state.message = '两端距离或演奏侧无效，请重做定位。';
        else { state.stage = 'ready'; state.ready = true; state.message = ''; }
      }
      break;
    case 'recalibrate':
      if (oneOf(stage, ['a0', 'c8', 'ready'])) { state.stage = 'a0'; state.ready = false; state.message = ''; }
      break;
    case 'restore':
      if (stage === 'input') { state.usingStored = true; state.stage = 'permission'; state.input = 'audio'; state.ready = false; }
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
      if (stage === 'handoff') { state.stage = 'practice'; state.paused = true; }
      break;
    case 'play':
      if (stage === 'practice' && state.ready && !state.editing) state.paused = !state.paused;
      break;
    case 'tick':
      if (stage !== 'practice' || state.paused || state.editing || !state.ready) break;
      state.dirty = true;
      if (state.companion === 'teaching') {
        state.teachingBeat += 1;
        if (state.teachingBeat >= 4) { state.companion = 'off'; state.paused = true; }
      } else if (state.measure < state.range[1]) state.measure += 1;
      else if (state.loop) state.measure = state.range[0];
      else { state.stage = 'result'; stop(); }
      state.spread = spreadForMeasure(state.measure);
      break;
    case 'finish':
      if (stage === 'practice') { state.stage = 'result'; state.dirty = true; stop(); }
      break;
    case 'seek':
      if (stage !== 'practice' || !Number.isFinite(event.value) || state.editing) break;
      state.measure = Math.max(state.range[0], Math.min(state.range[1], Math.round(event.value)));
      state.spread = spreadForMeasure(state.measure);
      state.companion = 'off';
      state.paused = true;
      break;
    case 'loop':
      if (stage === 'practice') { state.loop = !state.loop; state.range = state.loop ? [9, 16] : [1, totalMeasures]; state.measure = state.range[0]; state.spread = spreadForMeasure(state.measure); state.paused = true; state.companion = 'off'; }
      break;
    case 'controls':
      if (oneOf(stage, ['practice', 'result'])) state.controls = !state.controls;
      break;
    case 'record':
      if (stage === 'practice' && !state.editing && state.companion === 'off') { state.recording = !state.recording; state.dirty ||= state.recording; }
      break;
    case 'metronome':
      if (stage === 'practice') state.metronome = !state.metronome;
      break;
    case 'companion':
      if (stage !== 'practice' || !state.ready || state.editing || !['off', 'teaching', 'duet'].includes(event.value)) break;
      if (event.value === 'duet' && fail('ai')) { state.companion = 'off'; state.message = '本次陪弹失败，已停止。未切换 AI 后端。'; break; }
      state.guide = !fail('rig');
      state.companion = state.guide ? event.value : 'off';
      state.message = state.guide ? '' : '手部动作不可用，保留琴键 Guide。';
      state.guide = true;
      state.teachingBeat = 0;
      state.yielding = false;
      if (state.companion !== 'off') { state.paused = false; state.recording = false; }
      break;
    case 'yield':
      if (stage === 'practice' && state.companion === 'duet') state.yielding = !state.yielding;
      break;
    case 'feedback':
      if (oneOf(stage, ['practice', 'result']) && ['observed', 'unknown'].includes(event.value)) state.feedback = event.value;
      break;
    case 'edit':
      if (stage === 'practice') { stop(); state.editing = true; state.editStart = [...state.offset]; }
      break;
    case 'move':
      if (stage !== 'practice' || !state.editing || !Number.isInteger(event.axis) || event.axis < 0 || event.axis > 2 || !Number.isFinite(event.value)) break;
      state.offset[event.axis] = Math.max(-0.12, Math.min(0.12, state.offset[event.axis] + event.value));
      break;
    case 'reset-position':
      if (stage === 'practice' && state.editing) state.offset = [0, 0, 0];
      break;
    case 'edit-done':
      if (stage === 'practice' && state.editing) { if (event.cancel) state.offset = [...state.editStart]; state.editing = false; }
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
      if (!['entry', '2d', 'library'].includes(event.value)) break;
      if (state.session) {
        if (!oneOf(stage, ['practice', 'result', 'save-error', 'relocalize', 'suspended', 'settings'])) break;
        state.destination = event.value === '2d' ? 'entry' : event.value;
        state.resumeStage = stage === 'practice' || stage === 'result' ? stage : state.resumeStage;
        state.stage = 'saving';
        state.progressSaved = false;
        state.factsSaved = false;
        stop();
        state.editing = false;
      } else if (oneOf(stage, ['library', 'detail', 'empty', 'library-error'])) {
        state.destination = event.value === '2d' ? 'entry' : event.value;
        leave();
      }
      break;
    case 'progress-saved':
      if (stage !== 'saving') break;
      if (fail('progress')) { state.stage = 'save-error'; state.message = '练习进度保存失败。仍保留当前书与未保存部分。'; }
      else { state.progressSaved = true; state.savedMeasure = state.measure; }
      break;
    case 'facts-saved':
      if (stage !== 'saving' || !state.progressSaved) break;
      if (fail('facts')) { state.stage = 'save-error'; state.message = '会话事实保存失败。已保存进度保留，其余部分仍在。'; }
      else { state.factsSaved = true; leave(); }
      break;
    case 'retry-save':
      if (stage === 'save-error') { state.stage = 'saving'; state.message = ''; }
      break;
    case 'stay':
      if (stage === 'save-error') { state.stage = state.resumeStage; state.paused = true; state.message = ''; }
      break;
    case 'discard':
      if (stage === 'save-error') state.stage = 'discard-confirm';
      break;
    case 'discard-confirm':
      if (stage === 'discard-confirm') leave();
      break;
    case 'tracking-lost':
      if (!state.session || !oneOf(stage, ['practice', 'result', 'handoff', 'settings'])) break;
      state.resumeStage = stage === 'result' ? 'result' : 'practice';
      state.stage = 'relocalize';
      state.ready = false;
      stop();
      state.editing = false;
      break;
    case 'relocalized':
      if (stage !== 'relocalize') break;
      if (fail('tracking')) state.message = '仍无法确认钢琴位置，请重试；尚未恢复播放。';
      else { state.stage = state.resumeStage; state.ready = true; state.paused = true; state.message = ''; }
      break;
    case 'suspend':
      if (!state.session || !oneOf(stage, ['handoff', 'practice', 'result', 'settings', 'relocalize'])) break;
      if (stage === 'handoff') state.resumeStage = 'practice';
      else if (stage === 'practice' || stage === 'result') state.resumeStage = stage;
      state.stage = 'suspended';
      state.ready = false;
      stop();
      state.editing = false;
      break;
    case 'resume':
      if (stage === 'suspended') state.stage = 'relocalize';
      break;
    case 'settings':
      if (stage === 'practice') { state.stage = 'settings'; stop(); }
      else if (stage === 'settings') state.stage = 'practice';
      break;
    case 'manage':
      if (!state.session && oneOf(stage, ['library', 'empty', 'library-error'])) { state.stage = 'manager'; stop(); }
      break;
    case 'managed':
      if (stage === 'manager') state.stage = 'entry';
      break;
    case 'library-case':
      if (stage === 'library' && ['empty', 'library-error'].includes(event.value)) state.stage = event.value;
      break;
    case 'retry-library':
      if (oneOf(stage, ['empty', 'library-error'])) state.stage = 'library';
      break;
  }
  return state;
}
