# Audit P1 - companion-laya-mlx

- 审计方式：`plan-task-auditor`
- 审计范围：`plan-p1.md`
- feature 目录：`.github/features/companion-laya-mlx/`
- 粒度：`phase`

## 任务看板

- [x] P1-T1 建立 Laya-MLX HTTP 决策服务
- [x] P1-T2 删除 Qwen/Jev/CLM 实验路径并收敛 Python 工具

## 任务到文件的映射

- P1-T1
  - `python_backend/laya_server/`
  - `python_backend/shared/laya_protocol.py`
  - `python_backend/scripts/laya_server.py`
  - `python_backend/scripts/laya_server_smoketest.py`
- P1-T2
  - `python_backend/shared/companion_laya.py`
  - `python_backend/scripts/companion_e2e_acceptance.py`
  - `python_backend/tests/test_companion_laya.py`
  - `python_backend/README.md`
  - 删除旧 Prompt benchmark/profile/tests 与旧 Jev Feature Plan

## 发现项

## 发现 F-01

- 任务：`P1-T1`
- 严重级别：`Medium`
- 状态：`Resolved`
- 位置：`python_backend/shared/laya_protocol.py`
- 摘要：`HTTP schema 仍保留旧 Jev 的 2..50 criteria 与 <=256 questions 人工上限`
- 风险：`会拒绝 Laya 原生可接受的 typed-decision 请求，使薄 wrapper 与上游契约不一致，并遗留无依据安全围栏。`
- 预期修复：`只保留 Laya 原生必要约束：criteria/questions 非空、label 合法；删除旧数量上限。`
- 验证：`pytest laya_server/tests + direct protocol cases + real HTTP smoke`
- 解决证据：`commit 9b6ddfa2；Laya server tests 9/9 PASS；真实 HTTP smoke PASS。`


## 修复日志

- F-01：删除从旧 Jev 继承的 option/question 数量上限，HTTP schema 只保留 Laya 原生所需的非空与 label 合法性约束；`9b6ddfa2`。

## 验证日志

- `PYTHONPATH=. python_backend/laya_server/.venv/bin/python -m pytest python_backend/laya_server/tests python_backend/tests/test_companion_laya.py -q` -> `PASS (14/14)`
- `uv run --project python_backend/aria_server python -m unittest python_backend.tests.test_companion_acceptance_corpus -v` -> `PASS (2/2)`
- `HF_HUB_OFFLINE=1 ... laya.load(...); agent.predict(...)` -> `PASS`，模型 SHA256 与 manifest 一致，热态 median `10.15 ms`，`output_tokens=0`
- `python_backend/scripts/laya_server_smoketest.py --host 127.0.0.1 --port 8767` -> `PASS`，真实 HTTP choice 正确
- 错误 model 的真实 `/v1/classifier` 请求 -> `PASS`，HTTP `400` 且不伪造 answer
- `dns-sd -B _lpduet._tcp local.` -> `PASS`，发现 `HappyPianist Laya Classifier`
- `rtk rg ... Qwen|Jev|CLM ... python_backend` -> `PASS`，当前 Python 决策路径无旧实现残留
- `rtk git diff --check` -> `PASS`

## Gate（是否允许进入下一阶段）

- 结论：`Go`
- 理由：Mac 本机 Laya-MLX runtime、typed HTTP、Bonjour、失败边界与旧 Python 路径清理均已验证，唯一审计 finding 已解决。

## 最终状态与剩余风险

- 当前状态：`Resolved`
- 剩余风险：Laya 的钢琴 action criteria 尚未通过固定 MIDI Stage A；两个手工 companion smoke 状态目前都选择 `listen`。这是 P2-T2 的行为质量门禁，不影响 P1 runtime Gate，但在通过 P2 前不能视为产品决策质量已达标。

## 审计约束

- 本文件对应一个 phase，不对应单个 task
- 如果由 `executing-plans` 自动进入审计，也沿用同一模板
