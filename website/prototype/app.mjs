import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { CSS3DRenderer, CSS3DObject } from 'three/addons/renderers/CSS3DRenderer.js';
import { songs, pageCount, boards, initialState, transition, boardState } from './model.mjs';

const viewport = document.querySelector('#viewport');
const product = document.querySelector('#product');
const actions = document.querySelector('#actions');
const results = document.querySelector('#search-results');
const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.12;
viewport.append(renderer.domElement);
const cssRenderer = new CSS3DRenderer();
cssRenderer.setSize(innerWidth, innerHeight);
cssRenderer.domElement.id = 'css-scene';
viewport.append(cssRenderer.domElement);
const operationsElement = document.createElement('div');
operationsElement.id = 'spatial-operations';
const spatialStatus = document.createElement('div');
spatialStatus.id = 'spatial-status';
operationsElement.append(spatialStatus);
const spatialOperations = new CSS3DObject(operationsElement);
spatialOperations.scale.setScalar(0.00125);

const scene = new THREE.Scene();
scene.background = new THREE.Color('#e9e5df');
scene.fog = new THREE.Fog('#e9e5df', 4, 9);
const camera = new THREE.PerspectiveCamera(43, innerWidth / innerHeight, 0.02, 12);
const orbit = new OrbitControls(camera, renderer.domElement);
orbit.enableDamping = true;
orbit.enablePan = false;
orbit.minDistance = 0.8;
orbit.maxDistance = 3.5;
orbit.minPolarAngle = 0.15;
orbit.maxPolarAngle = Math.PI * 0.65;
orbit.target.set(0, 1.25, 0);
scene.add(new THREE.HemisphereLight('#ffffff', '#ada994', 2.2));
const light = new THREE.DirectionalLight('#fff5e2', 3);
light.position.set(-2, 4, 3);
light.castShadow = true;
light.shadow.mapSize.set(2048, 2048);
light.shadow.camera.left = -2;
light.shadow.camera.right = 2;
light.shadow.camera.top = 3;
light.shadow.camera.bottom = -1;
light.shadow.bias = -0.0002;
scene.add(light);
const floor = new THREE.Mesh(new THREE.PlaneGeometry(20, 20), new THREE.MeshStandardMaterial({ color: '#dedbd2', roughness: 1 }));
floor.rotation.x = -Math.PI / 2;
floor.receiveShadow = true;
scene.add(floor);
const grid = new THREE.GridHelper(8, 32, '#c4c8be', '#d2d5cb');
grid.position.y = 0.001;
grid.material.transparent = true;
grid.material.opacity = 0.2;
scene.add(grid);

const width = 0.32;
const height = 0.43;
let state = initialState();
let delayed;
let ticker;
let currentBoard = 'D01';
let previousFrame = performance.now();
let scoreKey = '';
let renderError = '';
const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2();
const folios = [];
const emptyRoot = new THREE.Group();
emptyRoot.position.set(0, 1.45, 0);
scene.add(emptyRoot);

function canvasTexture(canvas) {
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = Math.min(renderer.capabilities.getMaxAnisotropy(), 8);
  return texture;
}

function coverTexture(song, index) {
  const canvas = document.createElement('canvas');
  canvas.width = 768;
  canvas.height = 1032;
  const context = canvas.getContext('2d');
  context.fillStyle = '#f4efdf';
  context.fillRect(0, 0, 768, 1032);
  context.strokeStyle = '#d9d1bd';
  context.lineWidth = 2;
  context.strokeRect(24, 24, 720, 984);
  context.fillStyle = '#393f40';
  context.textAlign = 'center';
  context.font = `${song.title.length > 16 ? 42 : 50}px Georgia, serif`;
  context.fillText(song.title, 384, 157, 640);
  context.font = '23px Georgia, serif';
  context.fillStyle = '#6d7064';
  context.fillText(song.composer, 384, 207);
  const gradient = context.createLinearGradient(0, 290, 0, 850);
  gradient.addColorStop(0, '#e1ddc9');
  gradient.addColorStop(1, song.tint);
  context.fillStyle = gradient;
  context.fillRect(70, 280, 628, 566);
  for (let layer = 0; layer < 10; layer += 1) {
    context.beginPath();
    context.moveTo(70, 846);
    for (let position = 70; position <= 698; position += 4) {
      const elevation = 555 + layer * 25 + Math.sin(position * 0.01 + layer * 0.66 + index) * 40 + Math.cos(position * 0.018 + layer) * 24;
      context.lineTo(position, elevation);
    }
    context.lineTo(698, 846);
    context.closePath();
    context.fillStyle = layer % 2 ? '#eff0df' : song.tint;
    context.globalAlpha = 0.18;
    context.fill();
  }
  context.globalAlpha = 0.8;
  context.fillStyle = '#f8ebc7';
  context.beginPath();
  context.arc(455 - index * 14, 423, 33, 0, Math.PI * 2);
  context.fill();
  context.globalAlpha = 1;
  context.font = '18px Georgia, serif';
  context.fillStyle = '#72776a';
  context.fillText('PIANO SOLO', 384, 916);
  context.font = '14px sans-serif';
  context.fillText('PROCEDURAL COVER · DESIGN SAMPLE', 384, 965);
  return canvasTexture(canvas);
}

function pageSurface() {
  const canvas = document.createElement('canvas');
  canvas.width = 768;
  canvas.height = 1032;
  return { canvas, texture: canvasTexture(canvas) };
}

