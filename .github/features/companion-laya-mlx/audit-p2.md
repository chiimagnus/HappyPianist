# Audit P2 - companion-laya-mlx

- 审计范围：`plan-p2.md`
- feature 目录：`.github/features/companion-laya-mlx/`
- 粒度：`phase`
- 结论：`No-Go`

## 任务看板

- [x] P2-T1 将 Swift Jev 接入整体替换为 Laya
- [!] P2-T2 建立固定 Laya companion 行为 benchmark（Blocked）

## 已完成证据

### P2-T1

- Swift 产品调用链已切换为 `LayaClassifierClient` + `LayaNetworkCompanionDecisionBackend`。
- 产品与测试旧 `Jev` companion 符号扫描为 0。
- `make build:simulator` -> PASS。
- Laya/companion 定向测试 -> 8/8 PASS。
- compact-state 后核心 Laya 定向测试 -> 4/4 PASS。
- 提交：`29848940`、`19c46b78`。

### P2-T2

- 新增固定 Stage A runner：`python_backend/scripts/companion_laya_benchmark.py`。
- 固定 `seed=20260920`、6 states、MAESTRO + POP909、每 state/source 10 cases，共 120 cases。
- corpus：1276 MAESTRO + 909 POP909 = 2185 MIDI，解析 errors=0。
- corpus raw LF SHA256：`b1ea445712d563d8ef8facc3cf9c66c272f261382666b0f5bddf17e7b818971d`。
- corpus canonical JSON SHA256：`40645ac15205f8d3a85067daf4ddb9adb062ff53eddb8ed39c3d35d1b87d6569`。
- 历史 Windows `6D544631...` 与当前内容差异仅为 CRLF/LF；把当前 LF JSON 转成 CRLF 后 SHA256 精确恢复 `6d544631c7a005a5ac059a0d3e1939e417f89ea82f6762a59e7f831a8bb24c52`。
- benchmark/test 提交：`c6c7a60e`。

## 发现项

### F-01 - recent notes 使 Laya state 超出合理上下文预算

- 严重级别：`Medium`
- 状态：`Resolved`
- 发现：固定 120 cases 中，76 个包含 16 条 `recent_notes` 的 raw state 超过 1000 tokens；典型 dense/takeover 为约 1250-1287 tokens。
- 对照：删除逐音符明细后 state 约 170-200 tokens。
- 结果：逐音符明细没有改善 action collapse；删除后热态延迟显著下降。
- 修复：从 `AIPerformanceService -> CompanionDecisionInput -> Laya state` 整条链删除 `recent_notes`，Python payload 同步只发送汇总 state。
- 验证：Python 11/11 PASS；`make build:simulator` PASS；Swift Laya 定向测试 4/4 PASS。
- 解决证据：`19c46b78`。

### F-02 - Laya 直接五分类 action choice 稳定单类 collapse

- 严重级别：`Blocker`
- 状态：`Unresolved`
- 正式 Stage A：120/120 选择 `listen`。
- action 分布：`listen=100%`，其余四类均 `0%`。
- compact-state 热态延迟：server median `40 ms`、p95 `53 ms`、max `60 ms`；round-trip median `46.8 ms`、p95 `61.3 ms`、max `95.8 ms`。
- Gate failures：全局单类 collapse；`takeover_overlay` 未与 `active_dense` 在 yield 上分离；`settled_end respond=0%`；`active_sparse` 单类 collapse。
- 可重复性：第二次完整 Stage A 的 case IDs、canonical corpus SHA、120 个 choice 与 Gate failures 均完全一致；benchmark 按失败契约退出 code 2。
- Plan 允许范围内的最小 question 迭代已执行：仅修改同一个 `action` choice 的 instructions/criteria，不新增 profile、不改样本。某些 wording 可让 `takeover_overlay` 较多转为 `yield`，但 `settled_end/respond` 与 `support` 概率长期维持极低，无法同时满足固定边界。
- 结论：当前 Laya 直接五分类 action 方案不能进入 P3。

## 验证日志

- `PYTHONPATH=. ... pytest test_companion_laya.py test_companion_laya_benchmark.py test_companion_acceptance_corpus.py -q` -> PASS `11/11`。
- `make build:simulator` -> PASS。
- compact-state Swift 定向测试 -> PASS `4/4`。
- 固定 120-case Stage A x2 -> deterministic No-Go。
- `rtk git diff --check` -> PASS。

## Gate（是否允许进入下一阶段）

- 结论：`No-Go`
- P3-T1/P3-T2/P3-T3 保持 `pending`，不得在失效的 companion decision 上继续做 E2E 或宣称产品验收通过。

## 剩余决策

当前 blocker 不是实时性能，而是 Laya 对这个五动作直接 choice 的决策质量。下一步需要新方案/新 phase；不能通过继续堆同类 Prompt wording 伪造通过。
