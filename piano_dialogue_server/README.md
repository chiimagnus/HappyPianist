# 本机 Python：piano_dialogue_server（Dialogue）

这里是本仓库的 **Python 工作区**，用于两件事：

1. **Piano Dialogue**：本机 AI 钢琴对话（Turn-based 生成/回放）

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

## 🧠 本机服务接口一览（Dialogue）

服务代码在 `piano_dialogue_server/server/`，同时提供：

- `GET /health`：健康检查
- `WS /ws`：Piano Dialogue（AI 钢琴对话）

> 说明：本仓库不再内置 PDF/图片转 MusicXML 的流程。AVP 侧只负责导入外部准备好的 MusicXML 文件。