function paintPage(surface, page) {
  const context = surface.canvas.getContext('2d');
  context.fillStyle = '#f8f3e5';
  context.fillRect(0, 0, 768, 1032);
  const gradient = context.createLinearGradient(0, 0, 768, 0);
  gradient.addColorStop(0, '#d6cbb433');
  gradient.addColorStop(0.08, '#ffffff00');
  gradient.addColorStop(1, '#b1a48e12');
  context.fillStyle = gradient;
  context.fillRect(0, 0, 768, 1032);
  context.textAlign = 'center';
  context.fillStyle = '#747767';
  if (page > pageCount) {
    context.font = '26px Georgia, serif';
    context.fillText('End of score', 384, 500);
    context.font = '18px sans-serif';
    context.fillText('奇数末页 · 右侧为空白', 384, 546);
    surface.texture.needsUpdate = true;
    return;
  }
  context.font = '34px Georgia, serif';
  context.fillStyle = '#343a39';
  context.fillText(songs[state.selected].title, 384, 77, 650);
  context.font = '16px sans-serif';
  context.fillStyle = '#788172';
  context.fillText('布局测试谱 · 并非该作品真实 MusicXML', 384, 113);
  context.textAlign = 'left';
  for (let system = 0; system < 4; system += 1) {
    const top = 190 + system * 188;
    const firstMeasure = (page - 1) * 8 + system * 2 + 1;
    const active = state.session && state.measure >= firstMeasure && state.measure < firstMeasure + 2;
    if (active || (state.stage === 'result' && firstMeasure === 9 && state.feedback !== 'unknown')) {
      context.fillStyle = state.feedback === 'unknown' ? '#8a969014' : '#d5bd7532';
      context.fillRect(105, top - 14, 577, 132);
      context.strokeStyle = state.feedback === 'unknown' ? '#909a90' : '#ba9c54';
      context.lineWidth = 2;
      context.strokeRect(105, top - 14, 577, 132);
    }
    context.fillStyle = '#5c635a';
    context.font = '18px Georgia, serif';
    context.fillText(String(firstMeasure), 65, top - 17);
    for (let staff = 0; staff < 2; staff += 1) {
      const staffTop = top + staff * 73;
      context.strokeStyle = '#555951';
      context.lineWidth = 1.15;
      for (let line = 0; line < 5; line += 1) {
        context.beginPath();
        context.moveTo(82, staffTop + line * 9);
        context.lineTo(690, staffTop + line * 9);
        context.stroke();
      }
      context.fillStyle = '#3e443f';
      context.font = '32px Georgia, serif';
      context.fillText(staff === 0 ? 'G' : 'F', 83, staffTop + 32);
      for (let note = 0; note < 10; note += 1) {
        const noteX = 135 + note * 52;
        const noteY = staffTop + 9 + ((note + firstMeasure + staff * 2) % 6) * 4.5;
        context.beginPath();
        context.ellipse(noteX, noteY, 8, 5.6, -0.35, 0, Math.PI * 2);
        context.fill();
        context.beginPath();
        context.moveTo(noteX + 7, noteY);
        context.lineTo(noteX + 7, noteY - 33);
        context.stroke();
        if (note % 2 === 0) {
          context.lineWidth = 4;
          context.beginPath();
          context.moveTo(noteX + 7, noteY - 33);
          context.lineTo(noteX + 59, noteY - 28);
          context.stroke();
          context.lineWidth = 1.15;
        }
      }
    }
    for (const barX of [82, 405, 690]) {
      context.beginPath();
      context.moveTo(barX, top);
      context.lineTo(barX, top + 109);
      context.stroke();
    }
    if (active) {
      context.font = '15px sans-serif';
      context.fillStyle = '#6b775e';
      context.fillText(state.feedback === 'unknown' ? '— 证据不足，不评价' : `› 当前小节 ${state.measure} · 模拟`, 105, top + 142);
    }
  }
  context.textAlign = 'center';
  context.font = '17px Georgia, serif';
  context.fillStyle = '#7b8072';
  context.fillText(String(page), 384, 987);
  surface.texture.needsUpdate = true;
}

function paperMesh(surface, offset, back = false) {
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(width, height, 24, 1), new THREE.MeshStandardMaterial({ map: surface.texture, roughness: 1 }));
  mesh.position.set(width / 2, 0, offset);
  if (back) mesh.rotation.y = Math.PI;
  mesh.receiveShadow = true;
  return mesh;
}

for (const [index, song] of songs.entries()) {
  const root = new THREE.Group();
  root.userData.song = index;
  const body = new THREE.Mesh(new THREE.BoxGeometry(width, height, 0.01), new THREE.MeshStandardMaterial({ color: '#e1dac8', roughness: 1 }));
  body.position.x = width / 2;
  body.castShadow = true;
  body.receiveShadow = true;
  root.add(body);
  const hinge = new THREE.Group();
  hinge.position.z = 0.013;
  const cover = new THREE.Mesh(new THREE.BoxGeometry(width, height, 0.002), new THREE.MeshStandardMaterial({ color: '#ece5d4', roughness: 1 }));
  cover.position.x = width / 2;
  cover.castShadow = true;
  hinge.add(cover);
  const front = new THREE.Mesh(new THREE.PlaneGeometry(width, height), new THREE.MeshStandardMaterial({ map: coverTexture(song, index), roughness: 1 }));
  front.position.set(width / 2, 0, 0.0012);
  hinge.add(front);
  const left = pageSurface();
  const right = pageSurface();
  hinge.add(paperMesh(left, -0.0012, true));
  root.add(hinge);
  root.add(paperMesh(right, 0.006));
  const spine = new THREE.Mesh(new THREE.CylinderGeometry(0.003, 0.003, height, 8), new THREE.MeshStandardMaterial({ color: '#c8bea6', roughness: 1 }));
  root.add(spine);
  const leaf = new THREE.Group();
  leaf.position.z = 0.023;
  const leafFront = pageSurface();
  const leafBack = pageSurface();
  leaf.add(paperMesh(leafFront, 0.0005));
  leaf.add(paperMesh(leafBack, -0.0005, true));
  leaf.visible = false;
  root.add(leaf);
  root.position.set((index - 2) * 0.35 - width / 2, 1.45, -Math.abs(index - 2) * 0.18);
  scene.add(root);
  folios.push({ root, hinge, front, left, right, leaf, leafFront, leafBack, spread: 0, flip: null, open: 0 });
}

