import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const smokeOnly = process.argv.includes('--smoke');
const root = dirname(fileURLToPath(import.meta.url));
const cli = join(process.env.CODEX_HOME || join(homedir(), '.codex'), 'skills/automation/web-access/scripts/helium-remote.mjs');
const url = 'http://127.0.0.1:8765/prototype/?review=automated';
const created = JSON.parse(execFileSync(process.execPath, [cli, 'new', url], { encoding: 'utf8' }));
const targets = await (await fetch('http://127.0.0.1:9222/json/list')).json();
const target = targets.find(item => item.id === created.targetId);
assert.equal(target.url, url);
const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { socket.addEventListener('open', resolve, { once: true }); socket.addEventListener('error', reject, { once: true }); });
const pending = new Map();
let serial = 0;
const failures = [];
const checks = [];
socket.addEventListener('message', event => {
  const reply = JSON.parse(event.data);
  const request = pending.get(reply.id);
  if (request) {
    clearTimeout(request.timer);
    pending.delete(reply.id);
    if (reply.error) request.reject(new Error(reply.error.message));
    else request.resolve(reply.result);
  }
  if (reply.method === 'Runtime.exceptionThrown') failures.push(reply.params.exceptionDetails.text);
});
function send(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++serial;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`${method} timed out`)); }, 10000);
    pending.set(id, { resolve, reject, timer });
    socket.send(JSON.stringify({ id, method, params }));
  });
}
async function evaluate(expression) {
  const response = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true, userGesture: true });
  if (response.exceptionDetails) throw new Error(response.exceptionDetails.exception?.description || response.exceptionDetails.text);
  return response.result.value;
}
const wait = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const snapshot = () => evaluate('prototypeReview.snapshot()');
async function click(type, value) {
  const selector = `[data-action="${type}"]${value === undefined ? '' : `[data-value="${value}"]`}`;
  await wait(120);
  const observation = await evaluate(`(() => { const element = document.querySelector(${JSON.stringify(selector)}); return element ? { disabled:element.disabled, text:element.innerText, rect:element.getBoundingClientRect().toJSON() } : null; })()`);
  assert.ok(observation, `missing button ${selector}`);
  assert.equal(observation.disabled, false, `${selector} disabled`);
  const x = observation.rect.x + observation.rect.width / 2;
  const y = observation.rect.y + observation.rect.height / 2;
  assert.ok(observation.rect.width > 0 && observation.rect.height > 0, `${selector} hidden`);
  assert.ok(await evaluate(`document.querySelector(${JSON.stringify(selector)}).contains(document.elementFromPoint(${x}, ${y}))`), `${selector} blocked at ${x},${y}`);
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
}
async function stage(expected) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) { const state = await snapshot(); if (state.stage === expected) return state; await wait(60); }
  assert.equal((await snapshot()).stage, expected);
}
async function board(id) {
  await evaluate(`prototypeReview.loadBoard(${JSON.stringify(id)}); document.querySelector('#review').open = false; prototypeReview.setView('front'); true`);
  await wait(800);
}
function checked(label) { checks.push(label); console.log(`PASS ${label}`); }
async function capture(name) {
  const response = await send('Page.captureScreenshot', { format: 'png' });
  writeFileSync(join(root, '../boards', `${name}.png`), Buffer.from(response.data, 'base64'));
}

