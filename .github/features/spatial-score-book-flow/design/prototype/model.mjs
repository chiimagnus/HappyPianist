export const songs = [
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
export const boards = [
  ['D01', '进入与返回'], ['D02', '空间曲库'], ['D03', '展开与详情'],
  ['D04', '翻页与末页'], ['D05', '准备与校准'], ['D06', '移琴与谱位'],
  ['D07', '练习与反馈'], ['D08', '示范与陪弹'], ['D09', '结果与复测'],
  ['D10', '保存与中断'],
];

export function initialState() {
  return {
    stage: 'entry', selected: 2, spread: 0, measure: 1, input: 'audio',
    ready: false, usingStored: false, session: false, paused: true, dirty: false,
    progressSaved: false, factsSaved: false, savedMeasure: 0,
    controls: false, recording: false, metronome: false, companion: 'off',
    yielding: false, guide: true, audition: false, loop: false,
    range: [1, totalMeasures], teachingBeat: 0, feedback: 'observed',
    offset: [0, 0, 0], editing: false, editStart: [0, 0, 0],
    destination: 'library', resumeStage: 'practice', fault: '', message: '',
    search: '', reduced: false, largeText: false,
  };
}

export function spreadForMeasure(measure) {
  return Math.floor((Math.min(totalMeasures, Math.max(1, measure)) - 1) / 16);
}

export function transition(previous, event) {
  const state = structuredClone(previous);
  const stage = state.stage;
  const fail = (fault) => {
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
      if (!['entry', 'entry-error'].includes(stage)) break;
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
      if (!['permission', 'midi'].includes(stage)) break;
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
      if (['a0', 'c8', 'ready'].includes(stage)) { state.stage = 'a0'; state.ready = false; state.message = ''; }
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
      if (['practice', 'result'].includes(stage)) state.controls = !state.controls;
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
      if (['practice', 'result'].includes(stage) && ['observed', 'unknown'].includes(event.value)) state.feedback = event.value;
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
        if (!['practice', 'result', 'save-error', 'relocalize', 'suspended', 'settings'].includes(stage)) break;
        state.destination = event.value === '2d' ? 'entry' : event.value;
        state.resumeStage = ['practice', 'result'].includes(stage) ? stage : state.resumeStage;
        state.stage = 'saving';
        state.progressSaved = false;
        state.factsSaved = false;
        stop();
        state.editing = false;
      } else if (['library', 'detail', 'empty', 'library-error'].includes(stage)) {
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
      if (!state.session || !['practice', 'result', 'handoff', 'settings'].includes(stage)) break;
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
      if (!state.session || !['practice', 'result', 'settings', 'relocalize'].includes(stage)) break;
      if (['practice', 'result'].includes(stage)) state.resumeStage = stage;
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
      if (!state.session && ['library', 'empty', 'library-error'].includes(stage)) { state.stage = 'manager'; stop(); }
      break;
    case 'managed':
      if (stage === 'manager') state.stage = 'entry';
      break;
    case 'library-case':
      if (stage === 'library' && ['empty', 'library-error'].includes(event.value)) state.stage = event.value;
      break;
    case 'retry-library':
      if (['empty', 'library-error'].includes(stage)) state.stage = 'library';
      break;
    case 'reduced':
      state.reduced = Boolean(event.value);
      break;
    case 'large-text':
      state.largeText = Boolean(event.value);
      break;
  }
  return state;
}

export function boardState(id) {
  let state = initialState();
  if (id === 'D01') return state;
  for (const event of [{ type: 'enter' }, { type: 'placed' }]) state = transition(state, event);
  if (id === 'D02') return state;
  for (const event of [{ type: 'open' }, { type: 'loaded' }]) state = transition(state, event);
  if (id === 'D03') return state;
  if (id === 'D04') return transition(state, { type: 'page', value: 1 });
  state = transition(state, { type: 'start' });
  if (id === 'D05') return state;
  for (const event of [{ type: 'input', value: 'audio' }, { type: 'connect' }, { type: 'calibrate' }, { type: 'calibrate' }, { type: 'confirm' }, { type: 'arrived' }]) state = transition(state, event);
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
