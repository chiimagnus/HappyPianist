import assert from 'node:assert/strict';
import { test } from 'node:test';
import { CAMERA_TARGET, CAMERA_VIEWS } from './cameraViews.ts';

test('四个评审视角保持旧原型空间参数', () => {
  assert.deepEqual(CAMERA_TARGET, [0, 1.25, 0]);
  assert.deepEqual(CAMERA_VIEWS.front, [0, 1.46, 1.75]);
  assert.deepEqual(CAMERA_VIEWS.oblique, [0.85, 1.58, 1.45]);
  assert.deepEqual(CAMERA_VIEWS.side, [1.55, 1.47, 0.56]);
  assert.deepEqual(CAMERA_VIEWS.top, [0.06, 2.45, 0.95]);
});
