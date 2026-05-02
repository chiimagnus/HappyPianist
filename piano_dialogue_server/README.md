# 本机 Python：piano_dialogue_server

这里是 LonelyPianist 的本地推理工作区，提供 Piano Dialogue 所需的 HTTP / WebSocket 生成接口，以及本地 MIDI 上传扩展工具。

## 它做什么

- `GET /health`：健康检查
- `GET /`：若存在 `static/index.html`，则返回前端页面
- `POST /generate`：标准 HTTP 生成接口，接收 `generate` 请求并返回结果
- `WS /ws`：接收 `generate` 请求并返回回复音符
- `POST /upload-expand`：上传 MIDI，生成扩展后的 MIDI（算法或模型），并以 base64 返回给前端下载
- `server/debug_artifacts.py`：在调试模式下写出 request / response / MIDI / summary bundle

## 准备环境

```bash
cd piano_dialogue_server
python3.12 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -r requirements.txt
```

## 两种运行方式（是否加载模型）

- **不加载大模型（更轻）**
  - `POST /generate`：把 `params.strategy` 设为 `deterministic`
  - `POST /upload-expand`：把 `strategy` 设为 `algorithm`
- **加载大模型（更重）**
  - `POST /generate`：把 `params.strategy` 设为 `model`
  - `POST /upload-expand`：把 `strategy` 设为 `model`

注意：当前 `WS /ws` 的实现会在连接中调用模型引擎初始化；若你想确保完全不触发模型加载，优先使用 `POST /generate` 的 `deterministic`。

## 模型加载顺序

1. `AMT_MODEL_DIR`
2. 仓库内 `models/music-large-800k`
3. `AMT_MODEL_ID`，默认 `stanford-crfm/music-large-800k`

可选环境变量：

| 变量 | 作用 |
| --- | --- |
| `AMT_MODEL_DIR` | 本地模型目录 |
| `AMT_MODEL_ID` | Hugging Face 模型 ID |
| `AMT_DEVICE` | `mps` / `cuda` / `cpu` |
| `DIALOGUE_DEBUG` | 是否写出调试包 |
| `HF_ENDPOINT` | 镜像地址 |

可选：下载模型权重（脚本默认下载 `music-small-800k`；要跑服务端默认的 `music-large-800k`，请显式设置变量）：

```bash
cd piano_dialogue_server
AMT_MODEL_ID=stanford-crfm/music-large-800k \
AMT_MODEL_DIR=models/music-large-800k \
./scripts/download_model.sh
```

## 启动服务

```bash
cd piano_dialogue_server
source .venv/bin/activate
python -m uvicorn server.main:app --host 0.0.0.0 --port 8765
```

健康检查：

```bash
curl -s http://127.0.0.1:8765/health
```

HTTP 生成接口示例：

```bash
curl -X POST http://127.0.0.1:8765/generate \
  -H "Content-Type: application/json" \
  -d '{
    "type": "generate",
    "protocol_version": 1,
    "notes": [
      {"note": 60, "velocity": 90, "time": 0.0, "duration": 0.5}
    ],
    "params": {
      "top_p": 0.95,
      "max_tokens": 256,
      "strategy": "deterministic"
    }
  }'
```

其中 `strategy` 可选值：
- `model`：使用原始模型生成
- `deterministic`：使用本地规则/分析生成，更稳定、保留原片段风格

## 离线验证

```bash
cd piano_dialogue_server
source .venv/bin/activate
python scripts/test_generate.py
python scripts/test_infilling.py
```

备注：离线验证脚本会尝试加载模型；如果你只想验证“无模型”的路径，直接起服务并调用 `POST /generate`（`deterministic`）更快。

## MIDI 解析与扩展

```bash
cd piano_dialogue_server
source .venv/bin/activate
python scripts/expand_midi.py path/to/input.mid path/to/output.mid --mode variation
```

可选参数：
- `--mode`: `continue`, `accompaniment`, `variation`, `emotion`
- `--analysis-json`: 写出 MIDI 特征分析结果
- `--extra-duration`: 生成的扩展时长（秒）

## 端到端回环

```bash
cd piano_dialogue_server/server
../.venv/bin/python test_client.py
```

## 备注

- 协议版本当前为 `1`
- 这个工作区只负责生成和调试，不负责 macOS / visionOS UI
- AVP 侧不再内置 PDF / 图片转 MusicXML 流程
