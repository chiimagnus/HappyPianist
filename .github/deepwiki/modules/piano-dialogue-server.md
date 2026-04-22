# 模块：piano_dialogue_server（Dialogue 服务）

## 职责与边界
- **负责**：
  - 提供 WebSocket `/ws` 对话推理协议；
  - 提供 `GET /health` 健康检查；
- **不负责**：macOS/AVP UI、CoreMIDI 采集、客户端状态管理。
- **位置**：`piano_dialogue_server/server/`。

## 目录范围
| 路径 | 角色 | 备注 |
| --- | --- | --- |
| `server/main.py` | FastAPI 入口与 WS 主循环 | parse/validate/generate/send |
| `server/protocol.py` | Pydantic 契约定义 | 请求/响应字段边界 |
| `server/inference.py` | 推理引擎与模型加载 | `AutoModelForCausalLM` + anticipation |
| `server/debug_artifacts.py` | 调试包落盘 | `DIALOGUE_DEBUG=1` 生效 |
| `server/test_client.py` | 端到端客户端 | 构造请求并保存 reply.mid |

## 入口点与生命周期
| 入口 / 类型 | 位置 | 何时触发 | 结果 |
| --- | --- | --- | --- |
| 服务进程入口 | `uvicorn server.main:app` | 进程启动 | FastAPI app 可响应健康检查与 WS |
| WS 消息处理 | `main.py::ws_endpoint` | 客户端发 `type=generate` | 返回 `type=result` 或 `type=error` |
| 模型初始化 | `get_inference_engine()` | 首次 generate 请求 | 懒加载模型并缓存 `_engine` |
| 调试包写入 | `write_debug_bundle()` | `DIALOGUE_DEBUG=1` 且请求成功 | 落盘 request/response/midi/summary |

## 关键文件
| 文件 | 用途 | 为什么值得看 |
| --- | --- | --- |
| `main.py` | 服务主循环与错误处理 | 定义协议入口和容错策略 |
| `protocol.py` | 数据契约 | 客户端兼容性根基 |
| `inference.py` | 推理核心 | 模型选择、设备选择、事件转换 |
| `debug_artifacts.py` | 可观测性 | 排障首选证据落点 |
| `test_client.py` | 自测工具 | 快速验证服务链路可用 |

## 上下游依赖
| 方向 | 对象 | 关系 | 影响 |
| --- | --- | --- | --- |
| 上游 | macOS WebSocket 客户端 | 发送 generate 请求 | 请求格式不兼容会直接失败 |
| 下游 | `transformers` 模型 | 生成 reply notes | 权重缺失会阻断服务能力 |
| 下游 | `anticipation.sample` | 事件采样 | token 逻辑直接影响输出质量 |
| 下游 | 本地文件系统 | debug/输出文件落盘 | 磁盘权限与空间影响调试能力 |

## 对外接口与契约
| 接口 / 命令 / 类型 | 位置 | 调用方 | 含义 |
| --- | --- | --- | --- |
| `GET /health` | `server/main.py` | macOS / 运维脚本 | 服务可用性探针 |
| `WS /ws` | `server/main.py` | `WebSocketDialogueService` | 对话请求与回复通道 |
| `GenerateRequest` | `server/protocol.py` | WS 客户端 | 包含 `notes/params/session_id` |
| `ResultResponse` | `server/protocol.py` | WS 服务端 | 返回回复 notes 与延迟 |
| `ErrorResponse` | `server/protocol.py` | WS 服务端 | 结构化错误反馈 |

## 数据契约、状态与存储
- 请求契约：
  - `type = "generate"`
  - `protocol_version = 1`
  - `notes: list[DialogueNote]`
  - `params.top_p/max_tokens`
- 推理状态：
  - 全局 `_engine` 缓存模型，减少重复加载。
- 输出存储：
  - 常规响应走 WS；
  - debug 开启时落盘到 `out/dialogue_debug/`。

## 配置与功能开关
- `AMT_MODEL_DIR`：本地模型目录（最高优先级）。
- `AMT_MODEL_ID`：模型 ID（当本地目录不存在时）。
- `AMT_DEVICE`：`mps/cuda/cpu`。
- `DIALOGUE_DEBUG=1`：开启调试工件。
- `HF_ENDPOINT`：默认会设为 `https://hf-mirror.com`（可覆盖）。

## 正常路径与边界情况
- 正常路径：接收 JSON -> 校验 -> 获取引擎 -> 生成 reply -> 发送 result。
- 边界情况：
  - 非 JSON/非法 payload：返回 `ErrorResponse`。
  - 非 `generate` type：返回 unsupported type。
  - 模型目录存在但无权重：抛显式错误并返回给客户端。
  - debug 写盘失败：仅打印日志，不破坏主流程。

## 扩展点与修改热点
- 扩展点：
  - 引入更多生成参数（需同步 protocol + 客户端）。
  - 支持多模型切换与会话策略。
  - 加入请求队列/限流。
- 修改热点：
  - `inference.py` 事件映射与 safe_logits patch。
  - `main.py` WS 主循环错误分支。

## 测试与调试
- 调试命令：
  - `curl -s http://127.0.0.1:8765/health`
  - `cd server && ../.venv/bin/python test_client.py`
- 调试文件：
  - `out/dialogue_debug/index.jsonl`
  - `out/dialogue_debug/requests/<req_id>/summary.json`
- 离线脚本：
  - `scripts/test_generate.py`
  - `scripts/test_infilling.py`

## 示例片段
```python
if message_type != "generate":
    await websocket.send_json(
        ErrorResponse(message=f"unsupported type: {message_type!r}").model_dump()
    )
    continue
```

```python
if Path(model_ref).is_dir():
    has_weights = any(model_path.glob("*.safetensors")) or any(model_path.glob("pytorch_model*.bin"))
    if not has_weights:
        raise RuntimeError(f"Model directory exists but weights not found: {model_ref}")
```

## Coverage Gaps
- 当前无并发压测数据，吞吐与高并发行为未结构化验证。
- 会话级上下文（`session_id`）目前未做复杂记忆机制，能力边界需在产品层明确。
