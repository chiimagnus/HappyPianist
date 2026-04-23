# Python Protocol

## 范围
这页只讲协议，不讲推理。

## 数据模型
| 模型 | 字段 |
| --- | --- |
| `DialogueNote` | `note`, `velocity`, `time`, `duration` |
| `GenerateParams` | `top_p`, `max_tokens` |
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
| Python -> macOS | JSON 文本或 binary 都可解析 |


## Coverage Gaps
- 协议没有版本协商；当前只按 `protocol_version=1` 运行。

