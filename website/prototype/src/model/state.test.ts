import assert from 'node:assert/strict';
import { test } from 'node:test';
import { boardState } from '../dev/fixtures.ts';
import { songs } from './data.ts';
import {
  initialState,
  spreadForMeasure,
  transition,
  type PrototypeEvent,
  type PrototypeState,
} from './state.ts';

function run(state: PrototypeState, ...events: PrototypeEvent[]): PrototypeState {
  return events.reduce(transition, state);
}

test('未 ready 和非活动阶段不能开始，原状态不被修改', () => {
  const state = initialState();
  assert.deepEqual(run(state, { type: 'confirm' }, { type: 'play' }, { type: 'tick' }), state);
  const next = transition(state, { type: 'enter' });
  assert.equal(state.stage, 'entry');
  assert.equal(next.stage, 'opening');
});

test('取消打开或加载以后，迟到完成不能打开旧场景', () => {
  assert.equal(run(initialState(), { type: 'enter' }, { type: 'cancel' }, { type: 'placed' }).stage, 'entry');
  assert.equal(run(boardState('D02'), { type: 'open' }, { type: 'cancel' }, { type: 'loaded' }).stage, 'library');
});

test('资源占用拒绝进入，失败后可以重试', () => {
  let state = transition(initialState(), { type: 'enter', ok: false });
  assert.equal(state.stage, 'entry-error');
  state = run(state, { type: 'enter' }, { type: 'placed', ok: false });
  assert.equal(state.stage, 'entry-error');
  assert.equal(run(state, { type: 'enter' }, { type: 'placed' }).stage, 'library');
});

test('选书有边界，详情拒绝换曲，选择不自动试听', () => {
  let state = boardState('D02');
  for (const value of [-1, songs.length, NaN, 1.5]) assert.equal(transition(state, { type: 'select', value }).selected, 2);
  state = transition(state, { type: 'select', value: 5 });
  assert.equal(state.audition, false);
  state = run(state, { type: 'open' }, { type: 'loaded' }, { type: 'select', value: 1 });
  assert.equal(state.selected, 5);
});

test('双页边界含奇数末页，自动页跟随真实模拟位置而不是独立页时钟', () => {
  let state = boardState('D03');
  state = run(state, { type: 'page', value: 99 }, { type: 'page', value: 1 });
  assert.equal(state.spread, 2);
  assert.equal(transition(state, { type: 'page', value: -99 }).spread, 0);
  assert.deepEqual([1, 16, 17, 32, 33, 40].map(spreadForMeasure), [0, 0, 1, 1, 2, 2]);
  state = run(boardState('D07'), { type: 'seek', value: 16 }, { type: 'play' }, { type: 'tick' });
  assert.equal(state.measure, 17);
  assert.equal(state.spread, 1);
  assert.equal(transition(state, { type: 'page', value: 1 }).spread, 1);
});

test('权限、MIDI 与错误校准保留现场；Ready 前不能确认', () => {
  for (const [input, stage] of [['audio', 'permission'], ['midi', 'midi']] as const) {
    let state = run(boardState('D05'), { type: 'input', value: input }, { type: 'connect', ok: false });
    assert.equal(state.stage, stage);
    assert.equal(transition(state, { type: 'confirm' }).session, false);
    state = run(state, { type: 'connect' }, { type: 'calibrate' }, { type: 'calibrate', ok: false });
    assert.equal(state.stage, 'c8');
    assert.equal(state.ready, false);
    state = transition(state, { type: 'calibrate' });
    assert.equal(state.stage, 'ready');
    assert.equal(state.ready, true);
  }
});

test('已有校准仍需重新定位，取消准备回同一书', () => {
  const permission = transition(boardState('D05'), { type: 'restore' });
  assert.equal(permission.stage, 'permission');
  assert.equal(permission.ready, false);
  const denied = transition(permission, { type: 'connect', ok: false });
  assert.equal(denied.stage, 'permission');
  const state = transition(permission, { type: 'connect' });
  assert.equal(state.stage, 'relocalize');
  assert.equal(state.ready, false);
  const ready = transition(state, { type: 'relocalized' });
  assert.equal(ready.stage, 'ready');
  assert.equal(transition(boardState('D05'), { type: 'cancel' }).stage, 'detail');
});

test('暂停、编辑、后台、定位丢失时 tick 不改变进度；恢复不自动播放', () => {
  for (const event of [{ type: 'play' }, { type: 'edit' }, { type: 'suspend' }, { type: 'tracking-lost' }] as const) {
    const stopped = transition(boardState('D07'), event);
    assert.equal(transition(stopped, { type: 'tick' }).measure, stopped.measure);
  }
  const state = run(boardState('D07'), { type: 'tick' }, { type: 'suspend' }, { type: 'resume' }, { type: 'relocalized' });
  assert.equal(state.stage, 'practice');
  assert.equal(state.measure, 2);
  assert.equal(state.paused, true);
  assert.equal(state.session, true);
});

