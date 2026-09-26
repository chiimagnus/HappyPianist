# Plan P2 - Prompt 实验与可复现评估

**Goal:** 在不微调 Qwen3.5-0.8B 的前提下，用固定真实 MIDI 样本系统比较 Prompt / semantic decomposition，确定 Prompt-only 是否足够改善陪伴决策。

**Non-goals:** 不把 MAESTRO/POP909 自然状态伪装成人工标签；不在本阶段改 Swift 产品决策；不因某组分布“看起来舒服”就宣称准确。

**Approach:** 先固定 corpus index、抽样 seed 与 semantic-to-action 映射，再运行 Stage A 小样本筛选。只有未发生明显 collapse、关键边界行为有改善且跨来源方向一致的候选进入 Stage B 600-case。实验保存 per-case semantic scores、action、latency 和 profile 元数据。

**Acceptance:**
- 2185 首 MIDI 候选索引可复现，状态不变量全部通过。
- 全部 Prompt profile 在 Stage A 使用同一 case IDs。
- Stage B 最多两个候选在同一固定 600-case 上比较。
- 最终形成可复现实验证据：选定可用 profile/schema，或明确 Prompt-only 仍不足。

**Rules:**
- 无人工 turn-taking 标签的状态只报告行为分布。
- takeover_overlay 始终标 synthetic。
- 不用单一总分掩盖状态间取舍。
- 调 Prompt 时不得同时修改模型、样本或动作映射。

---

## P2-T1 固定大规模 MIDI 状态语料与抽样不变量

**Files:**
- Modify: python_backend/scripts/companion_acceptance_corpus.py
- Modify: .gitignore

**Current evidence:**
- 本地已有 MAESTRO v3 1276 主 MIDI + POP909 909 主 MIDI。
- 之前出现过候选初始满足 dense、最终采样点越过下一 onset 的 bug，因此最终 candidate 自校验是必要不变量。

**Step 1: 固定状态定义**

编码 active_dense / active_sparse / sustain_pause / natural_silence / settled_end(or piece_end) / takeover_overlay 的可观测条件和 provenance。

**Step 2: 最终候选自校验**

候选生成后再次检查 density / next-onset / sustain / held notes 等条件；不满足直接拒绝。

**Step 3: 全量运行**

Run corpus index over 2185 MIDI with fixed parameters.

Expected: 全部文件解析完成且 0 error；输出含 source/state/file/timestamp/provenance；datasets/outputs 保持 gitignored。

**Step 4: 原子提交**

只提交语料索引逻辑与忽略规则。

---

## P2-T2 建立两阶段 Prompt benchmark

**Files:**
- Modify: python_backend/shared/companion_prompt_profiles.py
- Modify: python_backend/scripts/companion_prompt_benchmark.py
- Modify: python_backend/scripts/companion_e2e_acceptance.py

**Step 1: 固定 semantic decomposition**

优先测试独立语义判断（如 continuing / finished / space / reasserted）而不是直接五选一。semantic -> CompanionAction 的 deterministic mapping 必须集中在单一函数并可测试。

**Step 2: 定义真正不同的 Prompt profiles**

至少覆盖 direct/basic、observable-only、observable+boundaries/thresholds、example-driven、conservative。删除只有措辞差异、决策边界相同的重复 profile。

**Step 3: Stage A 小样本筛选**

固定 seed 和 case IDs，对全部 profile 跑相同分层样本。输出 semantic/action 分布、来源/状态分布、takeover reasserted/yield、dense finished/respond、sustain continuing/finished、latency 和 collapse。

**Step 4: Stage A 停止条件**

淘汰：几乎全部 case 收敛到一个动作/极端 semantic score；takeover 不提高 reasserted/yield；dense active 大量判 finished/respond；MAESTRO/POP909 行为方向相反且无音乐解释。

