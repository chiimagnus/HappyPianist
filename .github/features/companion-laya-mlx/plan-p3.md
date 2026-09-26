# Plan P3 - 真实链路、平台验证与收尾

**Goal:** 证明 Mac Laya 服务到 visionOS companion control loop 的真实链路可用，并把当前 PR 收敛为只含 Laya 的实现。

**Non-goals:** 不在收尾阶段新增模型、Prompt 架构或训练任务。

**Approach:** 先跑真实服务/E2E，再跑项目标准 Xcode build/test；最后更新长期文档并扫描旧实现。任何验证失败都回到拥有该不变量的 task 根因修复，不加 fallback。

**Acceptance:**
- Mac 本机 Laya smoke 与 companion-specific request 真实通过。
- Laya discovery/client/backend/AIPerformanceService 调用链有运行证据。
- `make build:simulator`、`make test:simulator` 通过。
- 最终工作树和长期文档无 Qwen/CLM/Jev companion 决策残留。

**Rules:**
- 不把 unit test、CodeGraph 或 build 当成真实服务 smoke。
- 不为了通过验收提高 timeout 掩盖性能问题。
- 不保留旧实现 compatibility/fallback。

---

## P3-T1 运行 Laya -> companion -> Aria/MIDI 真实链路

**Files:**
- Modify as required: `python_backend/scripts/companion_e2e_acceptance.py`
- Inspect/Modify as required: `HappyPianistAVP/Services/Practice/AI/AIPerformanceService.swift`
- Inspect: `HappyPianistAVP/Services/Practice/AI/TurnTaking/DuetPhrasePolicy.swift`

**Step 1: Mac 服务**

启动 Laya server，验证 localhost HTTP 和 Bonjour 广播；用 companion 实际 state/action question 做真实请求。

**Step 2: 控制环**

从 `AIPerformanceService.requestCompanionDecision` 追到 Laya backend，确认失败时停止该次决策、不回退规则；新用户输入仍可取消过时生成/播放窗口。

**Step 3: E2E**

条件允许时运行固定 Laya -> Aria -> MIDI 样本，记录分类延迟、生成延迟、NoteEvent 合法性和失败分类。Aria 环境缺失时只把 Aria 部分标为明确环境阻塞，不影响已证明的 Laya 决策链。

**Step 4: 原子提交**

只提交真实链路所需的必要修正；若无需改代码，在 todo note 记录证据，不制造空提交。

---

## P3-T2 执行完整 Swift/Python 回归

**Files:**
- Verify all changed source/test files

**Step 1: Python**

运行 `laya_server` tests、corpus/benchmark tests、`py_compile`、lock check 和 `git diff --check`。

**Step 2: Apple 平台**

运行 `make doctor`、`make destinations`、`make build:simulator`、`make test:simulator`。不得以 build-for-testing 代替 test。

**Step 3: 原子提交**

验证本身不制造提交；发现缺陷则回到对应 task 根因修复后重新跑。

---

## P3-T3 更新长期文档并清除旧实现

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/ai-companion-requirements.md`
- Modify: `python_backend/README.md`
- Modify/Delete stale Qwen/Jev/CLM references in current product/runtime files

**Step 1: 文档事实对齐**

只描述当前 Laya-MLX 架构、322M 默认 checkpoint、Mac 本地运行方式、typed-decision 边界、benchmark 结果与剩余限制。

**Step 2: 全仓清理**

扫描当前工作树中的 Qwen、CLM、Jev companion decision runtime、旧 `/decision`、旧 Prompt profiles、兼容分支和未使用文件；当前功能不再需要的全部删除。

**Step 3: 最终 diff 审核与原子提交**

确认 PR 相对 `origin/main` 的最终 diff 只表达 Laya pivot，运行受影响验证后提交文档/清理变更。

---

## Phase Audit

- Audit file: `audit-p3.md`
- Rule: 完成本 phase 全部 tasks 后，`executing-plans` 必须自动进入该文件的审计闭环