const piano = new THREE.Group();
const pianoMaterial = new THREE.MeshStandardMaterial({ color: '#838b86', roughness: 0.8 });
const pianoBody = new THREE.Mesh(new THREE.BoxGeometry(1.32, 0.13, 0.38), pianoMaterial);
pianoBody.position.set(0, 0.66, -0.02);
pianoBody.castShadow = true;
piano.add(pianoBody);
const keys = [];
let whiteIndex = 0;
for (let pitch = 21; pitch <= 108; pitch += 1) {
  const black = [1, 3, 6, 8, 10].includes(pitch % 12);
  const key = new THREE.Mesh(new THREE.BoxGeometry(black ? 0.014 : 0.023, black ? 0.018 : 0.013, black ? 0.096 : 0.18), new THREE.MeshStandardMaterial({ color: black ? '#323a38' : '#eaece6', roughness: 0.6 }));
  key.position.set(-0.61 + (black ? whiteIndex - 0.5 : whiteIndex) * (1.22 / 52), black ? 0.757 : 0.745, black ? -0.025 : 0.017);
  if (!black) whiteIndex += 1;
  key.castShadow = true;
  key.receiveShadow = true;
  piano.add(key);
  keys.push({ key, pitch, black });
}
for (const side of [-1, 1]) {
  const leg = new THREE.Mesh(new THREE.BoxGeometry(0.045, 0.62, 0.29), pianoMaterial);
  leg.position.set(side * 0.56, 0.31, -0.04);
  piano.add(leg);
}
scene.add(piano);

const guides = new THREE.Group();
for (const side of [-1, 1]) {
  const guide = new THREE.Mesh(new THREE.RingGeometry(0.015, 0.018, 32), new THREE.MeshBasicMaterial({ color: '#b69752', side: THREE.DoubleSide }));
  guide.rotation.x = -Math.PI / 2;
  guide.position.set(side * 0.145, 0.766, 0.04);
  guides.add(guide);
}
scene.add(guides);
const endpoints = new THREE.Group();
for (const side of [-1, 1]) {
  const endpoint = new THREE.Group();
  const marker = new THREE.Mesh(new THREE.RingGeometry(0.025, 0.03, 40), new THREE.MeshBasicMaterial({ color: '#709b86', side: THREE.DoubleSide }));
  marker.position.set(side * 0.6, 0.83, 0.11);
  endpoint.add(marker);
  const labelCanvas = document.createElement('canvas');
  labelCanvas.width = 256;
  labelCanvas.height = 96;
  const labelContext = labelCanvas.getContext('2d');
  labelContext.font = '48px Georgia, serif';
  labelContext.fillStyle = '#466552';
  labelContext.textAlign = 'center';
  labelContext.fillText(side < 0 ? 'A0' : 'C8', 128, 67);
  const label = new THREE.Mesh(new THREE.PlaneGeometry(0.095, 0.036), new THREE.MeshBasicMaterial({ map: canvasTexture(labelCanvas), transparent: true, depthWrite: false }));
  label.position.set(side * 0.6, 0.889, 0.11);
  endpoint.add(label);
  endpoints.add(endpoint);
}
scene.add(endpoints);

const companion = new THREE.Group();
const handMaterial = new THREE.MeshStandardMaterial({ color: '#abc9c4', transparent: true, opacity: 0.6, roughness: 0.6, depthWrite: false });
const hands = [];
for (const side of [-1, 1]) {
  const hand = new THREE.Group();
  const palm = new THREE.Mesh(new THREE.BoxGeometry(0.065, 0.016, 0.072), handMaterial);
  palm.position.z = 0.044;
  hand.add(palm);
  const fingers = [];
  for (let finger = 0; finger < 5; finger += 1) {
    const fingerRoot = new THREE.Group();
    fingerRoot.position.set((finger - 2) * 0.016, 0, 0.01);
    const segment = new THREE.Mesh(new THREE.CapsuleGeometry(0.005, 0.047 - Math.abs(finger - 2) * 0.006, 4, 8), handMaterial);
    segment.rotation.x = Math.PI / 2;
    segment.position.z = -0.02;
    fingerRoot.add(segment);
    hand.add(fingerRoot);
    fingers.push(fingerRoot);
  }
  hand.position.set(side * 0.17, 0.795, 0.05);
  companion.add(hand);
  hands.push({ hand, fingers, side });
}
scene.add(companion);

function setView(view) {
  const target = new THREE.Vector3(0, 1.25, 0);
  const positions = { front: [0, 1.46, 1.75], oblique: [0.85, 1.58, 1.45], side: [1.55, 1.47, 0.56], top: [0.06, 2.45, 0.95] };
  camera.position.fromArray(positions[view] || positions.front);
  orbit.target.copy(target);
  orbit.update();
  document.querySelectorAll('[data-view]').forEach(button => button.classList.toggle('selected', button.dataset.view === view));
}
setView('front');

function button(label, type, value, style = '', disabled = false) {
  const help = state.stage === 'detail' ? {
    'page:-1': disabled ? '已经是第一组书页' : '翻到上一组书页，不改变练习进度',
    'page:1': disabled ? '已经是最后一组书页' : '翻到下一组书页，不改变练习进度',
    'start:begin': '从第 1 小节开始；先确认钢琴输入与位置',
    'start:resume': '从上次保存的第 9 小节开始；先确认输入与定位（模拟进度）',
    'start:focus': '只练第 9–12 小节；这是示例范围，不是当前演奏评价',
    'return:library': '合拢这本谱，返回空间曲库；不会退出 3D',
    'listen:undefined': state.audition ? '停止模拟试听状态；本原型没有真实音频' : '查看模拟试听状态；本原型没有真实音频',
  }[`${type}:${value}`] : undefined;
  return `<button data-action="${type}"${value === undefined ? '' : ` data-value="${value}"`} class="${style}"${help ? ` data-help="${help}"` : ''}${disabled ? ' disabled' : ''}>${label}</button>`;
}

function row(content) { return `<div class="row">${content}</div>`; }

