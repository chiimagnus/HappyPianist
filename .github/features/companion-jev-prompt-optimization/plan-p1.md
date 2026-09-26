# Plan P1 - 通用 Jev-like Runtime 与协议收敛

**Goal:** 用领域无关、0-output-token 的 typed classifier runtime 完全替代钢琴专用 Qwen scorer，并让 Swift 网络层只承担通用协议传输。

**Non-goals:** 本阶段不判断哪个钢琴 Prompt 最好，不调整 Aria 生成策略，不做模型微调。

**Approach:** 以当前未提交的 python_backend/jev_server/ 和 JevClassifierClient.swift 草稿为起点，先稳定 prompt compilation / logits scoring / typed response 的职责边界，再删除旧 /decision 双轨。钢琴动作语义只保留在 companion adapter，不进入 runtime。真实 Qwen smoke 用非音乐问题证明 runtime 不是“换名字的钢琴 scorer”。

**Acceptance:**
- POST /v1/classifier 支持 choice 与 noul，真实 Qwen 请求报告 output_tokens=0。
- runtime 可处理非钢琴问题；schema/model/runtime 错误显式失败。
- Swift generic client 不认识 CompanionAction。
- 旧专用服务、协议和 client 被删除，无兼容 fallback。

**Rules:**
- 不自动回退到规则后端。
- 不为未使用的 Jev 能力引入额外框架。
- candidate 必须在最终 answer boundary 验证为稳定单 token；不能退化为文本生成解析。

---

## P1-T1 完成通用 Jev typed runtime 与 logits scoring

**Files:**
- Modify: python_backend/shared/jev_protocol.py
- Modify: python_backend/jev_server/jev_server/server.py
- Modify: python_backend/jev_server/tests/test_jev_server.py
- Modify: python_backend/jev_server/pyproject.toml
- Modify: python_backend/jev_server/uv.lock
- Modify: python_backend/scripts/jev_server.py
- Modify: python_backend/scripts/jev_server_smoketest.py

**Current evidence / root issue:**
- 当前 draft 已支持 choice/Noul、shared-prefix/KV cache 尝试和 /v1/classifier，但仍处于 Prompt contract 校准阶段。
- 旧五选一 scorer 曾出现候选顺序/token prior 明显影响结果；runtime 必须把 answer-boundary prompt、候选 token 校验和 Noul 评分固定成通用不变量，不能靠业务 Prompt 打补丁。

**Step 1: 收敛 typed schema 与 prompt compilation**

保留最小通用 schema：model、state、questions、choice/noul、typed answers、usage、latency。完成统一 system/context/selected-question/answer-prefix 编译；Jev runtime 内禁止钢琴领域词汇。

**Step 2: 收敛 logits 计算**

choice 只比较稳定 candidate label token；Noul 只比较约定的有序单 token score。所有候选必须在最终 answer boundary 重新验证 single-token 稳定性。shared-prefix 优化只有在与 full forward 行为等价时保留，否则删除优化。

**Step 3: 回归验证**

Run:
- python -m pytest python_backend/jev_server/tests -q
- python -m py_compile python_backend/shared/jev_protocol.py python_backend/jev_server/jev_server/server.py python_backend/scripts/jev_server.py python_backend/scripts/jev_server_smoketest.py

Expected: choice/Noul 正常；invalid request/model mismatch/runtime failure 不伪造 answer；output_tokens=0。

**Step 4: 真实 Qwen smoke**

启动 Qwen3.5-0.8B Jev server，用非钢琴问题调用 /v1/classifier。

Expected: typed answer 合理、output_tokens=0、无 completion 文本解析。

**Step 5: 原子提交**

只提交 Python 通用 Jev runtime 与测试。

---

## P1-T2 完成 Swift 通用 Jev transport 并删除旧专用路径

**Files:**
- Replace: HappyPianistAVP/Services/Practice/AI/Networking/CompanionDecisionClient.swift -> JevClassifierClient.swift
- Replace: HappyPianistAVPTests/Networking/CompanionDecisionClientTests.swift -> JevClassifierClientTests.swift
- Modify: HappyPianistAVP/ViewModels/Practice/AI/ARGuideAIPerformanceViewModel.swift
- Delete: python_backend/companion_decision_server/
- Delete: python_backend/scripts/companion_decision_server.py
- Delete: python_backend/scripts/companion_decision_smoketest.py
- Delete: python_backend/shared/decision_protocol.py

**Current evidence / root issue:**
- CodeGraph 显示 JevClassifierClient 只应由 companion adapter 使用；当前 discovery 已转向 path=/v1/classifier、engine=jev-classifier。
- 旧文件当前已处于删除/替换状态，但尚未完成统一验证。

**Step 1: 固定 Swift generic request/response**

Swift client 只建模 model/state/questions/answers/usage/latency，不引用 CompanionAction。choice 与 noul 均能解码。

**Step 2: 固定 Bonjour contract**

Jev discovery 只匹配新的 classifier TXT record；旧 /decision、旧 protocol version、旧 engine 名全部删除。

**Step 3: 清理双轨**

全仓检查旧 server/client/protocol 生产引用，删除所有被 Jev path 取代的兼容代码与测试。

**Step 4: 验证**

Run Swift 网络 client tests（macOS/Xcode 可用时）、旧符号搜索、git diff --check。

Expected: Swift transport 通用；旧 scorer 无生产引用。

**Step 5: 原子提交**

只提交 Swift transport/discovery 与旧路径清理。

---

## P1-T3 建立 runtime 等价性与失败边界回归

**Files:**
- Modify: python_backend/jev_server/tests/test_jev_server.py
- Modify: HappyPianistAVPTests/Networking/JevClassifierClientTests.swift

**Step 1: 增加关键边界测试**

覆盖 Noul score 范围与完整 distribution、candidate boundary 稳定性、shared-prefix/full-forward 等价性（若保留 shared-prefix）、server failure 不生成默认 answer、Swift 错误 HTTP/缺字段显式失败。

**Step 2: 验证**

运行 Python tests；macOS/Xcode 可用时运行 Swift tests。

Expected: runtime 正确性不依赖钢琴 Prompt。

**Step 3: 原子提交**

只提交边界回归。

---

## Phase Audit

- Audit file: audit-p1.md
- Rule: 完成本 phase 全部 tasks 后，executing-plans 必须自动进入该文件的审计闭环
