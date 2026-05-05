# Python Protocol

## 范围
这页只讲协议，不讲推理。

## 数据模型
| 模型 | 字段 |
| --- | --- |
| `DialogueNote` | `note`, `velocity`, `time`, `duration` |
| `GenerateParams` | `top_p`, `max_tokens`, `strategy` |
| `GenerateRequest` | `type`, `protocol_version`, `notes`, `params`, `session_id` |
| `ResultResponse` | `type`, `protocol_version`, `notes`, `latency_ms` |
| `ErrorResponse` | `type`, `protocol_version`, `message` |

## 协议约束
- `type` 固定为 `generate` / `result` / `error`。
- `protocol_version` 固定为 `1`。
- `extra="ignore"` 允许兼容扩展字段。

## 序列化边界
| 方向 | 说明 |
| --- | --- |
| macOS -> Python | JSON 编码后经 WS 发送 |
| AVP -> Python | JSON 编码后经 HTTP `POST /generate` 发送（host/port 通过 Bonjour 解析得到） |
| Python -> macOS | JSON 文本或 binary 都可解析 |

## 生成策略（`GenerateParams.strategy`）
| 值 | 行为 | 成本 |
| --- | --- | --- |
| `deterministic` | 走本地规则/分析生成（不初始化大模型） | 更轻、更稳定 |
| `model` | 初始化并使用模型生成 | 更重，受权重/设备影响 |

## 更新记录（Update Notes）
- 2026-05-05: 同步 `GenerateParams.strategy` 字段与 HTTP `/generate` 调用方向。


## Coverage Gaps
- 协议没有版本协商；当前只按 `protocol_version=1` 运行。