function updateUI() {
  const focused = document.activeElement;
  const focusAction = focused?.dataset?.action;
  const focusValue = focused?.dataset?.value;
  const focusID = focused?.id;
  const selection = focusID === 'search' ? focused.selectionStart : null;
  const name = songs[state.selected].title;
  const labels = {
    entry: ['原二维曲库 · 示意', '仍从熟悉的曲库开始', '现有二维产品保留。只有你主动进入，才打开空间书册。'],
    opening: ['进入中', '正在摆放空间书册', '原窗口仍保留。只有空间成功挂载并摆放后才隐藏。'],
    'entry-error': ['进入未完成', '原二维曲库仍可使用', '取消或失败不关闭原窗口，不自动开始练习。'],
    library: ['空间曲库', name, '先选择，再打开。试听独立；书册不会随着镜头转动。'],
    empty: ['空间曲库', '还没有曲谱', '返回原二维管理窗口导入，不用示例书掩盖空库。'],
    'library-error': ['空间曲库', '曲库暂未读取成功', '可以重试，或返回原二维曲库。'],
    loading: ['曲目详情', '正在准备这一本谱', '当前书保留；可取消，不会沿用上一首曲谱。'],
    'detail-error': ['曲目详情', '这一本谱未能打开', '保留曲目选择，可以重试或合拢。'],
    detail: ['双页详情', name, `第 ${state.spread * 2 + 1}–${Math.min(pageCount, state.spread * 2 + 2)} 页 / ${pageCount} 页 · 测试谱。历史：第 9 小节（模拟）。`],
    input: ['准备 1 / 输入', '你用哪种方式弹奏？', '同一本书暂存在旁边；本原型不会请求麦克风或蓝牙权限。'],
    permission: ['准备 2 / 音频', '允许使用钢琴音频', '正式 App 在这里请求系统权限。本原型只演练允许、拒绝与重试。'],
    midi: ['准备 2 / MIDI', '连接你的 MIDI 钢琴', '连接成功后再定位，连接失败不能提前开始。'],
    a0: ['准备 3 / 定位', '先确认左端 A0', '正式操作由真实端点定位完成；这里使用示意钢琴与模拟确认。'],
    c8: ['准备 4 / 定位', '再确认右端 C8', '端点距离与演奏者方向都合法，才进入 Ready。'],
    ready: ['准备完成 · 模拟', '钢琴位置已确认', '确认后，同一本谱将移到琴上。不生成第二台钢琴。'],
    handoff: ['连续转场', '同一本谱，来到琴上', '曲目与当前页保持。移动动画不决定真实音乐启动时机。'],
    practice: ['琴上练习 · 模拟', state.editing ? '调整谱位' : `${state.paused ? '已暂停' : '练习中'} · 第 ${state.measure} 小节`, state.editing ? '明确编辑态才移动谱。取消恢复原位置；完成后仍暂停。' : `范围 ${state.range[0]}–${state.range[1]} · ${state.feedback === 'unknown' ? '— 证据不足，不评价' : '› 单一当前小节提示（模拟）'}${state.recording ? ' · ● 录音中（模拟）' : ''}${state.metronome ? ' · 节拍开启（无音频）' : ''}${state.companion !== 'off' ? ` · ${state.companion === 'teaching' ? '一次示范' : state.yielding ? '陪弹退让' : '陪弹参与'}（动作占位）` : ''}`],
    result: ['同谱结果 · 模拟', '这一轮完成了', state.feedback === 'unknown' ? '暂无法判断，不生成问题归因或复测建议。结果尚未保存。' : '一个建议：第 9–12 小节，放慢速度完成一次。样本反馈，非真实评估；尚未保存。'],
    saving: ['安全返回', '正在保存，书先不合拢', state.progressSaved ? '进度已保存（内存模拟），等待会话事实保存。' : '先保存小节进度，再完成会话事实保存。两项成功才离开。'],
    'save-error': ['保留现场', '保存未完成', '仍在原书与原会话，可以重试、留下或明确放弃未保存部分。'],
    'discard-confirm': ['再次确认', '放弃尚未保存的部分？', '已保存进度不删除；只放弃本次仍未保存的增量。'],
    relocalize: ['暂停 · 定位恢复', '重新确认钢琴位置', '错位的手和 Guide 已隐藏。谱与会话保留；恢复后不自动播放。'],
    suspended: ['系统中断 · 模拟', '会话暂时停在这里', '播放、手部与录音已停止。恢复需重新定位；刷新网页不保留这些内存。'],
    manager: ['原二维管理 · 示意', '导入与删除仍用原功能', '已离开空间曲库；本原型不操作实际文件。完成后主动重新进入 3D。'],
    settings: ['辅助设置 · 示意', '设置仍服务于这一轮练习', '原会话暂停。这里不是新练习窗口，不创建第二个会话。'],
  };
  const [label, title, copy] = labels[state.stage];
  document.querySelector('#stage-label').textContent = label;
  document.querySelector('#product-title').textContent = title;
  document.querySelector('#product-copy').textContent = copy;
  document.querySelector('#message').textContent = state.message;
  product.dataset.stage = state.stage;
  let content = '';
  const back = button('合拢回曲库', 'return', 'library');
  const cancel = button('取消，保留原书', 'cancel');
  switch (state.stage) {
    case 'entry': case 'entry-error':
      content = button(state.stage === 'entry-error' ? '重试进入 3D' : '进入 3D', 'enter', undefined, 'primary');
      if (state.stage === 'entry-error') content += button('留在 2D', 'cancel');
      break;
    case 'opening': content = button('取消进入', 'cancel'); break;
    case 'library':
      content = row(button('← 上一本', 'select', state.selected - 1, '', state.selected === 0) + button('打开曲谱', 'open', undefined, 'primary') + button('下一本 →', 'select', state.selected + 1, '', state.selected === songs.length - 1));
      content += row(button(state.audition ? '停止试听（模拟）' : '试听（模拟）', 'listen') + button('导入 / 管理', 'manage') + button('返回 2D', 'return', '2d'));
      content += '<div class="row"><label for="search">查找演示曲目</label><input type="search" id="search" placeholder="输入曲名或作曲家" autocomplete="off"></div>';
      break;
    case 'empty': case 'library-error': content = button('重试', 'retry-library') + button('去 2D 管理', 'manage') + button('返回 2D', 'return', '2d'); break;
    case 'loading': content = cancel; break;
    case 'detail-error': content = button('重试打开', 'open', undefined, 'primary') + button('合拢回曲库', 'cancel'); break;
    case 'detail':
      content = button('↙', 'page', -1, 'page-corner previous', state.spread === 0) + button('↘', 'page', 1, 'page-corner next', state.spread === 2);
      content += button('从头练习', 'start', 'begin', 'practice-bookmark');
      content += button('上次停在第 9 小节 · 模拟<br><span>继续上次进度 →</span>', 'start', 'resume', 'history-mark');
      if (state.spread === 0) content += button('练习<br>9–12<span>模拟</span>', 'start', 'focus', 'range-mark');
      content += button('合拢', 'return', 'library', 'spine-close');
      content += button(state.audition ? '停止试听' : '试听', 'listen', undefined, 'title-listen');
      break;
    case 'input': content = row(button('真实钢琴音频', 'input', 'audio', 'primary') + button('Bluetooth MIDI', 'input', 'midi')) + row(button('验证已存定位（模拟）', 'restore') + cancel); break;
    case 'permission': case 'midi': content = button(state.stage === 'permission' ? '模拟允许 / 重试' : '模拟连接 / 重试', 'connect', undefined, 'primary') + cancel; break;
    case 'a0': case 'c8': content = button(`模拟确认 ${state.stage.toUpperCase()}`, 'calibrate', undefined, 'primary') + button('重做定位', 'recalibrate') + cancel; break;
    case 'ready': content = button('确认，移到琴上', 'confirm', undefined, 'primary') + button('重做定位', 'recalibrate') + cancel; break;
    case 'handoff': content = '<span class="kicker">同一书册连续移动中…</span>'; break;
    case 'practice':
      if (state.editing) {
        content = row(button('←', 'move-x', -0.02) + button('→', 'move-x', 0.02) + button('↑', 'move-y', 0.02) + button('↓', 'move-y', -0.02) + button('近一点', 'move-z', 0.02) + button('远一点', 'move-z', -0.02));
        content += row(button('完成调整', 'edit-done', undefined, 'primary') + button('取消调整', 'edit-cancel') + button('重置谱位', 'reset-position'));
      } else {
        content = row(button(state.paused ? '继续练习' : '暂停', 'play', undefined, 'primary') + button(state.controls ? '收起控制' : '唤出控制', 'controls') + button('保存回库', 'return', 'library'));
        if (state.controls) {
          content += row(button(state.recording ? '停止录音（模拟）' : '录音（模拟）', 'record', undefined, '', state.companion !== 'off') + button(state.metronome ? '关闭节拍' : '节拍（模拟）', 'metronome') + button('调整谱位', 'edit'));
          content += row(button('示范一次', 'companion', 'teaching') + button(state.companion === 'duet' ? '停止陪弹' : '开启陪弹', 'companion', state.companion === 'duet' ? 'off' : 'duet') + button(state.loop ? '取消循环范围' : '循环第 9–16 小节', 'loop'));
          content += row(button('辅助设置', 'settings') + button('本轮完成（模拟）', 'finish') + button('保存退出 3D', 'return', '2d'));
          content += `<div class="row"><label for="seek">明确跳练小节 · ${state.measure}</label><input id="seek" type="range" min="${state.range[0]}" max="${state.range[1]}" value="${state.measure}"></div>`;
        }
        if (state.companion !== 'off') content += row(button('停止伙伴动作', 'companion', 'off') + (state.companion === 'duet' ? button(state.yielding ? '恢复陪弹参与（模拟）' : '陪弹退让（模拟）', 'yield') : ''));
      }
      break;
    case 'result': content = row(button('重练建议范围', 'retest', 'focus', 'primary', state.feedback === 'unknown') + button('再练一遍', 'retest', 'all') + button(state.measure < 40 ? '继续后续小节' : '从头继续练习', 'continue')) + row(button('保存回曲库', 'return', 'library') + button('保存退出 3D', 'return', '2d')); break;
    case 'saving': content = button('正在保存…', 'retry-save', undefined, '', true); break;
    case 'save-error': content = button('重试保存', 'retry-save', undefined, 'primary') + button('留在原会话', 'stay') + button('放弃未保存部分…', 'discard', undefined, 'danger'); break;
    case 'discard-confirm': content = button('确认放弃并离开', 'discard-confirm', undefined, 'danger') + button('取消，继续保留', 'cancel'); break;
    case 'relocalize': content = button('模拟重新定位 / 重试', 'relocalized', undefined, 'primary') + (state.session ? button('安全保存回库', 'return', 'library') : cancel); break;
    case 'suspended': content = button('恢复并重新定位', 'resume', undefined, 'primary') + button('安全保存回库', 'return', 'library'); break;
    case 'manager': content = button('完成管理，返回原曲库', 'managed', undefined, 'primary'); break;
    case 'settings': content = button('返回同一练习', 'settings', undefined, 'primary') + button('安全保存回库', 'return', 'library'); break;
  }
  actions.innerHTML = content;
  if (actions.querySelector('#search')) actions.querySelector('#search').value = state.search;
  results.innerHTML = '';
  if (state.stage === 'library' && state.search.trim()) {
    const query = state.search.trim().toLocaleLowerCase();
    songs.forEach((song, index) => {
      if (`${song.title} ${song.composer}`.toLocaleLowerCase().includes(query)) results.insertAdjacentHTML('beforeend', button(song.title, 'select', index));
    });
    if (!results.children.length) results.textContent = '没有匹配的演示曲目。';
  }
  document.querySelector('#review-state').textContent = `演练状态：${state.stage} / 小节 ${state.measure} / 未保存 ${state.dirty ? '是' : '否'} / 进度 ${state.progressSaved ? '成功' : '未完成'} / 会话 ${state.factsSaved ? '成功' : '未完成'}。仅内存账本。`;
  const caption = state.stage === 'library' ? '独立薄书册 · 真实深度 · 世界固定示意' : state.session ? '同一本谱 · 琴上阅读\n灰色琴为现实乐器占位；手部与反馈为模拟' : ['detail', 'input', 'ready', 'a0', 'c8'].includes(state.stage) ? '同一书册展开 · 双页与轻书脊' : '';
  document.querySelector('#scene-caption').textContent = caption;
  const auxiliary = ['entry', 'entry-error', 'opening', 'manager'].includes(state.stage);
  product.classList.toggle('review-only', !auxiliary);
  if (auxiliary) {
    document.body.append(product);
    product.append(actions, results);
    spatialOperations.visible = false;
  } else {
    document.querySelector('#review-explanation').append(product);
    operationsElement.append(actions, results);
    const owner = ['empty', 'library-error'].includes(state.stage) ? emptyRoot : folios[state.selected].root;
    if (spatialOperations.parent !== owner) owner.add(spatialOperations);
    spatialOperations.visible = true;
    const status = {
      library: '', detail: '', loading: '正在打开…', 'detail-error': '曲谱未能打开',
      empty: '还没有曲谱', 'library-error': '曲库读取失败', input: '选择钢琴输入（模拟）',
      permission: '允许钢琴音频（模拟）', midi: '连接 MIDI 钢琴（模拟）',
      a0: '', c8: '', ready: '准备完成（模拟）', handoff: '同一本谱，移到琴上',
      practice: '', result: state.feedback === 'unknown' ? '证据不足，暂不评价' : '第 9–12 小节 · 放慢速度完成一次（模拟）',
      saving: state.progressSaved ? '正在完成会话保存…' : '正在保存进度…',
      'save-error': '', 'discard-confirm': '只放弃未保存部分；已保存内容保留',
      relocalize: '先重新确认钢琴位置', suspended: '已暂停，恢复后先重新定位', settings: '辅助设置（模拟）',
    }[state.stage];
    spatialStatus.textContent = [status, state.message].filter(Boolean).join('\n');
    const onPiano = state.session;
    operationsElement.dataset.stage = state.stage;
    spatialOperations.position.set(onPiano ? 0.60 : state.stage === 'library' ? width / 2 : 0, state.stage === 'detail' ? 0 : onPiano ? -0.02 : -height / 2 - 0.17, 0.045);
  }
  if (focusAction) {
    const selector = `[data-action="${CSS.escape(focusAction)}"]${focusValue === undefined ? '' : `[data-value="${CSS.escape(focusValue)}"]`}`;
    actions.querySelector(selector)?.focus({ preventScroll: true });
  } else if (focusID && product.contains(focused) === false) {
    const replacement = actions.querySelector(`#${CSS.escape(focusID)}`);
    replacement?.focus({ preventScroll: true });
    if (selection !== null) replacement?.setSelectionRange(selection, selection);
  }
}

