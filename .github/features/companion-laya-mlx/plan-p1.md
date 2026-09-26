# Plan P1 - Mac Laya-MLX Runtime

**Goal:** 用 Mac 原生 Laya-MLX 完全替换当前 PR 的 Qwen/Jev Python 决策 runtime，并证明真实 typed decision 可运行。

**Non-goals:** 本阶段不改 Swift 产品命名，不调整 Aria，不做 companion 行为 benchmark。

**Approach:** 保留 `/v1/classifier` 这一条简单 HTTP 边界，服务内部直接调用 `laya_mlx.Agent.predict`。协议只做 JSON 校验和错误映射，不重新实现 Laya 的 scoring/calibration。默认加载 322M multilingual MLX checkpoint，并在 HTTP listen 前完成模型加载。

**Acceptance:**
- `laya_server` 无 torch/transformers 依赖。
- 真实 Mac 服务 smoke 返回 typed answer 且 `output_tokens=0`。
- Qwen/Jev runtime 与 Prompt-only 实验文件从当前实现删除。

**Rules:**
- 不复制 Laya 内部 logits/scoring 代码。
- 模型加载失败直接退出；请求失败不伪造答案。
- 服务只面向 Apple Silicon Mac，不增加 Windows/CUDA 兼容分支。

---

## P1-T1 建立 Laya-MLX HTTP 决策服务

**Files:**
- Replace: `python_backend/jev_server/` -> `python_backend/laya_server/`
- Replace: `python_backend/shared/jev_protocol.py` -> `python_backend/shared/laya_protocol.py`
- Replace: `python_backend/scripts/jev_server.py` -> `python_backend/scripts/laya_server.py`
- Replace: `python_backend/scripts/jev_server_smoketest.py` -> `python_backend/scripts/laya_server_smoketest.py`

**Step 1: 依赖与模型**

`laya_server` 只声明 HTTP/schema 所需依赖与 `laya-mlx`。默认 checkpoint 固定为 `aac6fef/laya-multilingual-mlx`，允许显式 `--model` 覆盖用于实验，但不自动切换模型。

**Step 2: 服务边界**

请求保持 `model/state/questions`；问题支持 Laya 原生 `choice/score/noul`。启动时先 `laya.load()`，成功后才监听端口。响应直接保留 Laya `answers/usage`，附加服务端 `latency_ms`；模型 ID 不匹配、非法 schema、推理异常均返回明确非 200。

**Step 3: 测试与真实 smoke**

覆盖合法 typed questions、模型不匹配、非法问题和 runtime exception；随后在 Mac 真实启动服务并运行非音乐 smoke，确认 `output_tokens=0`。

**Step 4: 原子提交**

只提交 Laya runtime、协议、入口和对应测试。

---

## P1-T2 删除 Qwen/Jev/CLM 实验路径并收敛 Python 工具

**Files:**
- Delete: `python_backend/shared/companion_prompt_profiles.py`
- Delete: `python_backend/scripts/companion_prompt_benchmark.py`
- Delete: `python_backend/tests/test_companion_prompt_benchmark.py`
- Modify: `python_backend/scripts/companion_e2e_acceptance.py`
- Modify: `python_backend/README.md`
- Delete: `.github/features/companion-jev-prompt-optimization/`

**Step 1: 删除失效实验**

删除只为 Qwen Prompt 分解、candidate prior、CLM 对照服务的代码与现行计划。Git 历史保留，不在工作树保留兼容说明或双轨。

**Step 2: E2E 工具改为 Laya 真源**

`companion_e2e_acceptance.py` 的决策请求改用 Laya 模型 ID和 typed action question；保留与 Aria/MIDI 验证有关的通用部分。

**Step 3: 文档收敛**

Python README 只保留 Laya 本机启动、smoke、Bonjour/端口和失败边界，不再给出 Qwen/CLM/Jev 启动方式。

**Step 4: 验证与原子提交**

运行受影响 Python tests、`py_compile` 和旧符号扫描后提交。

---

## Phase Audit

- Audit file: `audit-p1.md`
- Rule: 完成本 phase 全部 tasks 后，`executing-plans` 必须自动进入该文件的审计闭环
