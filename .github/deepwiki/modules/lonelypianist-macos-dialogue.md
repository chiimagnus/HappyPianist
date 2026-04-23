# macOS Dialogue

## 范围
Dialogue 页覆盖 turn-based 对话状态机、静默触发、回放策略和 take 落盘。

## 关键对象
| 对象 | 职责 |
| --- | --- |
| `DialogueManager` | 会话编排与状态机 |
| `WebSocketDialogueService` | WS 客户端 |
| `DefaultSilenceDetectionService` | 静默检测 |
| `DialoguePlaybackInterruptionBehavior` | 回放期间输入策略 |

## 状态机
| 状态 | 说明 |
| --- | --- |
| `idle` | 未开启对话 |
| `listening` | 收集人类演奏 |
| `thinking` | 请求 Python 生成中 |
| `playing` | AI 回放中 |

## 行为
- 静默检测轮询间隔是 80ms。
- `ignore / interrupt / queue` 三种策略可持久化。
- AI reply 会写成 `RecordingTake`。
- 结束时会保存整个 session take。

## 协议
- 请求类型固定为 `generate`。
- 协议版本固定为 `1`。
- payload 带 `notes`、`params` 和 `session_id`。

## 调试抓手
- `dialogueStatus`
- `dialogueLatencyMs`
- `statusMessage`
- `recentLogs`
- Python `health` 和 `test_client.py`


## Coverage Gaps
- 会话记忆仍是单轮/短上下文，没有额外长期记忆机制。

