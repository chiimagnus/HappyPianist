import assert from 'node:assert/strict';
import { test } from 'node:test';
import { boardState } from '../dev/fixtures.ts';
import { transition } from '../model/state.ts';
import { pianoKeySpecs, pianoVisualState } from './pianoModel.ts';

test('钢琴包含完整 88 键并保持 52 白键 36 黑键', () => {
  const keys = pianoKeySpecs();
  assert.equal(keys.length, 88);
  assert.equal(keys.filter((key) => !key.black).length, 52);
  assert.equal(keys.filter((key) => key.black).length, 36);
  assert.equal(keys[0]?.pitch, 21);
  assert.equal(keys.at(-1)?.pitch, 108);
});

test('A0/C8 定位标记只在对应校准阶段出现', () => {
  let state = transition(boardState('D05'), { type: 'input', value: 'audio' });
  state = transition(state, { type: 'connect' });
  assert.deepEqual(pianoVisualState(state, false), {
    pianoVisible: true,
    a0Visible: true,
    c8Visible: false,
    companionVisible: false,
    guideVisible: false,
  });

  state = transition(state, { type: 'calibrate' });
  assert.equal(pianoVisualState(state, false).a0Visible, false);
  assert.equal(pianoVisualState(state, false).c8Visible, true);

  state = transition(state, { type: 'calibrate' });
  assert.equal(pianoVisualState(state, false).a0Visible, true);
  assert.equal(pianoVisualState(state, false).c8Visible, true);
});

test('伙伴手、Guide 与 reduced motion 遵守练习状态', () => {
  const practice = boardState('D07');
  assert.equal(pianoVisualState(practice, false).guideVisible, true);
  assert.equal(pianoVisualState(practice, false).companionVisible, false);

  const duet = boardState('D08');
  assert.equal(pianoVisualState(duet, false).companionVisible, true);
  assert.equal(pianoVisualState(duet, false).guideVisible, false);
  assert.equal(pianoVisualState(duet, true).companionVisible, true);
  assert.equal(pianoVisualState(duet, true).guideVisible, true);

  const yielding = transition(duet, { type: 'yield' });
  assert.equal(pianoVisualState(yielding, false).companionVisible, false);
  assert.equal(pianoVisualState(yielding, false).guideVisible, true);

  assert.equal(pianoVisualState(boardState('D06'), false).guideVisible, false);
  assert.equal(pianoVisualState(boardState('D01'), false).pianoVisible, false);
});
