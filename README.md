# 🎹 LonelyPianist

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_14%2B-blue?style=for-the-badge&logo=apple&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange?style=for-the-badge&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge" alt="License">
</p>

---

## 📌 文档入口

- **macOS 主应用（MIDI → 文本/快捷键/快捷指令）**：见下文「快速上手」「使用指南」
- **Piano Dialogue（本机 AI 钢琴对话）**：见下文「🤖 Piano Dialogue」
- **Apple Vision Pro（LonelyPianistAVP：AR Guide + 手部追踪 + 校准 + 指引）**：见下文「🕶️ Apple Vision Pro（AR Guide）」
- **OMR（PDF/图片 → MusicXML）**：见下文「🧾 OMR：PDF/图片 → MusicXML」
- **本机 Python 服务（Dialogue + OMR HTTP）**：见下文「🧠 本机 Python 服务（Dialogue + OMR HTTP）」
- **OMR 转换器打包 PoC**：见下文「📦 OMR 转换器打包 PoC」
- **visionOS 踩坑 Playbook（XCDocs）**：见下文「🧰 visionOS 踩坑 Playbook（XCDocs）」
- **研发计划/审计（内部）**：`.github/features/`（当前进行中）与 `.github/archived_features/`（历史归档，仅参考）

## 🎛️ 使用指南

## 🤖 Piano Dialogue（AI 钢琴对话模式）

> Turn-based：你弹一段 → 停顿 → AI 回一段（AI 音符会用橙色显示，并保存到 Recorder 的同一个 take 内）。

### 1) 准备 Python 后端（首次必做）

本仓库自带本机后端工作区：`piano_dialogue_server/`。

创建虚拟环境并安装依赖：

```bash
cd piano_dialogue_server
python3.12 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -r requirements.txt
```

（可选）离线验证脚本（P1，直接生成可试听的 MIDI，不需要启动服务）：

```bash
cd piano_dialogue_server
source .venv/bin/activate
python scripts/test_generate.py
python scripts/test_infilling.py
```

输出位置：

- `piano_dialogue_server/out/output.mid`
- `piano_dialogue_server/out/output_infilling.mid`

准备模型权重（不要提交仓库）：

- 模型（服务默认）：`stanford-crfm/music-large-800k`
- 放置路径：
  - `piano_dialogue_server/models/music-large-800k/model.safetensors`
  - `piano_dialogue_server/models/music-large-800k/config.json`

（可选）如果你把模型放在其他目录，后端支持：

```bash
export AMT_MODEL_DIR=/path/to/music-large-800k
```

（可选）脚本/服务支持的环境变量：

- `AMT_MODEL_DIR`：本地模型目录（优先级最高）
- `AMT_MODEL_ID`：HuggingFace 模型 ID（`scripts/*` 默认是 `stanford-crfm/music-small-800k`；服务默认是 `stanford-crfm/music-large-800k`）
- `AMT_DEVICE`：`mps` / `cuda` / `cpu`（默认自动选择）

Apple Silicon 上如遇到算子不支持，可尝试：

```bash
export PYTORCH_ENABLE_MPS_FALLBACK=1
```

### 2) 启动后端服务（保持运行）

在一个独立终端（或 tmux）里启动（从 `piano_dialogue_server/` 目录）：

```bash
cd piano_dialogue_server
source .venv/bin/activate
python -m uvicorn server.main:app --host 127.0.0.1 --port 8765
```

（可选）开启后端调试包落地（默认关闭；会把每次 generate 的 request/response + prompt/reply MIDI 写到 `piano_dialogue_server/out/dialogue_debug/`）：

```bash
export DIALOGUE_DEBUG=1
```

健康检查：

```bash
curl -s http://127.0.0.1:8765/health
```

期望输出：

```json
{"status":"ok"}
```

（可选）端到端测试（会生成 `piano_dialogue_server/out/server_reply.mid`）：

```bash
cd piano_dialogue_server/server
../.venv/bin/python test_client.py
```

### 3) 在 App 中使用 Dialogue

1. 启动 LonelyPianist（主窗口直接显示）
2. 首次使用仍需授予 **辅助功能权限**（否则无法开始监听）
3. 点击 `Start Listening`
4. 在侧边栏选择 `Dialogue`，点击 `Start Dialogue`
5. 弹一段，停顿（默认静默 2s + 踏板抬起）后触发 AI 回应
6. 回应会自动回放到你选择的 playback output，并保存为 take（Recorder 里可见）

回放期间的输入策略（可持久化，默认 B）：

- A Ignore：忽略你的输入
- B Interrupt：你一按键就打断 AI，立刻开始收集下一句（默认）
- C Queue：排队，AI 播完后再生成下一句

---

## 🕶️ Apple Vision Pro（AR Guide）

`LonelyPianistAVP` 是 visionOS 端的练琴/AR 指引原型：**导入 MusicXML → 校准钢琴空间位置 → 通过手部追踪判定按键 → 以 AR 高亮提示下一步**。

### 验收流程（最短闭环）

1. **导入谱子（MusicXML）**：在 2D 窗口点 `Import MusicXML…`，看到 `Steps: N`（N>0）。
2. **进入 AR Guide**：点 `Start AR Guide`，首次会弹出手部追踪权限弹窗，点允许。
3. **确认沉浸式状态可见**：你应看到 HUD（`AR Guide` 面板）+ 黄色 reticle 球 + 手指绿点（指尖）。
4. **校准（A0 / C8）**：在 HUD 点 `Set A0` / `Set C8`，对准真实钢琴两端键位，空间点击捕获，然后 `Save`。
5. **练习指引**：校准完成后会显示当前 step 的键位高亮；可用 `Skip` / `Mark Correct` 辅助推进验证流程。

