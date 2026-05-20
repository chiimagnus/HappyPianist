# Module: ImprovEngines (SwiftPM)

`Packages/ImprovEngines/` 是 AVP 端“本地即兴生成后端”的 SwiftPM 本地包，提供：

- `ImprovProtocol`：与网络协议对齐的 `GenerateRequest/Params/ResultResponse/ErrorResponse` 与 `ImprovDialogueNote` 数据结构（含可选 `seed`）。
- `ImprovEngines`：
  - `PythonRandom`：对齐 CPython `random.Random(seed)` 的 MT19937 RNG（用于 deterministic / rule 的随机分支可复现）。
  - `DeterministicImprovGenerator`：deterministic 本地生成实现。
  - `RuleImprovGenerator`：rule 本地生成实现。

AVP 侧通过后端实现接入：

- `LonelyPianistAVP/Services/Practice/AI/ImprovBackends/LocalDeterministicImprovBackend.swift`
- `LonelyPianistAVP/Services/Practice/AI/ImprovBackends/LocalRuleImprovBackend.swift`

注意：后端选择在 practice 的 settings popover 中进行，并且严格只使用用户所选后端（失败只提示，不自动切换）。