function updatePages(previous) {
  const folio = folios[state.selected];
  const key = `${state.selected}:${state.spread}:${state.measure}:${state.stage}:${state.feedback}:${state.session}`;
  if (key === scoreKey) return;
  scoreKey = key;
  if (folio.spread !== state.spread && previous.stage === state.stage && Math.abs(folio.spread - state.spread) === 1 && !folio.flip) {
    const forward = state.spread > folio.spread;
    paintPage(folio.leafFront, (forward ? folio.spread : state.spread) * 2 + 2);
    paintPage(folio.leafBack, (forward ? state.spread : folio.spread) * 2 + 1);
    folio.flip = { progress: 0, forward };
    folio.leaf.visible = true;
    paintPage(folio.left, (forward ? folio.spread : state.spread) * 2 + 1);
    paintPage(folio.right, (forward ? state.spread : folio.spread) * 2 + 2);
  } else if (folio.spread !== state.spread) {
    folio.flip = null;
    folio.leaf.visible = false;
    paintPage(folio.left, state.spread * 2 + 1);
    paintPage(folio.right, state.spread * 2 + 2);
  } else if (!folio.flip) {
    paintPage(folio.left, state.spread * 2 + 1);
    paintPage(folio.right, state.spread * 2 + 2);
  }
  folio.spread = state.spread;
}

