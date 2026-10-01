import assert from 'node:assert/strict';
import { test } from 'node:test';
import { boardState } from '../dev/fixtures.ts';
import { songs } from '../model/data.ts';
import { transition } from '../model/state.ts';
import { BOOK_WIDTH, bookPose } from './bookPose.ts';

test('空间曲库只显示 selected ±2 并保持旧弧形关系', () => {
  const state = boardState('D02');
  const poses = songs.map((_, index) => bookPose(state, index));
  assert.equal(poses.filter((pose) => pose.visible).length, 5);
  assert.deepEqual(poses[state.selected]?.position, [-BOOK_WIDTH / 2, 1.45, 0]);
  assert.deepEqual(poses[state.selected - 1]?.position, [-0.36 - BOOK_WIDTH / 2, 1.45, -0.23]);
  assert.deepEqual(poses[state.selected + 1]?.position, [0.36 - BOOK_WIDTH / 2, 1.45, -0.23]);
});

test('详情与练习始终只保留同一本 selected book', () => {
  const detail = boardState('D03');
  const detailVisible = songs.map((_, index) => bookPose(detail, index)).filter((pose) => pose.visible);
  assert.equal(detailVisible.length, 1);
  assert.equal(bookPose(detail, detail.selected).open, true);
  assert.deepEqual(bookPose(detail, detail.selected).position, [0, 1.45, 0.08]);

  const practice = transition(boardState('D07'), { type: 'edit-done' });
  const practicePose = bookPose(practice, practice.selected);
  assert.equal(practicePose.visible, true);
  assert.equal(practicePose.open, true);
  assert.deepEqual(practicePose.position, [0, 1.24, -0.13]);
  assert.deepEqual(practicePose.rotation, [-0.13, 0, 0]);

  const moved = transition(boardState('D06'), { type: 'move', axis: 0, value: 0.02 });
  assert.deepEqual(bookPose(moved, moved.selected).position, [0.02, 1.24, -0.13]);
});
