# 本机 Python：piano_dialogue_server

这里是 LonelyPianist 的本地推理工作区，提供 Piano Dialogue 所需的 HTTP / WebSocket 生成接口，以及本地 MIDI 上传扩展工具。

## 它做什么

- `GET /health`：健康检查
- `GET /`：若存在 `static/index.html`，则返回前端页面
- `POST /generate`：标准 HTTP 生成接口，接收 `generate` 请求并返回结果
- `WS /ws`：接收 `generate` 请求并返回回复音符
- `POST /upload-expand`：上传 MIDI，生成扩展后的 MIDI（算法或模型），并以 base64 返回给前端下载
- `server/debug_artifacts.py`：在调试模式下写出 request / response / MIDI / summary bundle
- Bonjour（mDNS/DNS-SD）：服务启动时广播 `_lonelypianist._tcp.local.`，便于局域网客户端（例如 AVP）自动发现

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

注意：
- `WS /ws` 在 `strategy=deterministic` 时不会初始化模型引擎；但若你用 `strategy=model`，仍会触发模型初始化。
- 离线验证脚本可能会触发模型加载；如果你只想验证“轻量 deterministic”，优先起服务后直接调用 `POST /generate`。

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

备注：`--host 0.0.0.0` 便于同一局域网内的设备访问（例如 AVP）。若你只在本机测试，也可用 `--host 127.0.0.1`。

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

## Bonjour 广播（自动发现）

服务启动后会广播 `_lonelypianist._tcp.local.`（端口 8765），并在 TXT record 里包含最小属性（例如 `path=/generate`）。

用 macOS 自带工具查看：

```bash
dns-sd -B _lonelypianist._tcp local.
dns-sd -L "<instance>" _lonelypianist._tcp local.
```

## 给 AVP（visionOS）使用的最小测试路径

1. Mac 上按上面的方式启动服务（建议 `--host 0.0.0.0`）。
2. 确保 Mac 与 Apple Vision Pro / visionOS Simulator 在同一网络（你用手机热点是可行的）。
3. 首次连接时，AVP 端需要允许 Local Network 权限；否则 Bonjour 发现会显示为 denied。

## 离线验证

```bash
cd piano_dialogue_server
source .venv/bin/activate
python scripts/test_generate.py
python scripts/test_infilling.py
```

备注：离线验证脚本会尝试加载模型；如果你只想验证“轻量 deterministic”，直接起服务并调用 `POST /generate`（`deterministic`）更快。

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