function schedule() {
  clearTimeout(delayed);
  const complete = { opening: 'placed', loading: 'loaded', handoff: 'arrived' }[state.stage];
  if (complete) delayed = setTimeout(() => dispatch({ type: complete }), state.stage === 'handoff' ? 1100 : 750);
  if (state.stage === 'saving') delayed = setTimeout(() => dispatch({ type: state.progressSaved ? 'facts-saved' : 'progress-saved' }), 700);
  const advancing = state.stage === 'practice' && !state.paused && state.ready && !state.editing && !document.hidden;
  if (advancing && !ticker) ticker = setInterval(() => dispatch({ type: 'tick' }), 1600);
  if (!advancing && ticker) { clearInterval(ticker); ticker = undefined; }
}

function dispatch(event) {
  const previous = state;
  const focusWasInProduct = product.contains(document.activeElement) || actions.contains(document.activeElement);
  state = transition(state, event);
  if (!['detail', 'practice'].includes(state.stage)) {
    folios.forEach(folio => { folio.flip = null; folio.leaf.visible = false; });
    scoreKey = '';
  }
  updatePages(previous);
  updateUI();
  schedule();
  if (previous.stage !== state.stage && focusWasInProduct && !product.contains(document.activeElement) && !actions.contains(document.activeElement)) {
    actions.querySelector('button:not(:disabled)')?.focus({ preventScroll: true });
  }
}

function loadBoard(id) {
  clearTimeout(delayed);
  clearInterval(ticker);
  ticker = undefined;
  const previous = state;
  state = boardState(id);
  currentBoard = id;
  scoreKey = '';
  folios.forEach(folio => { folio.flip = null; folio.leaf.visible = false; });
  updatePages(previous);
  updateUI();
  schedule();
  document.querySelectorAll('[data-board]').forEach(button => button.classList.toggle('selected', button.dataset.board === id));
}

