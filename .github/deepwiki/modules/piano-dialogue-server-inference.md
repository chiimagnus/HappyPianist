# Python Inference

## 范围
这页讲模型加载、设备选择、safe logits patch、事件转换和返回值构造。

## 关键逻辑
| 逻辑 | 行为 |
| --- | --- |
| `resolve_model_ref()` | 本地目录优先，其次 `AMT_MODEL_ID` |
| `resolve_device()` | `AMT_DEVICE` > mps > cuda > cpu |
| `_patch_safe_logits()` | 屏蔽非法 REST token 组合 |
| `generate_response()` | 生成 reply notes |
| `generate_response_with_debug()` | 生成 + debug 统计 |

## 输出约束
- 只接受 piano instrument。
- 只允许 MIDI 21..108。
- 负时间和短事件会被丢弃。
- 默认 velocity 从 prompt 均值推导。

## 调试统计
| 字段 | 含义 |
| --- | --- |
| `prompt_end_sec` | 输入结束时间 |
| `effective_start_sec` | 生成起点 |
| `generated_events_len` | 输出 token 数 |
| `dropped_notes` | 丢弃原因统计 |
| `generate_ms` | 推理耗时 |


## Coverage Gaps
- 没有高并发或长时间运行的压力测试证据。

