# Audit P2 - companion-jev-prompt-optimization

- 审计方式：plan-task-auditor
- 审计范围：plan-p2.md
- feature 目录：.github/features/companion-jev-prompt-optimization/
- 粒度：phase

## 任务看板

- [x] P2-T1 固定大规模 MIDI 状态语料与抽样不变量
- [x] P2-T2 建立两阶段 Prompt benchmark
- [x] P2-T3 对 Stage A 候选运行固定 600-case 并形成结论

## 任务到文件的映射

- P2-T1
  - python_backend/scripts/companion_acceptance_corpus.py
  - python_backend/tests/test_companion_acceptance_corpus.py
  - python_backend/.outputs/companion-corpus/index.json（实验产物，不入 Git）
- P2-T2
  - python_backend/shared/companion_prompt_profiles.py
  - python_backend/scripts/companion_prompt_benchmark.py
  - python_backend/scripts/companion_e2e_acceptance.py
  - python_backend/tests/test_companion_prompt_benchmark.py
  - python_backend/.outputs/p2-stage-a/（实验产物，不入 Git）
- P2-T3
  - python_backend/scripts/companion_prompt_benchmark.py（复用 T2 已参数化 runner，无额外 task commit）
  - python_backend/.outputs/p2-stage-b/（历史 600-case/profile 证据，不入 Git）

## 发现项

## 发现 F-04

- 任务：`P2-T4`
- 严重级别：`Medium`
- 状态：`Open`
- 位置：`python_backend/scripts/companion_prompt_benchmark.py:98-202`
- 摘要：`Stage A 未校验 space 与 inactive reasserted 的语义契约`
- 风险：`choice_strict 可在 active_dense 的 space≈0.818、AI 未激活的 active_dense reasserted≈0.593 时仍通过门禁；这些分数违反 Prompt 自身定义，只是被 action mapping 的优先级部分掩盖，进入 P3 后可能产生错误陪奏或不稳定让位行为。`
- 预期修复：`把 active_dense space、AI 未激活状态 reasserted 纳入 Stage A 诊断，并迭代二元 Prompt 使关键语义边界通过；若无法通过则不选产品候选。`
- 验证：`unittest 覆盖新停止条件；固定 120-case Stage A；通过后固定 600-case Stage B。`
- 解决证据：`<commit diff note or test/build output>`


## 发现 F-03

- 任务：`P2-T4`
- 严重级别：`Medium`
- 状态：`Open`
- 位置：`python_backend/jev_server/jev_server/server.py:246-281`
- 摘要：`二元 choice 语义分数受 A/B 候选位置偏置污染`
- 风险：`choice_strict 固定 false=A、true=B；实测同一明确 false 状态仅交换语义与 A/B 绑定，true 概率从约 0.651 变为约 0.423。Stage B 的 true 分数与 0.55 动作阈值因此不可直接解释，当前产品候选结论不可信。`
- 预期修复：`仅对二元 choice 同时按正序与反序编译，按语义选项聚合 logits 后再 softmax；多选 choice 与 Noul 保持原行为。`
- 验证：`增加候选顺序偏置回归；纯 false 探针验证顺序不再改变语义概率；重新运行固定 Stage A，若通过再重跑 600-case Stage B。`
- 解决证据：`<commit diff note or test/build output>`


## 发现 F-01

- 任务：P2-T1
- 严重级别：Medium
- 状态：Resolved
- 位置：python_backend/scripts/companion_acceptance_corpus.py:542-548
- 摘要：语料索引存在文件级错误时仍以退出码 0 结束
- 风险：未来自动化只检查进程退出码时会把不完整 corpus 当成成功产物，破坏固定 2185 文件与 0 error 的验收不变量。
- 预期修复：保留 errors 到 index 供诊断，但 main 在 errors 非空时返回非零；增加回归测试覆盖成功与错误退出语义。
- 验证：unittest + 全量 2185 corpus 运行确认 errors=0 且 exit=0
- 解决证据：commit dee30e2；unittest 成功/错误退出语义均通过；全量 1276 MAESTRO + 909 POP909=2185 文件 errors=0，输出 SHA256=6D544631C7A005A5AC059A0D3E1939E417F89EA82F6762A59E7F831A8BB24C52。

## 发现 F-02

- 任务：P2-T2
- 严重级别：Medium
- 状态：Resolved
- 位置：python_backend/scripts/companion_prompt_benchmark.py:98-169
- 摘要：Stage A 诊断没有检查 settled_end 结束边界
- 风险：Prompt 即使完全无法识别明确结束，也能通过 Stage A 并进入昂贵的 600-case；本轮两个候选正是因此直到 Stage B 才暴露 0 respond。
- 预期修复：把 settled_end finished/respond 与 active_dense 对照纳入 key boundaries 和停止条件，保留无人工标签前提下的行为边界判断。
- 验证：unittest 覆盖 broken settled_end 被淘汰，并用本轮 Stage A 结果重算 observable/thresholds 的停止原因
- 解决证据：commit b92644b；8/8 P2 unittest 通过；旧 Stage A 结果重算后 observable 与 observable_thresholds 均命中 settled_end_not_separated_from_active_dense，二者应在 Stage A 淘汰。

## 修复日志

- dee30e2：corpus 存在文件级错误时保留 errors 证据并返回非零；增加成功/失败退出语义回归。
- b92644b：Stage A 把 settled_end 与 active_dense 的 continuing / finished / respond 边界纳入停止条件；增加回归。

## 验证日志

- py_compile（P2 corpus / benchmark / e2e / prompt profiles / 两个测试文件） -> PASS
- python -m unittest python_backend.tests.test_companion_acceptance_corpus python_backend.tests.test_companion_prompt_benchmark -v -> PASS，8/8
- 全量 corpus：1276 MAESTRO + 909 POP909 = 2185，errors=0，SHA256=6D544631C7A005A5AC059A0D3E1939E417F89EA82F6762A59E7F831A8BB24C52 -> PASS
- 旧 Stage A 结果按修复后诊断重算：5/5 profiles 均有停止原因；observable 与 observable_thresholds 均命中 settled_end_not_separated_from_active_dense -> PASS
- Stage B 固定性核对：两个历史候选各 600 case，case IDs / corpus SHA / seed=20260920 / semantic-v1 mapping 全部一致 -> PASS
- Stage B 行为佐证：observable settled_end=99 listen + 1 support；observable_thresholds settled_end=100 listen，均 0 respond -> PASS（支持 Prompt-only 不足结论，不作为准确率声明）
- git grep 扫描 piece_end / 旧 baseline prompt profile -> 0 match
- git diff --check 95eef0d..HEAD -> PASS
- .outputs / .datasets ignore 检查 -> PASS
- 工作区 -> clean

## Gate（是否允许进入下一阶段）

- 结论：Go
- 理由：P2 的可复现评估目标已完成，两项审计缺陷均已根因修复；实验结论是 Prompt-only 暂不足，而不是选出产品候选。

## 最终状态与剩余风险

- 当前状态：Resolved
- 剩余风险：语料没有人工 turn-taking 标签，因此只能报告行为边界而不能宣称准确率；修复后的 Stage A 没有合格 profile，P3 不应把现有 Jev Prompt 接成产品决策真源，需先重新定义后续实验方向。历史 Stage B 1200 次分类仅作为负面结论佐证。

## 审计约束

- 本文件对应一个 phase，不对应单个 task
- 如果由 executing-plans 自动进入审计，也沿用同一模板