function injectCase(value) {
  const board = ['entry', 'busy'].includes(value) ? 'D01' : ['empty', 'library-error', 'score'].includes(value) ? 'D02' : ['permission', 'midi', 'calibration'].includes(value) ? 'D05' : ['progress', 'facts'].includes(value) ? 'D09' : 'D07';
  loadBoard(board);
  dispatch({ type: 'fault', value });
  if (['entry', 'busy'].includes(value)) dispatch({ type: 'enter' });
  else if (['empty', 'library-error'].includes(value)) dispatch({ type: 'library-case', value });
  else if (value === 'score') dispatch({ type: 'open' });
  else if (['permission', 'midi'].includes(value)) { dispatch({ type: 'input', value: value === 'permission' ? 'audio' : 'midi' }); dispatch({ type: 'connect' }); }
  else if (value === 'calibration') { dispatch({ type: 'input', value: 'audio' }); dispatch({ type: 'connect' }); dispatch({ type: 'calibrate' }); dispatch({ type: 'calibrate' }); }
  else if (value === 'tracking') { dispatch({ type: 'tracking-lost' }); dispatch({ type: 'relocalized' }); }
  else if (['rig', 'ai'].includes(value)) dispatch({ type: 'companion', value: value === 'rig' ? 'teaching' : 'duet' });
  else if (value === 'unknown') dispatch({ type: 'feedback', value: 'unknown' });
  else if (['progress', 'facts'].includes(value)) dispatch({ type: 'return', value: 'library' });
  else if (value === 'suspend') dispatch({ type: 'suspend' });
  document.querySelector('#fault-case').value = '';
}

actions.addEventListener('click', event => {
  const target = event.target.closest('[data-action]');
  if (!target || target.disabled) return;
  const type = target.dataset.action;
  let value = target.dataset.value;
  if (['select', 'page'].includes(type)) value = Number(value);
  if (type.startsWith('move-')) dispatch({ type: 'move', axis: ['x', 'y', 'z'].indexOf(type.slice(5)), value: Number(value) });
  else if (type === 'edit-cancel') dispatch({ type: 'edit-done', cancel: true });
  else dispatch({ type, value });
});
results.addEventListener('click', event => {
  const target = event.target.closest('[data-action]');
  if (target) dispatch({ type: 'select', value: Number(target.dataset.value) });
});
actions.addEventListener('input', event => {
  if (event.target.id === 'search') dispatch({ type: 'search', value: event.target.value });
});
actions.addEventListener('change', event => {
  if (event.target.id === 'seek') dispatch({ type: 'seek', value: Number(event.target.value) });
});
document.querySelector('#views').addEventListener('click', event => { if (event.target.dataset.view) setView(event.target.dataset.view); });
document.querySelector('#board-buttons').innerHTML = boards.map(([id, label]) => `<button data-board="${id}" class="${id === currentBoard ? 'selected' : ''}">${id}<br>${label}</button>`).join('');
document.querySelector('#board-buttons').addEventListener('click', event => { if (event.target.closest('[data-board]')) loadBoard(event.target.closest('[data-board]').dataset.board); });
document.querySelector('#fault-case').addEventListener('change', event => { if (event.target.value) injectCase(event.target.value); });
document.querySelector('#reset-demo').addEventListener('click', () => { loadBoard('D01'); setView('front'); });
document.addEventListener('keydown', event => {
  if (event.target.matches('input,select,textarea') || event.altKey || event.metaKey || event.ctrlKey) return;
  if (['ArrowLeft', 'ArrowRight'].includes(event.key) && ['library', 'detail'].includes(state.stage)) {
    event.preventDefault();
    const amount = event.key === 'ArrowLeft' ? -1 : 1;
    dispatch(state.stage === 'library' ? { type: 'select', value: state.selected + amount } : { type: 'page', value: amount });
  }
  if (event.key === 'Escape' && ['opening', 'loading', 'input', 'permission', 'midi', 'a0', 'c8', 'ready', 'discard-confirm'].includes(state.stage)) dispatch({ type: 'cancel' });
});
document.addEventListener('visibilitychange', () => {
  if (document.hidden) {
    if (state.session) dispatch({ type: 'suspend' });
    else { clearTimeout(delayed); clearInterval(ticker); ticker = undefined; }
  } else schedule();
});
let pointerDown;
renderer.domElement.addEventListener('pointerdown', event => { pointerDown = [event.clientX, event.clientY]; });
renderer.domElement.addEventListener('pointerup', event => {
  if (!pointerDown || Math.hypot(event.clientX - pointerDown[0], event.clientY - pointerDown[1]) > 6) return;
  pointer.set(event.clientX / innerWidth * 2 - 1, -(event.clientY / innerHeight) * 2 + 1);
  raycaster.setFromCamera(pointer, camera);
  if (state.stage === 'library') {
    const hits = raycaster.intersectObjects(folios.filter(folio => folio.root.visible).map(folio => folio.root), true);
    if (!hits.length) return;
    let object = hits[0].object;
    while (object.userData.song === undefined && object.parent) object = object.parent;
    if (object.userData.song === state.selected) dispatch({ type: 'open' });
    else dispatch({ type: 'select', value: object.userData.song });
  } else if (state.stage === 'detail') {
    const hits = raycaster.intersectObject(folios[state.selected].root, true);
    if (hits.length) {
      const local = folios[state.selected].root.worldToLocal(hits[0].point.clone());
      if (Math.abs(local.x) > width * 0.72) dispatch({ type: 'page', value: local.x > 0 ? 1 : -1 });
    }
  }
});