try {
  await send('Runtime.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 960, deviceScaleFactor: 1, mobile: false });
  await send('Emulation.setFocusEmulationEnabled', { enabled: true });
  await evaluate('new Promise(resolve => { const poll = () => window.prototypeReview ? resolve(true) : setTimeout(poll, 50); poll(); })');
  await wait(300);
  assert.equal(await evaluate('document.hidden'), false);
  await board('D01');
  await click('enter');
  await stage('library');
  assert.ok((await snapshot()).meshes > 10);
  assert.equal((await snapshot()).visibleBooks, 5);
  const bookID = (await snapshot()).selectedBookUUID;
  const center = (await snapshot()).selectedBookScreen;
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x: center[0], y: center[1], button: 'left', clickCount: 1 });
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: center[0], y: center[1], button: 'left', clickCount: 1 });
  await stage('detail');
  await click('start', 'begin');
  await click('input', 'audio');
  await click('connect');
  await click('calibrate');
  await click('calibrate');
  assert.equal((await snapshot()).stage, 'ready');
  await click('confirm');
  await stage('practice');
  assert.equal((await snapshot()).selectedBookUUID, bookID);
  assert.equal((await snapshot()).paused, true);
  await click('play');
  await wait(1750);
  assert.ok((await snapshot()).measure > 1);
  await click('play');
  const pausedMeasure = (await snapshot()).measure;
  await wait(1700);
  assert.equal((await snapshot()).measure, pausedMeasure);
  await click('controls');
  await click('finish');
  await click('return', 'library');
  await stage('library');
  const saved = await snapshot();
  assert.equal(saved.progressSaved, true);
  assert.equal(saved.factsSaved, true);
  assert.equal(saved.session, false);
  await click('return', '2d');
  await stage('entry');
  checked('D01–D10 主路径：真实 canvas 命中、校准门禁、同书身份、暂停与两段保存返回');
  assert.equal((await snapshot()).renderError, '');
  assert.deepEqual(failures, []);
  if (smokeOnly) process.exitCode = 0;
  else {
    mkdirSync(join(root, '../boards'), { recursive: true });
    for (let number = 1; number <= 10; number += 1) {
      const id = `D${String(number).padStart(2, '0')}`;
      await board(id);
      assert.ok(await evaluate('document.querySelectorAll("#actions button").length > 0'));
      await capture(id);
    }
    checked('D01–D10 每板有实际可操作控件并捕获运行图');
    await board('D01');
    await click('enter');
    await wait(200);
    await capture('D01-opening');
    await stage('library');
    await click('open');
    await stage('detail');
    await wait(150);
    await capture('D03-opening');
    await wait(400);
    await capture('D03-opening-wide');
    await wait(400);
    const continuousID = (await snapshot()).selectedBookUUID;
    await click('start', 'begin');
    await click('input', 'audio');
    await click('connect');
    await wait(100);
    await capture('D05-a0');
    await click('calibrate');
    await wait(100);
    await capture('D05-c8');
    await click('calibrate');
    await wait(100);
    await capture('D05-ready');
    await click('confirm');
    await wait(80);
    await capture('D06-depart');
    await wait(260);
    await capture('D06-handoff');
    await stage('practice');
    await wait(300);
    await capture('D06-arrived');
    assert.equal((await snapshot()).selectedBookUUID, continuousID);
    assert.equal((await snapshot()).keyboardKeyCount, 88);
    assert.equal((await snapshot()).companionHandCount, 2);
    checked('展开与移琴分镜保留同书身份；88 键占位与唯一一双伙伴手');
    await board('D02');
    await wait(500);
    const fixedPosition = (await snapshot()).bookPosition;
    const fixedControls = (await snapshot()).controlsWorldMatrix;
    const frontWidth = await evaluate("document.querySelector('#spatial-operations').getBoundingClientRect().width");
    assert.equal(await evaluate("document.querySelector('#review-explanation').contains(document.querySelector('#product')) && !document.querySelector('#review').open"), true);
    assert.equal(await evaluate("document.querySelector('#spatial-status').innerText"), '');
    for (const view of ['oblique', 'side', 'top']) {
      await evaluate(`prototypeReview.setView('${view}')`);
      await wait(300);
      assert.ok((await snapshot()).bookPosition.every((position, index) => Math.abs(position - fixedPosition[index]) < 0.0001));
      assert.ok((await snapshot()).controlsWorldMatrix.every((position, index) => Math.abs(position - fixedControls[index]) < 0.0001));
      if (view === 'side') assert.ok(await evaluate("document.querySelector('#spatial-operations').getBoundingClientRect().width") < frontWidth * 0.7);
      await capture(`D02-${view}`);
    }
    checked('曲名只在书上；无重复信息卡；控件固定于书册而非朝向镜头');
    await evaluate("prototypeReview.setView('front')");
    await click('select', 3);
    await click('select', 4);
    await click('select', 5);
    await wait(600);
    assert.equal((await snapshot()).selected, 5);
    assert.ok((await snapshot()).visibleBooks <= 5);
    checked('独立深度 / 斜侧俯视 / 不跟头 / 快速换书收敛');
    await board('D03');
    assert.equal(await evaluate('document.querySelectorAll("#actions .row").length'), 0);
    assert.equal(await evaluate('document.querySelector("#spatial-operations").dataset.stage'), 'detail');
    const pageBounds = await evaluate('document.querySelector("#spatial-operations").getBoundingClientRect().toJSON()');
    const practiceBounds = await evaluate('document.querySelector("[data-action=start][data-value=begin]").getBoundingClientRect().toJSON()');
    assert.ok(practiceBounds.top < pageBounds.bottom && practiceBounds.bottom < pageBounds.bottom + 30);
    await click('listen');
    assert.equal((await snapshot()).audition, true);
    await click('listen');
    assert.equal((await snapshot()).audition, false);
    await click('start', 'resume');
    assert.equal((await snapshot()).measure, 9);
    await click('cancel');
    await click('start', 'focus');
    assert.deepEqual((await snapshot()).range, [9, 12]);
    await click('cancel');
    await click('return', 'library');
    await stage('library');
    checked('详情无按钮面板：书签练习、页内继续/范围、标题试听、书脊合拢均可真实点击');
    await board('D03');
    for (const view of ['oblique', 'side']) {
      await evaluate(`prototypeReview.setView('${view}')`);
      await wait(300);
      await capture(`D03-${view}`);
    }
    await board('D03');
    await click('page', 1);
    await wait(290);
    assert.equal((await snapshot()).flipping, true);
    await capture('D04-turn');
    await click('page', 1);
    await wait(100);
    assert.equal((await snapshot()).spread, 2);
    assert.equal((await snapshot()).flipping, false);
    await capture('D04-last');
    await click('page', -1);
    await wait(300);
    await capture('D04-back');
    await wait(600);
    checked('双面翻页、反向、奇数末页、翻动中最新目标收敛');
    await board('D02');
    await evaluate("document.querySelector('#search').focus(); true");
    await send('Input.insertText', { text: 'Chopin' });
    assert.equal(await evaluate("document.querySelector('#search-results').innerText"), 'Nocturne');
    assert.equal(await evaluate('document.activeElement.id'), 'search');
    await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'ArrowLeft', code: 'ArrowLeft', windowsVirtualKeyCode: 37 });
    await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'ArrowLeft', code: 'ArrowLeft', windowsVirtualKeyCode: 37 });
    assert.equal((await snapshot()).selected, 2);
    await evaluate('document.activeElement.blur(); true');
    await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'ArrowRight', code: 'ArrowRight', windowsVirtualKeyCode: 39 });
    await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'ArrowRight', code: 'ArrowRight', windowsVirtualKeyCode: 39 });
    assert.equal((await snapshot()).selected, 3);
    checked('查找、焦点保持、键盘选书、输入框不误导航');
    for (const [fault, failed, action, recovered] of [
      ['entry', 'entry-error', 'enter', 'library'], ['busy', 'entry-error', 'enter', 'library'],
      ['score', 'detail-error', 'open', 'detail'], ['permission', 'permission', 'connect', 'a0'],
      ['midi', 'midi', 'connect', 'a0'], ['calibration', 'c8', 'calibrate', 'ready'],
      ['tracking', 'relocalize', 'relocalized', 'practice'],
      ['progress', 'save-error', 'retry-save', 'library'], ['facts', 'save-error', 'retry-save', 'library'],
    ]) {
      await evaluate(`prototypeReview.injectCase('${fault}')`);
      const failedState = await stage(failed);
      await wait(150);
      if (!['progress', 'facts'].includes(fault)) await capture(`case-${fault}`);
      if (['progress', 'facts'].includes(fault)) {
        assert.equal(failedState.session, true);
        assert.equal(failedState.dirty, true);
        await capture(`D10-${fault}-failure`);
      }
      await click(action);
      await stage(recovered);
      if (fault === 'tracking') assert.equal((await snapshot()).paused, true);
      checked(`${fault} 失败保留现场，真实按钮重试恢复`);
    }
    await board('D01');
    await click('enter');
    await click('cancel');
    await wait(1000);
    assert.equal((await snapshot()).stage, 'entry');
    await board('D02');
    await click('open');
    await click('cancel');
    await wait(1000);
    assert.equal((await snapshot()).stage, 'library');
    checked('取消进入 / 加载以后无迟到完成');
    for (const fault of ['empty', 'library-error']) {
      await evaluate(`prototypeReview.injectCase('${fault}')`);
      assert.equal((await snapshot()).visibleBooks, 0);
      await wait(200);
      await capture(`case-${fault}`);
      await click('manage');
      await click('managed');
      await stage('entry');
    }
    checked('空库和读取失败无假书，明确管理往返');
    await board('D10');
    const savedBeforeDiscard = (await snapshot()).savedMeasure;
    await click('discard');
    await capture('D10-discard-confirm');
    await click('cancel');
    assert.equal((await snapshot()).stage, 'save-error');
    await click('discard');
    await click('discard-confirm');
    assert.equal((await snapshot()).stage, 'library');
    assert.equal((await snapshot()).savedMeasure, savedBeforeDiscard);
    checked('放弃二次确认，取消保留，已保存部分不删除');
    await board('D06');
    await click('move-y', 0.02);
    await click('move-y', 0.02);
    await capture('D06-moved');
    await click('edit-cancel');
    assert.deepEqual((await snapshot()).offset, [0, 0, 0]);
    assert.equal((await snapshot()).paused, true);
    await click('controls');
    await click('settings');
    assert.equal((await snapshot()).stage, 'settings');
    await click('settings');
    assert.equal((await snapshot()).session, true);
    checked('有限谱位编辑与取消，辅助设置不创建新会话');
    await board('D05');
    await click('restore');
    assert.equal((await snapshot()).stage, 'permission');
    assert.equal((await snapshot()).ready, false);
    await click('connect');
    await click('relocalized');
    assert.equal((await snapshot()).stage, 'ready');
    checked('恢复已存定位也先过权限/输入，再重新定位，不直接 ready');
    await board('D08');
    assert.equal((await snapshot()).companionVisible, true);
    assert.equal((await snapshot()).guideVisible, false);
    await click('yield');
    await wait(150);
    assert.equal((await snapshot()).companionVisible, false);
    assert.equal((await snapshot()).guideVisible, true);
    await capture('D08-yield');
    for (const fault of ['rig', 'ai']) {
      await evaluate(`prototypeReview.injectCase('${fault}')`);
      await wait(150);
      assert.equal((await snapshot()).companion, 'off');
      assert.equal((await snapshot()).guideVisible, true);
      await capture(`case-${fault}`);
    }
    checked('单一伙伴模式、陪弹退让、手/AI 失败保留 Guide');
    await board('D07');
    await click('controls');
    await click('companion', 'teaching');
    await wait(6750);
    assert.equal((await snapshot()).companion, 'off');
    assert.equal((await snapshot()).paused, true);
    checked('一次示范结束，不永久循环');
    await evaluate("prototypeReview.injectCase('unknown')");
    await click('controls');
    await click('finish');
    assert.equal(await evaluate("document.querySelector('[data-action=retest][data-value=focus]').disabled"), true);
    assert.equal(await evaluate("document.querySelector('[data-action=retest][data-value=all]').disabled"), false);
    await capture('D09-unknown');
    await board('D09');
    await click('retest', 'focus');
    assert.deepEqual((await snapshot()).range, [9, 12]);
    assert.equal((await snapshot()).measure, 9);
    await click('play');
    await wait(6550);
    await stage('result');
    await click('continue');
    assert.equal((await snapshot()).measure, 13);
    assert.deepEqual((await snapshot()).range, [13, 40]);
    checked('未知不产生错误建议，复测确实改变范围和位置');
    await evaluate("prototypeReview.injectCase('suspend')");
    const beforeResume = (await snapshot()).measure;
    await click('resume');
    await click('relocalized');
    await wait(1700);
    assert.equal((await snapshot()).measure, beforeResume);
    assert.equal((await snapshot()).paused, true);
    checked('中断与定位恢复后不自动播放');
    await board('D07');
    await click('play');
    await send('Emulation.setFocusEmulationEnabled', { enabled: false });
    assert.equal(await evaluate('document.hidden'), true);
    await stage('suspended');
    const backgroundMeasure = (await snapshot()).measure;
    await wait(1700);
    assert.equal((await snapshot()).measure, backgroundMeasure);
    await send('Emulation.setFocusEmulationEnabled', { enabled: true });
    await click('resume');
    await click('relocalized');
    assert.equal((await snapshot()).paused, true);
    checked('真实页面不可见时停止推进，回来不自动播放');
    assert.equal((await snapshot()).renderError, '');
    assert.deepEqual(failures, []);
    const userAgent = await evaluate('navigator.userAgent');
    await send('Page.navigate', { url: 'http://127.0.0.1:8765/boards/' });
    await wait(600);
    await evaluate('Promise.all([...document.images].map(image => { image.loading = "eager"; return new Promise((resolve, reject) => { if (image.complete && image.naturalWidth) resolve(); else { image.addEventListener("load", resolve, { once: true }); image.addEventListener("error", () => reject(new Error(image.src)), { once: true }); } }); }))');
    assert.equal(await evaluate('[...document.images].every(image => image.complete && image.naturalWidth > 0)'), true);
    assert.equal(await evaluate('document.querySelectorAll("section").length'), 10);
    await send('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: false });
    await wait(100);
    assert.equal(await evaluate('document.documentElement.scrollWidth <= innerWidth'), true);
    await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 960, deviceScaleFactor: 1, mobile: false });
    await evaluate('document.querySelector("a[href=\"../prototype/?board=D03\"]").click()');
    await wait(600);
    await stage('detail');
    checked('设计板图片全部加载、窄屏无横向溢出、操作链接抵达对应原型');
    assert.deepEqual(failures, []);
    const evidence = { date: new Date().toISOString(), userAgent, viewport: [1440, 960], checks, exceptions: failures, appDataAccess: false, nativeRealityViewTested: false, physicalAVPTested: false };
    writeFileSync(join(root, '../boards/browser-checks.json'), JSON.stringify(evidence, null, 2) + '\n');
    console.log(`Passed ${checks.length} browser checks; actual captures saved to design/boards/.`);
  }
} finally {
  socket.close();
  const remaining = await (await fetch('http://127.0.0.1:9222/json/list')).json();
  if (remaining.some(item => item.id === created.targetId)) execFileSync(process.execPath, [cli, 'close', created.targetId], { encoding: 'utf8' });
}
