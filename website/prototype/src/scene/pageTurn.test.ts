import assert from 'node:assert/strict';
import { test } from 'node:test';
import { pageTurnPages } from './pageTurn.ts';

test('向前翻页保留旧左页、露出新右页并给叶片正确正反面', () => {
  assert.deepEqual(pageTurnPages(0, 1), {
    direction: 1,
    left: 1,
    right: 4,
    leafFront: 2,
    leafBack: 3,
  });
});

test('向后翻页保留旧右页、露出新左页并反向旋转叶片', () => {
  assert.deepEqual(pageTurnPages(1, 0), {
    direction: -1,
    left: 1,
    right: 4,
    leafFront: 2,
    leafBack: 3,
  });
});

test('快速重定向时页面映射直接服从最新 reducer 目标', () => {
  assert.deepEqual(pageTurnPages(1, 2), {
    direction: 1,
    left: 3,
    right: 6,
    leafFront: 4,
    leafBack: 5,
  });
});