test('谱位偏移有界且取消恢复；范围循环与 seek 同步页码', () => {
  const start = boardState('D06');
  const moved = run(start, { type: 'move', axis: 0, value: 10 }, { type: 'move', axis: 1, value: -10 });
  assert.deepEqual(moved.offset, [0.12, -0.12, 0]);
  assert.deepEqual(transition(moved, { type: 'edit-done', cancel: true }).offset, [0, 0, 0]);
  const state = run(boardState('D07'), { type: 'loop' }, { type: 'seek', value: 16 }, { type: 'play' }, { type: 'tick' });
  assert.equal(state.measure, 9);
  assert.equal(state.stage, 'practice');
  assert.deepEqual(state.range, [9, 16]);
});

test('一次示范自动结束；示范和陪弹只有一个模式，失败保留 Guide', () => {
  let state = transition(boardState('D08'), { type: 'companion', value: 'teaching' });
  for (let beat = 0; beat < 4; beat += 1) state = transition(state, { type: 'tick' });
  assert.equal(state.companion, 'off');
  assert.equal(state.paused, true);
  state = transition(boardState('D07'), { type: 'companion', value: 'teaching', failure: 'rig' });
  assert.equal(state.companion, 'off');
  assert.equal(state.guide, true);
  state = transition(boardState('D07'), { type: 'companion', value: 'duet', failure: 'ai' });
  assert.equal(state.companion, 'off');
  assert.match(state.message, /未切换/);
});

test('unknown 不生成建议；复测真实改变范围、位置和页', () => {
  const unknown = transition(boardState('D09'), { type: 'feedback', value: 'unknown' });
  assert.equal(transition(unknown, { type: 'retest', value: 'focus' }).stage, 'result');
  assert.equal(transition(unknown, { type: 'retest', value: 'all' }).stage, 'practice');
  const retest = transition(boardState('D09'), { type: 'retest', value: 'focus' });
  assert.equal(retest.stage, 'practice');
  assert.deepEqual(retest.range, [9, 12]);
  assert.equal(retest.measure, 9);
});

test('两段保存都成功才离开；失败保留 session 和增量，重复完成无效', () => {
  for (const failure of ['progress', 'facts'] as const) {
    let state = transition(boardState('D09'), { type: 'return', value: 'library' });
    assert.equal(transition(state, { type: 'facts-saved' }).stage, 'saving');
    state = failure === 'progress'
      ? transition(state, { type: 'progress-saved', ok: false })
      : run(state, { type: 'progress-saved' }, { type: 'facts-saved', ok: false });
    assert.equal(state.stage, 'save-error');
    assert.equal(state.session, true);
    assert.equal(state.dirty, true);
    state = run(state, { type: 'retry-save' }, { type: 'progress-saved' }, { type: 'facts-saved' });
    assert.equal(state.stage, 'library');
    assert.equal(state.session, false);
    assert.equal(state.factsSaved, true);
    assert.equal(transition(state, { type: 'facts-saved' }).stage, 'library');
  }
});

test('放弃必须二次确认，不删除已保存进度；留在现场仍可重试', () => {
  const state = boardState('D10');
  assert.equal(state.progressSaved, true);
  assert.equal(transition(state, { type: 'discard-confirm' }).stage, 'save-error');
  const discard = run(state, { type: 'discard' }, { type: 'discard-confirm' });
  assert.equal(discard.stage, 'library');
  assert.equal(discard.savedMeasure, state.savedMeasure);
  assert.equal(run(state, { type: 'discard' }, { type: 'cancel' }).stage, 'save-error');
  assert.equal(transition(state, { type: 'stay' }).stage, 'result');
});

test('管理不是新会话；保存退 2D 恢复原选择；练习不能直接管理', () => {
  assert.equal(transition(boardState('D07'), { type: 'manage' }).stage, 'practice');
  assert.equal(run(boardState('D02'), { type: 'manage' }, { type: 'managed' }).stage, 'entry');
  const state = run(boardState('D09'), { type: 'return', value: '2d' }, { type: 'progress-saved' }, { type: 'facts-saved' });
  assert.equal(state.stage, 'entry');
  assert.equal(state.selected, 2);
  assert.equal(state.recording, false);
});

test('保存期间重复返回不改变目标；恢复校准可取消；伙伴与录音互斥', () => {
  const saving = run(boardState('D09'), { type: 'return', value: 'library' }, { type: 'return', value: '2d' });
  assert.equal(saving.destination, 'library');
  assert.equal(run(boardState('D05'), { type: 'restore' }, { type: 'cancel' }).stage, 'detail');
  assert.equal(transition(boardState('D08'), { type: 'record' }).recording, false);
});

test('建议范围完成后继续后续小节，完整结束后可从头继续', () => {
  let state = run(boardState('D09'), { type: 'retest', value: 'focus' }, { type: 'play' });
  for (let beat = 0; beat < 4; beat += 1) state = transition(state, { type: 'tick' });
  assert.equal(state.stage, 'result');
  state = transition(state, { type: 'continue' });
  assert.equal(state.stage, 'practice');
  assert.equal(state.measure, 13);
  assert.deepEqual(state.range, [13, 40]);
  state = run(state, { type: 'seek', value: 40 }, { type: 'play' }, { type: 'tick' }, { type: 'continue' });
  assert.equal(state.measure, 1);
  assert.equal(state.paused, true);
});
