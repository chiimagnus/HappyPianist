# Plan P1 - 固定 Stage A 优化 Qwen

**Goal:** 在 P0 已收敛的单一 Qwen Companion service 和固定 Stage A 上，提高语义分离并记录决策时延；最终得到语义 Gate 结论或可重复的明确 blocker。

**Non-goals:** 不换模型，不改 P0 已修正并冻结的四语义 criteria、A/B 交换、threshold、mapping、corpus manifest 或 Gate；不微调/LoRA；不以增大 timeout 代替性能通过。P1 不再替 P0 修合同。

**Approach:** 先用 P0 固定 manifest 在 Windows RTX 4060 重建双跑 baseline；再把 server latency 拆成 prompt/render/tokenize、GPU batch forward、decode/mapping 与 HTTP overhead。当前 `_forward_full()` 已一次 batch 处理 8 questions，不再重复设计 batch；主要审查旧 Jev/Qwen prompt scaffold 是否制造无效 token 和交叉问题干扰。最多保留极少量预定义简化实验，最终只留一个实现。

**Acceptance:**
- 两次 baseline 的 corpus/case IDs、semantic scores 与 actions 可重复；
- 所有优化运行同一版本化 Stage A manifest，runner 无可改验收口径参数；
- 最终 automatic Gate 聚焦语义与 action 行为；Windows 本机 Qwen service RTT 继续完整记录，但不再作为 P1 自动失败条件，也不能替代 Vision Pro→Windows 局域网真机 RTT；
- Qwen server unit tests、semantic benchmark tests 与 smoke 持续通过；
- 实验 Prompt/临时代码不留在最终实现。

**Rules:**
- 固定本地 `Qwen3.5-0.8B-NF4-4bit` + CUDA；不保留 BF16 runtime/fallback；
- 一次请求仍只做一次 8-question batch model forward；
- 不恢复 generic classifier、第二模型、profile zoo 或 silent fallback；
- Stage A 输出保存在 ignored `.outputs`，不提交大结果。

---

## P1-T1 重建可重复 Qwen Stage A baseline

**Files:**
- Reuse unchanged: `python_backend/scripts/companion_semantic_benchmark.py`
- Reuse unchanged: `python_backend/tests/fixtures/companion_stage_a_manifest.json`
- Reuse: `python_backend/qwen_server/qwen_server/server.py`
- Evidence only: `python_backend/.outputs/companion-semantic-benchmark/`

**Step 1: 固定 Windows 环境**

在 Windows RTX 4060 使用与 Mac 同一 commit 启动当前 Qwen Companion service；health/smoke 必须报告固定 model/engine/protocol identity，CUDA 不可用直接停止。

**Step 2: 正常 Gate 模式运行 120-case x2**

runner 必须只接受 P0-T2 重建并提交的当前 Stage A manifest：new canonical corpus identity、projection version、errors=0、120 ordered case IDs/digest 必须全部匹配。不得把旧 `40645ac...` / `6abd632...` 历史 identity 写死回来，也不得提供/使用 bypass Gate。

**Step 3: 对比可重复性**

逐 case 比较 `semantic_scores`、`semantic_order_gaps`、`action`；同时比较 source/state medians 与 Gate reasons。latency 允许运行时抖动，但行为值若变化必须先定位随机源，不进入 Prompt 优化。

**Step 4: 建立新 baseline 结论**

2026-09-26 旧统一测试曾观察到 `listen=27 / support=6 / sparse=54 / yield=20 / respond=13` 与 RTT p95 约 1.16s，这只作 sanity check；P0 协议收敛后必须以当前双跑结果为新 baseline，不直接继承历史数字。

**Commit:** 无代码变更时不提交；通过 `todo.toml` note 与 P1 audit 记录 evidence identity/result。

---

## P1-T2 定位 Qwen 决策时延和 Prompt 冗余

**Files:**
- Modify only if long-term useful: `python_backend/qwen_server/qwen_server/server.py`
- Modify if prompt builder is separated there/shared module after P0: corresponding Qwen prompt source
- Modify: `python_backend/qwen_server/tests/test_qwen_server.py`
- Reuse unchanged: fixed Stage A runner/manifest

**Current evidence:**
- `_forward_full()` 已把 8 questions padding 后一次 forward，不能把“增加 batch”当优化。
- 当前旧 prompt scaffold 在每个 question 中注入全部 question instructions，又把 selected question 重复两次，并包含 `Think through ... step by step` 文案；这些都来自通用 classifier 历史，不属于 semantic contract。
- P0 后协议中的 `server_latency_ms` 是 request validation 之后到 action ready 的完整 server latency；benchmark 另测 HTTP RTT。P1 内部 profiler 再把 server latency 拆成 render/tokenize、tensor build、GPU forward、decode/mapping，不能把单独 GPU forward 时间重新冒充 server/RTT。

