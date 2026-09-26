# Plan P4 - 全面验证、文档与旧实现清理

**Goal:** 以仓库级回归、平台 build/test、文档和旧引用审计完成 feature 收口，确保只留下一个 Jev runtime 和一套 companion 决策真源。

**Non-goals:** 不在收尾阶段新增 Prompt、模型或数据集；新的研究方向只记录后续项。

**Approach:** 先做 Python/协议/真实服务回归，再在 macOS/Xcode 可用时执行项目标准 build/test；随后更新架构与 AI companion 文档，最后清理旧符号、重复协议、无用 fallback 和死代码。验证失败必须回到对应 phase 根因修复。

**Acceptance:**
- Python tests、真实 Jev smoke、Prompt benchmark 证据和 E2E 可复现。
- macOS/Xcode 可用时项目标准 Swift build/test 通过；不可用时明确留下未验证项。
- 文档只描述当前实现与实测结果，不把旧 6-MIDI/30-case 当当前结论。
- 全仓不存在旧 /decision 双轨、旧 Qwen 专用 scorer 或多余兼容代码。

**Rules:**
- Feature Plan 默认本地，不提交 Git，除非用户另行明确要求。
- 不把 CodeGraph sync / git diff --check / Python tests 冒充 Xcode build/test。
- 不为了通过验收改变 benchmark 样本或选择性删除失败 case。

---

## P4-T1 执行 Python、协议与真实服务回归

**Files:**
- Verify all changed Python runtime, prompt, corpus and E2E files

**Step 1: Python tests**

运行 Jev server、Aria server 和 shared 相关测试。

**Step 2: 静态与锁文件**

Run py_compile、uv lock --check、git diff --check、CodeGraph sync。

**Step 3: 真实服务 smoke**

启动 Qwen Jev server，运行非钢琴 classifier smoke 和 companion-specific sample；确认 output_tokens=0。

**Step 4: 复核实验**

确认最终 Prompt benchmark summary 和 E2E summary 可由文档命令复现。

---

## P4-T2 执行 Swift build/test 与 App 级可达性验证

**Files:**
- Verify all Swift files changed by this feature

**Step 1: 项目标准检查**

macOS/Xcode 可用时运行 make doctor、make destinations、make build:simulator、make test:simulator。

**Step 2: App 级链路**

至少证明 Jev discovery -> generic client -> companion adapter -> AIPerformanceService 可达；条件允许时用 simulator/device MIDI 注入验证一次完整决策。

**Step 3: 环境阻塞处理**

若 macOS MCP/Xcode 不可用，记录具体缺口，不创建假测试，不用 Windows 结果替代。

---

## P4-T3 更新文档并删除所有过时实现/结论

**Files:**
- Modify: docs/architecture.md
- Modify: docs/ai-companion-requirements.md
- Modify: python_backend/README.md
- Delete/clean stale legacy scorer references

**Step 1: 文档事实对齐**

说明通用 Jev-like runtime、choice/Noul 0-output-token、companion semantic adapter、Prompt benchmark 方法与结果、大规模 MIDI 语料边界、E2E/延迟结果和剩余限制。

**Step 2: 删除过时结论**

旧 5 手工场景、6-MIDI/30-case 等只能作为历史背景时明确标为已作废，不得继续成为当前验收依据。

**Step 3: 全仓清理**

检查旧命名、旧 /decision、兼容分支、重复 prompt/action mapping、未使用文件和多余 fallback；能删则删。

**Step 4: 最终验证与原子提交**

重新执行受影响测试和 diff check，再提交文档/清理变更。

---

## Phase Audit

- Audit file: audit-p4.md
- Rule: 完成本 phase 全部 tasks 后，executing-plans 必须自动进入该文件的审计闭环
