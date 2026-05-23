# Module: piano_dialogue_server

`piano_dialogue_server/` 是本地 FastAPI 服务，为 AVP 的 **可选网络后端** 提供 `/generate` / `/ws` 推理接口。本地规则生成已迁移到 SwiftPM（`Packages/ImprovEngines/`），服务端仅保留模型推理。

## 入口与目录

| 位置 | 说明 |
| --- | --- |
| `piano_dialogue_server/server/api/main.py` | FastAPI app、路由、lifespan Bonjour。 |
| `piano_dialogue_server/server/api/protocol.py` | `DialogueNote`、`GenerateRequest`、`ResultResponse`、`ErrorResponse`。 |
| `piano_dialogue_server/server/engines/` | model 生成（anticipation / transformers / torch）。 |
| `piano_dialogue_server/server/media/` | Bonjour、debug artifacts。 |
| `piano_dialogue_server/static/` | `GET /` 返回的本地 playground。 |
| `piano_dialogue_server/scripts/run_server.sh` | 创建 venv、安装依赖、启动服务。 |

## API

| API | 输入 | 输出 | 说明 |
| --- | --- | --- | --- |
| `GET /health` | 无 | `{"status":"ok"}` | 健康检查。 |
| `GET /` | 无 | HTML | 返回 `piano_dialogue_server/static/index.html` 或 fallback HTML。 |
| `POST /generate` | JSON `GenerateRequest` | `ResultResponse` | 标准生成接口。 |
| `WS /ws` | JSON `GenerateRequest` | `ResultResponse` 或 `ErrorResponse` | WebSocket 生成接口。 |

`protocol_version` 当前为 `1`。`GenerateParams.strategy` 只接受 `model`。

AVP 的 Swift 协议额外支持可选 `seed` 字段；server 侧目前会忽略未知字段（兼容旧协议，不保证使用 seed）。

## Bonjour

服务启动时 best-effort 广播：

- instance name：`LonelyPianist Dialogue Server`
- service type：`_lonelypianist._tcp.local.`
- port：`8765`
- properties：`path=/generate`、`protocol_version=1`

Bonjour 失败不阻止 HTTP 服务启动；AVP 自动发现会受影响。

## 调试

`DIALOGUE_DEBUG=1` 时，`piano_dialogue_server/server/media/debug_artifacts.py` 会写出 request、response、prompt/reply notes 与 summary bundle 到：

```text
piano_dialogue_server/out/dialogue_debug/
```

## 验证

```bash
rtk sh -lc 'cd piano_dialogue_server && ./scripts/run_server.sh'
rtk curl -s http://127.0.0.1:8765/health
```

服务端仅支持 `strategy=model`，会触发模型加载。