**Step 1: 分解真实热态成本**

用单调时钟在 Windows 本地测：request/schema、prompt render/tokenize、batch tensor build、GPU forward、A/B score decode/mapping、HTTP RTT。只记录聚合 timing，不记录原始 state/MIDI/Prompt 正文。

**Step 2: 核对 warm-up 是否覆盖产品 shape**

P0 已要求 warm-up 走同样 8-question batch；确认首个正式请求不再承担 batch shape/cuda cache 冷启动。如果仍有 cold-only 抖动，先修 warm-up 而不是提高 product timeout。

**Step 3: 只优化证据占比高的部分**

优先删除被证实无收益的通用包装：all-question reminder、重复 selected question、无生成需求的 reasoning 指令。固定 semantic instruction/criteria 文本本身不在本 task 调整。如果 GPU forward 已占绝对多数，停止 tokenizer/HTTP 微优化并记录。

**Step 4: 验证**

Run: Qwen server unit tests

Run: fixed Stage A

Expected: timing breakdown 可重复；任何保留的优化有实际 p50/p95 改善，且 semantic Gate 不比 P1-T1 baseline 退化。

**Step 5: 原子提交**

只提交有证据收益的最终 runtime/prompt simplification 与回归测试；临时 profiler/变体删除或保持 ignored。

---

## P1-T3 用同一 Stage A 收口 Qwen Gate

**Files:**
- Modify only if P1-T2 evidence justifies: current Qwen prompt/runtime implementation
- Modify corresponding Qwen unit tests
- Reuse unchanged: `python_backend/scripts/companion_semantic_benchmark.py`
- Reuse unchanged: `python_backend/tests/fixtures/companion_stage_a_manifest.json`

**Step 1: 最多比较基线与一个 compact prompt 形态**

如果 P1-T2 已证明旧 framing 是主要质量/性能变量，只允许一个清晰的 compact candidate 与当前 baseline 做固定 Stage A 对照；不得重新建立多 Profile 搜索、自动调参或大量 wording sweep。

**Step 2: Gate 决策**

通过必须同时满足 runner 当前全部 automatic Gate：
- 无 action collapse；
- P0 固定的 observable semantic boundaries 正确，尤其 active_sparse.space=true 与 active_dense.space=false；
- active_dense / settled_end / takeover_overlay 的行为 separation 正确；
- MAESTRO 与 POP909 **分别**通过适用于各自样本的同一 boundary Gate；source/state median 差异继续报告，但不做 pairwise automatic-fail；
- 五个 action 在合同层保持可达，实际 120-case 不要求人为凑齐固定比例；
- Windows localhost Qwen HTTP RTT p50/p95/max 继续记录为性能证据，但不再决定 P1 Gate；真机网络在 P2 单独验。

**Step 3: 失败停止条件**

如果最优已验证 framing 仍有 semantic blocker，保留表现更好的单一实现并把 P1 标 `blocked`；不要继续堆 Prompt。真实 RTT 继续记录 runtime/hardware/architecture 现状，但不再阻止 P1 收口或后续 P2 服务链验证。若后续需要微调或改 decision cadence/异步架构，另开 feature。

**Step 4: 最终复跑 x2**

最终保留实现必须再完整双跑，确认行为可重复、Gate reason 稳定、manifest 未变化。

**Step 5: 原子提交**

有代码差异则只提交最终实现和测试；无代码差异只记录 evidence。

---

## Phase Audit

- Audit file: `audit-p1.md`
- Rule: 审计必须确认 P0 冻结后的 manifest/semantic/Gate 没被为了过测试而改动，Windows 结果来自真实固定 Qwen CUDA service；不得重新引入 cross-source pairwise fake truth、隐藏 Prompt profile、模型 fallback 或放宽 latency Gate。
- Required verification: 运行 Qwen server 全部 unit/protocol tests、Companion semantic/corpus tests、service smoke，以及最终 fixed Stage A x2。若本 phase 未改 Swift，不把 `make test:simulator` 伪装成必要证据；若实际触及 Swift consumer，则补跑 AGENTS 规定的 `make doctor`、`make destinations`、`make build:simulator`、`make test:simulator`。
- Docs sync: 若 P1 更新 canonical testing/AI 文档，同步刷新 `docs/GENERATION.md` 的 source commit 与真实 evidence。
