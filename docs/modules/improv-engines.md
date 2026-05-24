# Module: ImprovEngines (SwiftPM)

`Packages/ImprovEngines/` 是 AVP 端“本地即兴生成后端”的 SwiftPM 本地包，提供：

- `ImprovProtocol`：与网络协议对齐的 `GenerateRequest/Params/ResultResponse/ErrorResponse` 与 `ImprovDialogueNote` 数据结构（含可选 `seed`）。
- `ImprovEngines`：
  - `PythonRandom`：对齐 CPython `random.Random(seed)` 的 MT19937 RNG（用于 rule 的随机分支可复现）。
  - `RuleImprovGenerator`：rule 本地生成实现。

AVP 侧通过后端实现接入：

- `LonelyPianistAVP/Services/Practice/AI/ImprovBackends/LocalRuleImprovBackend.swift`
- `LonelyPianistAVP/Services/Practice/AI/ImprovBackends/LocalCoreMLDuetImprovBackend.swift`

注意：后端选择在 practice 的 settings popover 中进行，并且严格只使用用户所选后端（失败只提示，不自动切换）。

## Local CoreML Duet（Performance RNN）

本地 CoreML 后端使用 Performance RNN 的单步模型做自回归采样（seed 可复现），模型文件不入库。

相关代码：

- `LonelyPianistAVP/Services/Practice/AI/CoreMLDuet/PerformanceRNNCoreMLModelLoader.swift`
- `LonelyPianistAVP/Services/Practice/AI/CoreMLDuet/PerformanceRNNImprovGenerator.swift`
- `LonelyPianistAVP/Services/Practice/AI/ImprovBackends/LocalCoreMLDuetImprovBackend.swift`

### 1) 生成 CoreML 模型（.mlpackage）

使用仓库内脚本把 Magenta `.mag` bundle 转成 `AIDuetPerformanceRNN.mlpackage`：

```bash
python3 python_backend/duet/convert_performance_rnn_to_coreml.py \
  --out LonelyPianistAVP/Resources/Models/AIDuetPerformanceRNN.mlpackage
```

备注：

- 脚本依赖 `tensorflow` / `note-seq` / `coremltools` / `numpy` 等 Python 包（按你的 Python 环境自行安装）。
- 默认输入 bundle 是 `python_backend/duet/models/performance_with_dynamics.mag`（若你有其他 bundle，可用 `--bundle` 指定）。

### 2) 放置并加入 Xcode target

推荐本地放置路径：

- `LonelyPianistAVP/Resources/Models/AIDuetPerformanceRNN.mlpackage`

该目录与模型文件类型已在 `.gitignore` 中忽略（避免误提交）。

然后在 Xcode 中把模型加入 `LonelyPianistAVP` target（确保 Target Membership 勾选 `LonelyPianistAVP`），让它随 app bundle 一起打包。

### 3) 排障

- UI 显示缺少模型：检查文件名是否为 `AIDuetPerformanceRNN.mlpackage` 或 `AIDuetPerformanceRNN.mlmodelc`，以及是否加入了 `LonelyPianistAVP` target。
- 首次加载较慢：若 bundle 中是 `.mlpackage`，首次运行可能会触发 `MLModel.compileModel` 的编译开销，属于正常现象。
