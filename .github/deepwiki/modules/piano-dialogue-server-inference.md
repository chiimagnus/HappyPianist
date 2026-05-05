# Python Inference

## 范围
这页讲模型加载、设备选择、safe logits patch、事件转换和返回值构造。

## 关键逻辑
| 逻辑 | 行为 |
| --- | --- |
| `_resolve_model_ref()` | `AMT_MODEL_DIR` 优先，其次仓库内 `models/music-large-800k`，最后 `AMT_MODEL_ID` |
| `_resolve_device()` | `AMT_DEVICE` > mps > cuda > cpu |
| `_patch_safe_logits()` | 屏蔽非法 REST token 组合 |
| `InferenceEngine.generate_response()` | 模型生成 reply notes |
| `InferenceEngine.generate_response_with_debug()` | 模型生成 + debug 统计 |
| `generate_deterministic_response()` | 基于 `midi_generation.generate_expanded_midi` 做轻量 deterministic 续写，并把返回时间轴平移到从 0 开始 |
| `_derive_response_length_sec()` | 将协议 `max_tokens` 映射为 “续写时长（秒）” 的启发式窗口 |

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
- deterministic 分支的音乐质量与参数选择更多依赖手工体验（同一 prompt 的可预期性优先于多样性）。
