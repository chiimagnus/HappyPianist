# 模块：piano_dialogue_server

## 边界
- 负责：`GET /health`、`WS /ws`、协议校验、推理和调试包。
- 不负责：macOS / AVP UI。

## 目录地图
| 路径 | 角色 |
| --- | --- |
| `server/main.py` | FastAPI / WS 入口 |
| `server/protocol.py` | Pydantic 契约 |
| `server/inference.py` | 模型加载和生成 |
| `server/debug_artifacts.py` | 调试落盘 |
| `server/test_client.py` | WS 回环测试 |

## 入口与生命周期
| 入口 | 行为 |
| --- | --- |
| `/health` | 返回 `{"status":"ok"}` |
| `/ws` | 收到 `generate` 请求后返回 `result` / `error` |
| `get_inference_engine()` | 懒加载并缓存模型 |
| `write_debug_bundle()` | 在 debug 开启时落盘工件 |

## 重要子页
- [Protocol](modules/piano-dialogue-server-protocol.md)
- [Inference](modules/piano-dialogue-server-inference.md)
- [Debug artifacts](modules/piano-dialogue-server-debug.md)

## 风险点
- 模型目录存在但缺权重
- 安全 logits patch
- debug 写盘失败


## Coverage Gaps
- 没有并发压测和高负载稳定性数据。

