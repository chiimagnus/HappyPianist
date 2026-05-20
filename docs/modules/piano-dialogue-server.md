# Module: piano_dialogue_server

`piano_dialogue_server/` 是本地 FastAPI 服务，为 AVP AI 即兴和浏览器 MIDI 扩展工具提供接口。

## 入口与目录

| 位置 | 说明 |
| --- | --- |
| `piano_dialogue_server/server/api/main.py` | FastAPI app、路由、lifespan Bonjour。 |
| `piano_dialogue_server/server/api/protocol.py` | `DialogueNote`、`GenerateRequest`、`ResultResponse`、`ErrorResponse`。 |
| `piano_dialogue_server/server/engines/` | model、deterministic、rule 生成。 |
| `piano_dialogue_server/server/media/` | MIDI/MusicXML 处理、Bonjour、debug artifacts。 |
| `piano_dialogue_server/static/` | `GET /` 返回的本地 playground。 |
| `piano_dialogue_server/scripts/run_server.sh` | 创建 venv、安装依赖、启动服务。 |

## API

| API | 输入 | 输出 | 说明 |
| --- | --- | --- | --- |
| `GET /health` | 无 | `{"status":"ok"}` | 健康检查。 |
| `GET /` | 无 | HTML | 返回 `piano_dialogue_server/static/index.html` 或 fallback HTML。 |
| `POST /generate` | JSON `GenerateRequest` | `ResultResponse` | 标准生成接口。 |
| `WS /ws` | JSON `GenerateRequest` | `ResultResponse` 或 `ErrorResponse` | WebSocket 生成接口。 |
| `POST /upload-expand` | multipart MIDI + strategy/mode | base64 MIDI + analysis | 浏览器上传 MIDI 扩展。 |

`protocol_version` 当前为 `1`。`GenerateParams.strategy` 只接受 `model`、`deterministic`、`rule`。

## 策略

| strategy | 行为 |
| --- | --- |
| `rule` | 使用规则即兴器，适合轻量本地验证。 |
| `deterministic` | 使用确定性生成路径，适合不加载模型的验证。 |
| `model` | 加载 anticipation / transformers / torch 模型。 |

`/upload-expand` 的 multipart `strategy` 使用 `algorithm` 或 `model`，不要与 `/generate` 的 `strategy` 字段混淆。

## Bonjour

服务启动时 best-effort 广播：

- instance name：`LonelyPianist Dialogue Server`
- service type：`_lonelypianist._tcp.local.`
- port：`8765`
- properties：`path=/generate`、`protocol_version=1`、`supports_deterministic=1`

Bonjour 失败不阻止 HTTP 服务启动；AVP 自动发现会受影响。

## 调试

`DIALOGUE_DEBUG=1` 时，`piano_dialogue_server/server/media/debug_artifacts.py` 会写出 request、response、MIDI 和 summary bundle 到：

```text
piano_dialogue_server/out/dialogue_debug/
```

## 验证

```bash
cd piano_dialogue_server
./scripts/run_server.sh
curl -s http://127.0.0.1:8765/health
```

轻量生成示例使用 `strategy=rule` 或 `strategy=deterministic`，避免触发模型加载。
