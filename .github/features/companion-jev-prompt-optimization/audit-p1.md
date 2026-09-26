# Audit P1 - companion-jev-prompt-optimization

- 审计方式：`plan-task-auditor`
- 审计范围：`plan-p1.md`
- feature 目录：`.github/features/companion-jev-prompt-optimization/`
- 粒度：`phase`

## 任务看板

- [x] P1-T1 完成通用 Jev typed runtime 与 logits scoring
- [x] P1-T2 完成 Swift 通用 Jev transport 并删除旧专用路径
- [x] P1-T3 建立 runtime 等价性与失败边界回归

## 任务到文件的映射

- P1-T1
  - `python_backend/shared/jev_protocol.py`
  - `python_backend/jev_server/jev_server/server.py`
  - `python_backend/jev_server/tests/test_jev_server.py`
  - `python_backend/jev_server/pyproject.toml`
  - `python_backend/jev_server/uv.lock`
  - `python_backend/scripts/jev_server.py`
  - `python_backend/scripts/jev_server_smoketest.py`
- P1-T2
  - `HappyPianistAVP/Services/Practice/AI/Networking/JevClassifierClient.swift`
  - `HappyPianistAVP/Services/Practice/AI/TurnTaking/JevNetworkCompanionDecisionBackend.swift`
  - `HappyPianistAVP/ViewModels/Practice/AI/ARGuideAIPerformanceViewModel.swift`
  - `HappyPianistAVPTests/Networking/JevClassifierClientTests.swift`
  - `python_backend/README.md`
  - 已删除旧 `CompanionDecisionClient`、`QwenNetworkCompanionDecisionBackend`、`companion_decision_server`、`decision_protocol.py` 与旧 smoke 入口
- P1-T3
  - `python_backend/jev_server/tests/test_jev_server.py`
  - `HappyPianistAVPTests/Networking/JevClassifierClientTests.swift`

## 发现项

## 发现 F-03

- 任务：`P1-T1`
- 严重级别：`Medium`
- 状态：`Resolved`
- 位置：`python_backend/jev_server/jev_server/server.py:_forward_with_shared_prefix`
- 摘要：`shared-prefix KV-cache 优化增加模型特定缓存语义风险且不是 runtime 正确性所需`
- 风险：`不同模型/cache 实现可能与 full forward 行为漂移；同时重复维护两条 logits 路径，违背 P1 只在行为等价时保留该优化的约束。`
- 预期修复：`删除 shared-prefix/KV-cache 快路径，所有 question 统一走单次 batched full forward。`
- 验证：`python -m pytest python_backend/jev_server/tests -q`
- 解决证据：`commit 71d38b8；删除 196 行 shared-prefix/cache 路径与专属测试；当前 Jev Python 10/10 passed。`

## 发现 F-02

- 任务：`P1-T2`
- 严重级别：`Medium`
- 状态：`Resolved`
- 位置：`python_backend/README.md:1-77`
- 摘要：`Python backend README 仍宣传已删除的 companion_decision_server 与 /decision`
- 风险：`开发者按文档会进入不存在目录并启动不存在入口，且把旧专用 Qwen 协议误认为当前正式协议。`
- 预期修复：`把实时陪伴决策文档切换为通用 jev_server、/v1/classifier 与对应 smoke 命令，删除旧 scorer 叙述。`
- 验证：`git grep old symbols + Jev Python tests + py_compile`
- 解决证据：`commit 95eef0d；Jev Python 10/10 passed；py_compile PASS；旧 /decision、companion_decision_server、旧 Swift client/backend 生产引用扫描为 0。`

## 发现 F-01

- 任务：`P1-T1`
- 严重级别：`Medium`
- 状态：`Resolved`
- 位置：`python_backend/shared/jev_protocol.py:_shared_system`
- 摘要：`多 question Prompt 仍依赖 JSON object 到达顺序`
- 风险：`Swift Dictionary/JSON object 没有顺序契约；同一 questions 映射可能生成不同 shared-system 顺序，导致 logits 漂移并破坏通用 runtime 的确定性。`
- 预期修复：`按 question id 排序 shared-system instructions，并同步固定 classify 编译顺序；增加反序输入回归。`
- 验证：`python -m pytest python_backend/jev_server/tests -q && python -m py_compile python_backend/shared/jev_protocol.py python_backend/jev_server/jev_server/server.py`
- 解决证据：`commit 2db9f58；Python 回归与 py_compile、diff-check PASS。`

## 修复日志

- F-01：`2db9f58` 固定 shared-system 与 compile 的 question 顺序，消除 JSON/Swift Dictionary 顺序导致的 Prompt 漂移。
- F-03：`71d38b8` 删除 shared-prefix/KV-cache 双轨，所有 question 统一走单次 batched full forward。
- F-02：`95eef0d` 把 Python backend README 完整切换到 Jev `/v1/classifier`，移除已删除服务与旧 `/decision` 用法。

## 验证日志

- `PYTHONPATH=python_backend;python_backend/jev_server python -m pytest python_backend/jev_server/tests -q` -> PASS，10/10。
- `python -m py_compile python_backend/shared/jev_protocol.py python_backend/jev_server/jev_server/server.py python_backend/scripts/jev_server.py python_backend/scripts/jev_server_smoketest.py` -> PASS。
- `git diff --check de737e3..HEAD` -> PASS。
- 旧 `CompanionDecisionClient` / `QwenNetworkCompanionDecisionBackend` / `companion_decision_server` / `decision_protocol` / `/decision` 生产引用扫描 -> 0。
- CodeGraph：`JevClassifierClient` 不引用 `CompanionAction`；Bonjour 仅匹配 `/v1/classifier + protocol_version=1 + engine=jev-classifier`；`AIPerformanceService` 对所选决策后端失败显式停止当前 tick，不回退规则后端。
- Swift generic client 回归源码覆盖 bad HTTP、choice 缺字段、`output_tokens != 0` 显式失败；Windows 环境没有 Xcode，因此没有把未运行的 Apple test 冒充为通过。
- 本机 `python_backend/.outputs/prompt-full/observable/results.json` 已于 2026-09-23 通过 `/v1/classifier` 完成 600 个真实 MIDI case；runtime 响应 schema 将 `output_tokens` 固定为 `Literal[0]`，smoke 脚本显式断言为 0。本轮 8767 未运行且 Qwen 权重缓存已不存在，因此未重复下载约 1.7 GB 权重做重复 smoke。
- `todo validate` -> `todo.toml OK`；`phase-complete --phase p1` -> `PHASE COMPLETE`。
- `uv lock --check` 未执行：Windows PATH 中没有 `uv`；P1 plan 的必需验证命令不包含该项。

## Gate（是否允许进入下一阶段）

- 结论：`Go`
- 理由：P1 的 runtime、generic Swift transport、旧路径删除与失败边界均已满足；3 条审计 finding 全部 Resolved，P1 机械门禁与要求的 Python 验证通过。

## 最终状态与剩余风险

- 当前状态：`Resolved`
- 剩余风险：当前 Windows checkout 无法运行 Xcode/visionOS 测试；真实 Qwen 新接口已有当日 600-case 本地运行证据，但本轮未因权重缓存已不存在而再次启动模型。该两项不阻塞 P1，Apple build/test 的完整门禁仍归 P4。

## 审计约束

- 本文件对应一个 phase，不对应单个 task
- 如果由 `executing-plans` 自动进入审计，也沿用同一模板
