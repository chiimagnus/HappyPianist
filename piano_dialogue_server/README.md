# 本机 Python：piano_dialogue_server（Dialogue + OMR）

这里是本仓库的 **Python 工作区**，用于两件事：

1. **Piano Dialogue**：本机 AI 钢琴对话（Turn-based 生成/回放）
2. **OMR**：把 PDF/图片谱转换为 MusicXML（给 `LonelyPianistAVP` 导入）

---

## 🤖 Piano Dialogue（AI 钢琴对话）

> Turn-based：你弹一段 → 停顿 → AI 回一段（回放 + 录入 Recorder take）。

### 1) 准备环境（首次必做）

创建虚拟环境并安装依赖：

```bash
cd piano_dialogue_server
python3.12 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -r requirements.txt
```

（可选）离线验证脚本（直接生成可试听的 MIDI，不需要启动服务）：

```bash
cd piano_dialogue_server
source .venv/bin/activate
python scripts/test_generate.py
python scripts/test_infilling.py
```

输出位置：

- `piano_dialogue_server/out/output.mid`
- `piano_dialogue_server/out/output_infilling.mid`

### 2) 准备模型权重（不要提交仓库）

- 模型（服务默认）：`stanford-crfm/music-large-800k`
- 放置路径：
  - `piano_dialogue_server/models/music-large-800k/model.safetensors`
  - `piano_dialogue_server/models/music-large-800k/config.json`

（可选）如果你把模型放在其他目录：

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

### 3) 启动后端服务（保持运行）

在一个独立终端（或 tmux）里启动：

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

先启动服务（见上文），然后：

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

## 🧠 本机服务接口一览（Dialogue + OMR）

服务代码在 `piano_dialogue_server/server/`，同时提供：

- `GET /health`：健康检查
- `POST /omr/convert`：PDF/图片 → MusicXML
- `WS /ws`：Piano Dialogue（AI 钢琴对话）

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