function renderFrame(now) {
  const delta = Math.min((now - previousFrame) / 1000, 0.05);
  previousFrame = now;
  const amount = 1 - Math.exp(-delta * 9);
  const isLibrary = state.stage === 'library';
  const hidden = ['entry', 'entry-error', 'opening', 'empty', 'library-error', 'manager'].includes(state.stage);
  const unfolded = !['library', 'loading', 'detail-error'].includes(state.stage);
  const onPiano = state.session;
  const selected = folios[state.selected];
  for (const [index, folio] of folios.entries()) {
    const distance = index - state.selected;
    folio.root.visible = !hidden && (isLibrary ? Math.abs(distance) <= 2 : index === state.selected);
    if (!folio.root.visible) continue;
    const openTarget = index === state.selected && unfolded ? 1 : 0;
    folio.open = THREE.MathUtils.lerp(folio.open, openTarget, amount);
    folio.hinge.rotation.y = -Math.PI * folio.open;
    const targetX = isLibrary ? Math.sign(distance) * (Math.abs(distance) === 1 ? 0.36 : Math.abs(distance) * 0.30) - width / 2 : -width / 2 * (1 - folio.open) + (onPiano ? state.offset[0] : 0);
    const targetY = onPiano ? 1.24 + state.offset[1] : 1.45;
    const targetZ = isLibrary ? -Math.abs(distance) * 0.23 : (onPiano ? -0.13 + state.offset[2] : 0.08);
    folio.root.position.lerp(new THREE.Vector3(targetX, targetY, targetZ), amount);
    folio.root.rotation.y = THREE.MathUtils.lerp(folio.root.rotation.y, isLibrary ? -Math.sign(distance) * Math.min(Math.abs(distance) * 0.5, 0.85) : 0, amount);
    folio.root.rotation.x = THREE.MathUtils.lerp(folio.root.rotation.x, onPiano ? -0.13 : 0, amount);
    if (folio.flip) {
      folio.flip.progress = Math.min(1, folio.flip.progress + delta / 0.8);
      const eased = folio.flip.progress * folio.flip.progress * (3 - 2 * folio.flip.progress);
      folio.leaf.rotation.y = -Math.PI * (folio.flip.forward ? eased : 1 - eased);
      for (const mesh of folio.leaf.children) {
        const positions = mesh.geometry.attributes.position;
        for (let vertex = 0; vertex < positions.count; vertex += 1) {
          const ratio = (positions.getX(vertex) + width / 2) / width;
          positions.setZ(vertex, Math.sin(ratio * Math.PI) * Math.sin(eased * Math.PI) * 0.025 * (mesh.rotation.y ? -1 : 1));
        }
        positions.needsUpdate = true;
        mesh.geometry.computeVertexNormals();
      }
      if (folio.flip.progress === 1) {
        folio.flip = null;
        folio.leaf.visible = false;
        paintPage(folio.left, state.spread * 2 + 1);
        paintPage(folio.right, state.spread * 2 + 2);
      }
    }
  }
  piano.visible = !hidden && ['input', 'permission', 'midi', 'a0', 'c8', 'ready', 'handoff', 'practice', 'result', 'saving', 'save-error', 'discard-confirm', 'relocalize', 'suspended', 'settings'].includes(state.stage);
  endpoints.visible = ['a0', 'c8', 'ready'].includes(state.stage);
  endpoints.children[0].visible = ['a0', 'ready'].includes(state.stage);
  endpoints.children[1].visible = ['c8', 'ready'].includes(state.stage);
  const visibleHands = state.stage === 'practice' && state.ready && !state.paused && !state.editing && state.companion !== 'off' && !state.yielding;
  companion.visible = visibleHands;
  guides.visible = state.stage === 'practice' && state.ready && !state.editing && !visibleHands;
  for (const [index, item] of hands.entries()) {
    const motionTime = now / 1000;
    item.hand.position.x = item.side * 0.17 + Math.sin(motionTime * 0.9 + index) * 0.028;
    item.hand.position.y = 0.795 + Math.sin(motionTime * 2 + index) * 0.007;
    for (const [finger, object] of item.fingers.entries()) object.rotation.x = Math.sin(motionTime * 3 + finger * 1.5) * 0.12;
  }
  orbit.update();
  if (['entry', 'entry-error', 'opening', 'manager'].includes(state.stage)) {
    product.style.left = `${innerWidth / 2}px`;
    product.style.top = `${Math.max(150, innerHeight * 0.34)}px`;
  }
  renderer.render(scene, camera);
  cssRenderer.render(scene, camera);
}

window.addEventListener('resize', () => { camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix(); renderer.setSize(innerWidth, innerHeight); cssRenderer.setSize(innerWidth, innerHeight); });
window.addEventListener('error', event => { renderError = event.message; });
window.addEventListener('unhandledrejection', event => { renderError = String(event.reason); });
window.addEventListener('pagehide', () => { clearTimeout(delayed); clearInterval(ticker); renderer.setAnimationLoop(null); });

window.prototypeReview = {
  loadBoard, injectCase, setView,
  snapshot: () => {
    const center = folios[state.selected].root.localToWorld(new THREE.Vector3(width / 2, 0, 0.02)).project(camera);
    return { ...structuredClone(state), board: currentBoard, threeRevision: THREE.REVISION, renderError, meshes: renderer.info.render.calls, visibleBooks: folios.filter(folio => folio.root.visible).length, openAngle: folios[state.selected].hinge.rotation.y, flipping: Boolean(folios[state.selected].flip), companionVisible: companion.visible, guideVisible: guides.visible, companionHandCount: hands.length, keyboardKeyCount: keys.length, selectedBookUUID: folios[state.selected].root.uuid, bookPosition: folios[state.selected].root.position.toArray(), selectedBookScreen: [(center.x + 1) * innerWidth / 2, (1 - center.y) * innerHeight / 2], cameraPosition: camera.position.toArray(), controlsWorldMatrix: spatialOperations.matrixWorld.toArray(), controlsCSSTransform: operationsElement.style.transform, simulatedOnly: true };
  },
};
updatePages(state);
updateUI();
renderer.setAnimationLoop(renderFrame);
const linkedBoard = new URLSearchParams(location.search).get('board');
if (boards.some(([id]) => id === linkedBoard)) loadBoard(linkedBoard);