> 重要：当前 MVP 的键位对齐依赖 **A0 / C8 两点校准**。如果高亮位置明显漂移，先重新校准再判断判定逻辑。

---

## 🧾 OMR：PDF/图片 → MusicXML

目标：把你手里现成的 **PDF/图片谱** 转成 **MusicXML**（给 `LonelyPianistAVP` 导入）。

当前仓库提供两种入口：**CLI**（最直接）与 **HTTP**（给 App/前端调用）。

### A) CLI 转换（推荐先用这个验收）

```bash
cd piano_dialogue_server
source .venv/bin/activate
python -m omr.cli --input /absolute/path/to/score.pdf
```

输出会打印：

- `job_dir=...`
- `musicxml_path=.../output/score.musicxml`

把这个 `score.musicxml` 拿去 AVP 里导入即可。

### B) HTTP 转换（服务接口）

先启动服务（见下文「🧠 本机 Python 服务」），然后：

```bash
curl -s \
  -F "file=@/absolute/path/to/score.pdf" \
  -F "inline_xml=true" \
  http://127.0.0.1:8765/omr/convert
```

返回包含：

- `musicxml_path`：生成的 MusicXML 文件路径
- `job_dir`：本次转换的 job 目录（包含调试产物）

### 输出结构（便于排障）

每次转换都会写入：

`piano_dialogue_server/out/omr/<basename>-<timestamp>-<id>/`

目录结构：

- `input/`：预处理后的图片（PDF 会先渲染成图片）
- `debug/`：oemer 与管线调试产物（例如 `oemer_teaser.png`）
- `output/score.musicxml`：最终输出（给 AVP 导入）

### 多页 PDF 策略（MVP）

- 当前 MVP **只处理第一页**。
- 多页 PDF 会发出 warning，并只转换 page 1。
- 如果你传 `page != 1` 且是多页 PDF，会返回明确错误（后续再做 merge-pages）。

### checkpoints（离线/首次运行）

如果你的 Python 环境里缺少 oemer checkpoints，首次转换会自动下载（需要联网一次）。

完全离线的话：下载并预置以下 4 个文件（来自 `oemer` 上游仓库的 Release assets）：

- `1st_model.onnx`：`https://github.com/BreezeWhite/oemer/releases/download/checkpoints/1st_model.onnx`
- `1st_weights.h5`：`https://github.com/BreezeWhite/oemer/releases/download/checkpoints/1st_weights.h5`
- `2nd_model.onnx`：`https://github.com/BreezeWhite/oemer/releases/download/checkpoints/2nd_model.onnx`
- `2nd_weights.h5`：`https://github.com/BreezeWhite/oemer/releases/download/checkpoints/2nd_weights.h5`

把文件放到虚拟环境里的默认目录（`oemer` 包内 checkpoints 目录）：

- `<venv>/lib/python3.12/site-packages/oemer/checkpoints/unet_big/`
- `<venv>/lib/python3.12/site-packages/oemer/checkpoints/seg_net/`

然后再跑一次 CLI 转换验证。

> 许可证与再分发提示：
> - `oemer` 代码许可证为 MIT（来自 `pip show oemer` 元数据）。
> - checkpoints 的再分发条款在本仓库里未明确声明；如果要把 checkpoints 打进产品安装包，请先做合规确认。默认策略是“首次运行下载/或由用户手动预置”。

---

## 🧠 本机 Python 服务（Dialogue + OMR HTTP）

服务代码在 `piano_dialogue_server/server/`，同时提供：

- `GET /health`：健康检查
- `POST /omr/convert`：PDF/图片 → MusicXML
- `WS /ws`：Piano Dialogue（AI 钢琴对话）

### 启动

```bash
cd piano_dialogue_server
source .venv/bin/activate
python -m uvicorn server.main:app --host 127.0.0.1 --port 8765
```

健康检查：

```bash
curl -s http://127.0.0.1:8765/health
```

---

## 📦 OMR 转换器打包 PoC

目标：把 OMR 转换器打成一个可分发的 CLI，让用户不必自己配 Python 环境。

当前 PoC 路线：PyInstaller one-folder 包。

```bash
cd piano_dialogue_server
./.venv/bin/pip install -U pyinstaller
./omr/packaging/build_pyinstaller.sh
```

产物：

- `piano_dialogue_server/omr/packaging/dist/lp-omr-convert`

注意：checkpoint 默认依然是 **首次运行下载**（在未确认 checkpoint 再分发条款前，不建议打进包里）。

产品化目标（尚未接入）：建议把 checkpoints 缓存到 `~/Library/Application Support/LonelyPianistOMR/checkpoints/`，避免写入 site-packages。

---

## 🙏 致谢

本项目的部分能力依赖以下开源项目/标准：

- `oemer`：用于 OMR（乐谱 PDF/图片 → MusicXML）的核心推理组件（Python）。
- `PyMuPDF`：用于 PDF 渲染与页面提取（Python）。
- `FastAPI` / `Uvicorn`：用于本机 Python 服务与 HTTP 接口。
- MusicXML：乐谱交换格式标准（AVP 导入以 MusicXML 为主）。

## 🎹 没有实体 MIDI 键盘？

没问题！你可以用虚拟 MIDI 键盘测试：

- 推荐 [MidiKeys](https://github.com/flit/MidiKeys)（开源免费）
- 打开 MidiKeys 后，在 LonelyPianist 中点击 `Refresh MIDI Sources` 即可识别

> 💡 **避坑提示**：不要用库乐队（GarageBand）测试 — 它的 MIDI 事件不会广播给外部应用。

---

<p align="center">
  Made with 🎹 by <a href="https://github.com/chiimagnus">chiimagnus</a>
</p>