若 Stage A 无任何合格候选，本 task 输出“Prompt-only 暂不足”的证据并停止，不强行进入 Stage B。

**Step 5: 原子提交**

只提交 Prompt profile、benchmark 和 deterministic mapping。

---

## P2-T3 对 Stage A 候选运行固定 600-case 并形成结论

**Files:**
- Modify: python_backend/scripts/companion_prompt_benchmark.py
- Evidence only: python_backend/.outputs/（不入 Git）

**Step 1: 固定 600-case**

每来源 × 每状态 × 50，使用同一 corpus index、seed 和 case IDs。

**Step 2: 运行候选 profile**

只跑 Stage A 通过的最多两个候选；记录 per-case 与 summary。

**Step 3: 分维度比较**

分别比较关键状态行为、跨来源稳定性、confidence/Noul 分布和 latency；不输出单一“总冠军分数”。

**Step 4: 实验决策**

若某 profile/schema 在关键边界稳定改善且无新 collapse，记录为 P3 产品接入候选；否则记录 Prompt-only 的能力上限，Jev 继续实验状态，不伪造 winner。

**Step 5: 证据交付**

记录运行命令、固定 seed、样本规模和结论；原始 .outputs 不提交。

---

## P2-T4 迭代 Prompt 优化并重新验证关键边界

**Files:**
- Modify: python_backend/shared/companion_prompt_profiles.py
- Modify: python_backend/tests/test_companion_prompt_benchmark.py
- Evidence only: python_backend/.outputs/（不入 Git）

**Step 1: 从失败边界反推 Prompt 缺陷**

以现有 Stage A/B 的 active_dense、settled_end、sustain_pause、takeover_overlay 结果为基线，优先修复 continuing/finished 无法拉开的问题；不改模型、corpus、sample 生成和 semantic-v1 action mapping。

**Step 2: 小样本迭代**

新增少量真正不同的候选 Prompt，优先把正反证据写进 Noul true/false criteria，并显式锚定可观测时间/踏板/held-note 边界。使用固定开发 seed 与同一 case IDs 反复筛选；每轮根据失败边界收敛候选，不堆叠同义 profile。

**Step 3: 固定 Stage A 复验**

仅将开发样本上明显改善且无 collapse 的候选放回固定 seed=20260920、120-case Stage A。必须同时检查 settled_end vs active_dense、takeover vs active_dense、sustain_pause 和跨来源方向。

**Step 4: 决策**

若候选通过修正后的 Stage A，再进入固定 600-case Stage B；否则保留 Prompt-only 不足结论。不得为进入 P3 强选候选。

**Step 5: 原子提交与证据**

提交最终保留的 Prompt/schema 与最小回归测试；中间失败实验只保留 gitignored evidence。

---

## P2-T5 消除二元 Choice 标签顺序偏置并验证产品候选

**Files:**
- Modify: python_backend/shared/jev_protocol.py
- Modify: python_backend/jev_server/jev_server/server.py
- Modify: python_backend/jev_server/tests/test_jev_server.py
- Modify: python_backend/shared/companion_prompt_profiles.py
- Modify: python_backend/tests/test_companion_prompt_benchmark.py
- Evidence only: python_backend/.outputs/（不入 Git）

**Step 1: 固定根因**

用同一问题/criteria 仅改变正类落在 A 或 B 的位置，确认 Qwen3.5-0.8B zero-token Choice 存在明显 candidate-label prior；不得把该偏置误归因于 Prompt 文案。

**Step 2: 通用顺序不变评分**

仅对二元 Choice 在 Jev runtime 内同时编译原顺序与反转顺序，将同一语义选项的 logits 对齐后平均再 softmax。实现必须保持领域无关，不改变 Noul、HTTP 协议、模型或 semantic-v1 action mapping。

**Step 3: 回归与延迟边界**

