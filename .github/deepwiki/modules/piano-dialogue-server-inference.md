# Python Inference

## 范围
这页讲三种生成策略的实现位置与关键逻辑：`model`（神经网络）、`deterministic`（现有算法/分析）、`rule`（规则即兴器）。

## 关键逻辑
| 逻辑 | 行为 |
| --- | --- |
| `_resolve_model_ref()` | `AMT_MODEL_DIR` 优先，其次仓库内 `models/music-large-800k`，最后 `AMT_MODEL_ID`（`server/engines/model_inference.py`） |
| `_resolve_device()` | `AMT_DEVICE` > mps > cuda > cpu（`server/engines/model_inference.py`） |
| `_patch_safe_logits()` | 屏蔽非法 REST token 组合（`server/engines/model_inference.py`） |
| `InferenceEngine.generate_response()` | `strategy=model`：模型生成 reply notes（`server/engines/model_inference.py`） |
| `InferenceEngine.generate_response_with_debug()` | `strategy=model`：模型生成 + debug 统计（`server/engines/model_inference.py`） |
| `generate_deterministic_response()` | `strategy=deterministic`：基于 `media/midi_generation.generate_expanded_midi` 做轻量续写，并把返回时间轴平移到从 0 开始（`server/engines/model_inference.py`） |
| `generate_rule_response()` | `strategy=rule`：把协议 `DialogueNote` 转成 `media/midi_utils.NoteEvent`，调用 `run_rule_improviser`，再转回协议 notes（`server/engines/rule_inference.py`） |
| `run_rule_improviser(...)` | 规则即兴器核心（和声/节奏/动机规则 + 风格 preset），产出 `RuleResult`（`server/engines/rule_backend.py`） |
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

## 与 API 的连接点
- `POST /generate` 与 `WS /ws` 的策略分流在 `server/api/main.py`（`params.strategy`）。
- 仅当 `strategy=model` 时会初始化模型引擎；`deterministic` 与 `rule` 都不会加载权重。

## Coverage Gaps
- 没有高并发或长时间运行的压力测试证据。
- deterministic 分支的音乐质量与参数选择更多依赖手工体验（同一 prompt 的可预期性优先于多样性）。
- rule 分支的风格/参数目前固定（例如 style=pop, mode=motif），缺少面向产品的配置面板与回归基线。
