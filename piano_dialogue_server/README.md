# piano_dialogue_server

本目录是 LonelyPianist 的本地 Python 后端，提供 AI 即兴生成与 Bonjour 广播（仅保留模型推理路径）。

## API

| API | 说明 |
| --- | --- |
| `GET /health` | 健康检查。 |
| `GET /` | 返回 `static/index.html` 或 fallback HTML。 |
| `POST /generate` | 接收 `GenerateRequest`，返回 `ResultResponse`。 |
| `WS /ws` | WebSocket 生成接口。 |

调试包由 `server/media/debug_artifacts.py` 写入，不是旧路径 `server/debug_artifacts.py`。

## 启动

```bash
cd piano_dialogue_server
./scripts/run_server.sh
```

脚本默认使用 `PYTHON=${PYTHON:-python3.12}`，创建 `.venv`，安装 `requirements.txt`，并启动：

```bash
python -m uvicorn server.api.main:app --host 0.0.0.0 --port 8765
```

健康检查：

```bash
curl -s http://127.0.0.1:8765/health
```

## 生成策略

`POST /generate` 与 `WS /ws` 使用 `params.strategy`：

| strategy | 是否加载大模型 | 说明 |
| --- | --- | --- |
| `model` | 是 | 加载 anticipation / transformers / torch 模型。 |
（`rule` / `deterministic` 已迁移到 SwiftPM：`Packages/ImprovEngines/`。）

## 环境变量

| 变量 | 作用 |
| --- | --- |
| `AMT_MODEL_DIR` | 本地模型目录。 |
| `AMT_MODEL_ID` | Hugging Face 模型 ID，默认 `stanford-crfm/music-large-800k`。 |
| `AMT_DEVICE` | `mps` / `cuda` / `cpu`。 |
| `HF_ENDPOINT` | Hugging Face 镜像地址。 |
| `DIALOGUE_DEBUG` | 设为 `1` 时写调试包到 `out/dialogue_debug/`。 |

## HTTP 示例

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
      "strategy": "model"
    }
  }'
```

## Bonjour

服务启动时 best-effort 广播 `_lonelypianist._tcp.local.`，port `8765`，properties 包含 `path=/generate`、`protocol_version=1`。AVP 真机访问时，Mac 与 Apple Vision Pro 需要在同一局域网内，并允许 Local Network 权限。

## 离线脚本

```bash
python scripts/test_generate.py
python scripts/test_infilling.py
```

这些脚本可能触发模型加载；只验证服务端链路时，直接调用 `strategy=model` 即可。