增加候选顺序偏置回归；Python Jev tests、Prompt benchmark tests 与 py_compile 全部通过。真实 Stage A 必须使用固定 seed=20260920 / 同一 120 case。若完整四问题消偏使延迟超过当前 Swift 1s request timeout，则继续收敛 semantic schema，优先合并重复的 continuing/finished，而不是提高 timeout 掩盖问题。

**Step 4: 固定 Stage B**

只有 Stage A 无自动停止项、无跨来源方向冲突且延迟满足实时边界的候选，才能进入同 seed / corpus / case IDs 的固定 600-case Stage B。

**Step 5: 决策**

若关键边界在 Stage B 稳定通过，记录为 P3 唯一实验真源；否则继续保持 Jev 实验状态，不强选候选。

---

## P2-T6 评估 CLM System One 替代路径

**Scope:** 仅做隔离实验，不修改 HappyPianist 产品代码；验证 Contrastive-LM/CLM 是否比当前 Jev/Qwen zero-token 路线更适合实时 companion decision。

**Step 1: Zero-shot 对照**

使用官方 CLM-v0.1-8B projection head 与原始 Qwen3-8B BF16 last-token embedding 做真实 smoke；另用 Qwen3-8B bnb-4bit 验证 8GB RTX 4060 可运行性。直接比较 typed semantic 问题与 state->action ranking，观察候选措辞稳定性和延迟。

**Step 2: 轻量 head finetune 可学习性 probe**

固定 companion corpus，按 source+MIDI file 分组切 train/val/test，避免同一文件泄漏。仅微调 CLM projection head，encoder 冻结。标签来自显式 synthetic boundary bootstrap，只能用于验证边界是否可学习，不得表述为人类 turn-taking accuracy。

**Step 3: 部署路径 replay**

用保存的 head 重新走 Engine.answer() + 4-bit encoder，对完全 held-out MIDI files 重放，核对训练评测与真实推理路径一致，并记录热态 latency。

**Step 4: 决策**

若 zero-shot 对 wording 敏感或 collapse，则淘汰 zero-shot 产品接入；若 finetune 只在 synthetic labels 上有效，则记录为候选研究路线，但在取得真实 turn-taking 标签之前不得进入 P3 产品真源。

**Evidence:**
- 官方 CLM head SHA256=b2b4a8c9c2d39263eff78a351eb909a342ce9b3bf21a3f07c1d1bf15f1c4eda5。
- 原始 Qwen3-8B 五个 BF16 shards 均按仓库 X-Linked-Etag SHA256 校验通过；bnb-4bit 主权重 SHA256=2d7930212c1a43efade360fa2d66cc0188ebda793b08fb4f8ec1143299147381。
- Zero-shot BF16/direct-action 对候选 wording 极不稳定：一组描述几乎全 listen，加入边界条件后又几乎全 respond，因此不可作为产品候选。
- 4-bit encoder + 官方 head 在 synthetic held-out test 上仅 16.7%，几乎全 respond。
- 仅微调 head：960 case（80/source/state），按 MIDI file 分组为 train=673 / val=143 / test=144；部署路径 replay test=84.7%。per-state: active_dense=100%、active_sparse=25%、natural_silence=95.5%、settled_end=83.3%、sustain_pause=92.6%、takeover_overlay=100%。热态 median=407.6ms，p95≈410.0ms，模型加载约 6.6s，显存约 5.66GB。
- focused active_sparse 再训练虽把局部 validation 拉高，但同一 held-out replay 总体跌到 42.4%，已淘汰。

**Conclusion:** CLM zero-shot 不足；task-specific head finetune 显示出明显可学习性和可接受热态延迟，但当前证据仍是 synthetic boundary reproduction，且 active_sparse 边界不足。没有真实 turn-taking 标签前，不把 CLM 作为 P3 产品真源。

---

## Phase Audit

- Audit file: audit-p2.md
- Rule: 完成本 phase 全部 tasks 后，executing-plans 必须自动进入该文件的审计闭环
