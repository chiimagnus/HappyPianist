import assert from 'node:assert/strict';
import { test } from 'node:test';
import { boardState } from '../dev/fixtures.ts';
import { transition } from '../model/state.ts';
import { productPlacement } from './productPlacement.ts';

test('辅助状态保留 screen DOM，空间曲库与准备绑定书册', () => {
  assert.equal(productPlacement(boardState('D01')), 'screen');
  assert.equal(productPlacement(boardState('D02')), 'book');
  assert.equal(productPlacement(boardState('D03')), 'book');
  assert.equal(productPlacement(boardState('D05')), 'book');
});

test('session 开始后产品 DOM 绑定钢琴，未建 session 的恢复定位仍绑定书册', () => {
  assert.equal(productPlacement(boardState('D07')), 'piano');
  assert.equal(productPlacement(boardState('D10')), 'piano');

  const restore = transition(boardState('D05'), { type: 'restore' });
  const relocalize = transition(transition(restore, { type: 'connect' }), { type: 'relocalized', ok: false });
  assert.equal(relocalize.session, false);
  assert.equal(productPlacement(relocalize), 'book');
});
