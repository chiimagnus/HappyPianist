# Audit P2 - companion-laya-mlx

- 审计范围：`plan-p2.md`
- feature 目录：`.github/features/companion-laya-mlx/`
- 粒度：`phase`
- 结论：`No-Go`

## 任务看板

- [x] P2-T1 将 Swift Jev 接入整体替换为 Laya
- [!] P2-T2 建立统一 Companion 二元语义 benchmark 并重测 Laya（Blocked）

## 统一评测协议

为保证 Laya 与后续 Qwen 使用同一口径，P2-T2 已改成模型无关的 `observable-binary-v1-order-balanced`：

1. 同一 compact structured MIDI state；不含 `recent_notes`。
2. 同一 4 个二元语义：`continuing / finished / space / reasserted`。
3. 每个语义使用相同 instructions/criteria，同时按 `false,true` 和 `true,false` 两种 option order 请求。
4. 先按语义标签对齐，再平均两个顺序的 `true` probability。
5. 同一 `semantic_threshold=0.55`。
6. 同一确定性 `semantic-v1` action mapping；`support/sparse` 只由 density `2.0` 阈值区分。
7. 同一 `seed=20260920`、同一 120 cases、同一 ordered case IDs、同一 MAESTRO/POP909 corpus、同一 Gate。
8. 后续切到 Qwen 时只能更换 classifier server/model，不能改 state、问题、阈值、mapping、样本或 Gate。

## 已完成证据

### P2-T1

- Swift 产品调用链已切换为 `LayaClassifierClient` + `LayaNetworkCompanionDecisionBackend`。
- 产品与测试旧 `Jev` companion 符号扫描为 0。
- `make build:simulator` -> PASS。
- Laya/companion 定向测试 -> 8/8 PASS。
- compact-state 后核心 Laya 定向测试 -> 4/4 PASS。
- 提交：`29848940`、`19c46b78`。

### P2-T2

- 固定 corpus：1276 MAESTRO + 909 POP909 = 2185 MIDI，errors=0。
- raw LF SHA256：`b1ea445712d563d8ef8facc3cf9c66c272f261382666b0f5bddf17e7b818971d`。
- canonical JSON SHA256：`40645ac15205f8d3a85067daf4ddb9adb062ff53eddb8ed39c3d35d1b87d6569`。
- 历史 Windows SHA 与当前语义内容差异仅为 CRLF/LF；转 CRLF 后精确恢复历史 SHA。
- 模型无关 semantic protocol + benchmark：`4bcc70fc`。
- Python 统一 benchmark/corpus/Laya adapter tests：14/14 PASS。

## 发现项

### F-01 - recent notes 使 state 过长

- 严重级别：`Medium`
- 状态：`Resolved`
- 120 cases 中 76 个原始 state 超过 1000 tokens；典型 dense/takeover 约 1250-1287 tokens。
- 去掉逐音符明细后约 170-200 tokens，且不降低当时 direct-action 结果。
- 已从产品与 benchmark 数据链删除；`19c46b78`。

### F-02 - 旧 Laya 直接五分类测试不能作为模型级比较结论

- 严重级别：`High`
- 状态：`Resolved`
- 旧实验让 Laya 直接 `listen/support/sparse/yield/respond` 五选一，而此前 Qwen 路线是多个二元语义 + 确定性 mapping；两者任务定义不同。
- `120/120 listen` 仍保留为“直接五分类方案失败”的诊断证据，但撤销其作为“Laya 模型整体不适合”的依据。
- 修复：建立上述统一二元语义协议，并重新执行完整 Laya Stage A。

### F-03 - 统一二元语义协议下 Laya 仍未通过 Stage A

- 严重级别：`Blocker`
- 状态：`Unresolved`
- 完整 120-case actions：`listen=77 / sparse=12 / support=11 / yield=20 / respond=0`。
- 关键 semantic medians：
  - `active_dense.continuing=0.165`，预期 `>=0.55`。
  - `active_dense.reasserted=0.575`，AI 未播放时预期 `<0.55`。
  - `active_sparse.continuing=0.398`，预期 `>=0.55`。
  - `settled_end.finished=0.115`，预期 `>=0.55`。
  - `sustain_pause.continuing=0.455`，预期 `>=0.55`。
  - `takeover_overlay.reasserted=0.949`，这一条边界通过，20/20 映射为 `yield`。
- `respond=0`，因此 `settled_end` 没有高于 `active_dense` 的 respond separation。
- MAESTRO/POP909 出现 3 个方向冲突：`active_sparse.continuing`、`active_sparse.space`、`sustain_pause.continuing`。
- option-order 仍非常敏感：例如非 takeover state 的 `reasserted` order-gap median 约 0.64-0.80，`space` 约 0.53-0.75；双顺序平均只能中和，不能消除模型自身的不稳定判断。
- round-trip P95 两次完整运行约 `2228.6 ms` 与 `1491.1 ms`，都超过产品 `1s` Gate。
- 可重复性：两次完整 120-case 的 ordered case IDs、canonical corpus SHA、全部 semantic scores、全部 actions 完全一致。只有 latency P95 因运行时抖动不同，但两次都失败。

## 验证日志

- `pytest test_companion_semantic_benchmark.py test_companion_acceptance_corpus.py test_companion_laya.py` -> PASS `14/14`。
- 完整统一 Stage A #1 -> semantic/action Gate No-Go；round-trip p95 `2228.6 ms`。
- 完整统一 Stage A #2 -> semantic/action 结果逐项完全一致；round-trip p95 `1491.1 ms`。
- `rtk git diff --check` -> PASS。

## Gate（是否允许进入下一阶段）

- 结论：`No-Go`
- 这次 No-Go 是在与后续 Qwen 可直接复用的统一二元语义协议下得到的，不再基于不公平的五分类对比。
- P3-T1/P3-T2/P3-T3 保持 `pending`。

## 剩余决策

Laya 已按统一口径重新测试。下一步如果比较 Qwen，必须直接运行同一个 `companion_semantic_benchmark.py`，不得修改任何 state、semantic questions、双顺序聚合、mapping、样本或 Gate；这样结果才有可比性。
