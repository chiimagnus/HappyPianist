// /generate panel
const genBtn = document.getElementById('genBtn');
const genStrategy = document.getElementById('genStrategy');
const genTopPGroup = document.getElementById('genTopPGroup');
const genTopP = document.getElementById('genTopP');
const genTopPValue = document.getElementById('genTopPValue');
const genMaxTokens = document.getElementById('genMaxTokens');
const genMaxTokensValue = document.getElementById('genMaxTokensValue');
const genNotes = document.getElementById('genNotes');
const genMessage = document.getElementById('genMessage');
const genResult = document.getElementById('genResult');

function showGenMessage(text, type) {
  genMessage.textContent = text;
  genMessage.className = `message show ${type}`;
}
function hideGenMessage() {
  genMessage.className = 'message';
}

function updateGenUI() {
  const isModel = genStrategy.value === 'model';
  genTopPGroup.style.display = isModel ? 'block' : 'none';
}
genStrategy.addEventListener('change', updateGenUI);
updateGenUI();

genTopP.addEventListener('input', () => {
  genTopPValue.textContent = genTopP.value;
});
genMaxTokens.addEventListener('input', () => {
  genMaxTokensValue.textContent = genMaxTokens.value;
});

genBtn.addEventListener('click', async () => {
  hideGenMessage();
  genResult.style.display = 'none';

  let notesPayload;
  try {
    notesPayload = JSON.parse(genNotes.value);
    if (!Array.isArray(notesPayload)) {
      throw new Error('notes 必须是 JSON 数组');
    }
  } catch (err) {
    showGenMessage(`notes JSON 无效：${err.message}`, 'error');
    return;
  }

  const payload = {
    type: 'generate',
    protocol_version: 1,
    notes: notesPayload,
    params: {
      top_p: parseFloat(genTopP.value),
      max_tokens: parseInt(genMaxTokens.value, 10),
      strategy: genStrategy.value,
    },
  };

  genBtn.disabled = true;
  const originalText = genBtn.innerHTML;
  const isModel = genStrategy.value === 'model';
  genBtn.innerHTML = `<div class="spinner"></div><span>${isModel ? '模型推理中（首次加载较慢）...' : '生成中...'}</span>`;

  try {
    const res = await fetch('/generate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const data = await res.json().catch(() => null);
    if (!res.ok) {
      const msg = data && data.message ? data.message : `HTTP ${res.status}`;
      throw new Error(msg);
    }

    genResult.textContent = JSON.stringify(data, null, 2);
    genResult.style.display = 'block';
    showGenMessage(`成功：reply_notes=${(data.notes || []).length}`, 'success');
  } catch (err) {
    showGenMessage(err.message || '请求失败', 'error');
  } finally {
    genBtn.innerHTML = originalText;
    genBtn.disabled = false;
  }
});

// /upload-expand panel
const dropZone = document.getElementById('dropZone');
const fileInput = document.getElementById('fileInput');
const fileName = document.getElementById('fileName');
const generateBtn = document.getElementById('generateBtn');
const strategy = document.getElementById('strategy');
const modeGroup = document.getElementById('modeGroup');
const duration = document.getElementById('duration');
const durationValue = document.getElementById('durationValue');
const durationLabel = document.getElementById('durationLabel');
const modelHint = document.getElementById('modelHint');
const topPGroup = document.getElementById('topPGroup');
const topP = document.getElementById('topP');
const topPValue = document.getElementById('topPValue');
const message = document.getElementById('message');
const results = document.getElementById('results');
const resultGrid = document.getElementById('resultGrid');
const downloadBtn = document.getElementById('downloadBtn');

let selectedFile = null;
let midiBase64 = '';
let outputFilename = '';

// Strategy switch
function updateUIForStrategy() {
  const isModel = strategy.value === 'model';
  modeGroup.style.display = isModel ? 'none' : 'block';
  topPGroup.style.display = isModel ? 'block' : 'none';
  durationLabel.textContent = isModel ? '续写长度（秒）' : '生成时长（秒）';
  modelHint.style.display = isModel ? 'block' : 'none';
  if (isModel) {
    duration.max = 20;
    duration.min = 2;
    duration.step = 1;
    if (parseInt(duration.value) > 20) duration.value = 12;
  } else {
    duration.max = 60;
    duration.min = 5;
    duration.step = 5;
  }
  durationValue.textContent = duration.value;
}
strategy.addEventListener('change', updateUIForStrategy);
updateUIForStrategy();

// Duration slider
duration.addEventListener('input', () => {
  durationValue.textContent = duration.value;
});

// Top-p slider
topP.addEventListener('input', () => {
  topPValue.textContent = topP.value;
});

// File selection
fileInput.addEventListener('change', (e) => {
  if (e.target.files.length) {
    setFile(e.target.files[0]);
  }
});

function setFile(file) {
  selectedFile = file;
  fileName.textContent = file.name;
  generateBtn.disabled = false;
  hideMessage();
  results.classList.remove('show');
}

// Drag & drop
dropZone.addEventListener('dragover', (e) => {
  e.preventDefault();
  dropZone.classList.add('dragover');
});
dropZone.addEventListener('dragleave', () => {
  dropZone.classList.remove('dragover');
});
dropZone.addEventListener('drop', (e) => {
  e.preventDefault();
  dropZone.classList.remove('dragover');
  const files = e.dataTransfer.files;
  if (files.length) {
    fileInput.files = files;
    setFile(files[0]);
  }
});

// Generate
generateBtn.addEventListener('click', async () => {
  if (!selectedFile) return;

  const isModel = strategy.value === 'model';
  generateBtn.disabled = true;
  const originalText = generateBtn.innerHTML;
  generateBtn.innerHTML = `<div class="spinner"></div><span>${isModel ? 'AI 模型推理中（首次加载较慢）...' : '生成中...'}</span>`;
  hideMessage();
  results.classList.remove('show');

  const form = new FormData();
  form.append('file', selectedFile);
  form.append('strategy', strategy.value);
  if (!isModel) {
    form.append('mode', document.getElementById('mode').value);
  }
  form.append('extra_duration', duration.value);
  form.append('include_source', document.getElementById('includeSource').checked);
  if (isModel) {
    form.append('top_p', document.getElementById('topP').value);
  }

  try {
    const res = await fetch('/upload-expand', {
      method: 'POST',
      body: form,
    });

    if (!res.ok) {
      const err = await res.json().catch(() => ({ message: '生成失败，请检查后端服务' }));
      throw new Error(err.message || '生成失败');
    }

    const data = await res.json();
    midiBase64 = data.midi_base64;
    outputFilename = data.filename;

    // Show analysis
    const a = data.analysis;
    const strategyLabel = data.strategy === 'model' ? 'AI 模型' : '算法生成';
    resultGrid.innerHTML = `
      <div class="stat"><div class="stat-value">${a.key_signature}</div><div class="stat-label">调性 (${a.key_mode})</div></div>
      <div class="stat"><div class="stat-value">${Math.round(a.tempo_bpm)}</div><div class="stat-label">BPM</div></div>
      <div class="stat"><div class="stat-value">${a.time_signature.join('/')}</div><div class="stat-label">拍号</div></div>
      <div class="stat"><div class="stat-value">${data.source_note_count}</div><div class="stat-label">原始音符</div></div>
      <div class="stat"><div class="stat-value">${data.generated_melody_count}</div><div class="stat-label">生成旋律</div></div>
      <div class="stat"><div class="stat-value">${data.generated_accompaniment_count}</div><div class="stat-label">生成伴奏</div></div>
      <div class="stat"><div class="stat-value">${Math.round(a.duration_seconds)}s</div><div class="stat-label">原曲时长</div></div>
      <div class="stat"><div class="stat-value">${strategyLabel}</div><div class="stat-label">生成策略</div></div>
    `;

    // Setup download
    const blob = new Blob([Uint8Array.from(atob(midiBase64), c => c.charCodeAt(0))], { type: 'audio/midi' });
    const url = URL.createObjectURL(blob);
    downloadBtn.href = url;
    downloadBtn.download = outputFilename;

    results.classList.add('show');
    showMessage('生成成功！', 'success');
  } catch (err) {
    showMessage(err.message, 'error');
  } finally {
    generateBtn.innerHTML = originalText;
    generateBtn.disabled = false;
  }
});

function showMessage(text, type) {
  message.textContent = text;
  message.className = `message show ${type}`;
}
function hideMessage() {
  message.className = 'message';
}

