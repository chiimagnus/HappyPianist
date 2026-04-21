# 模块：LonelyPianistAVP（visionOS）

## 职责与边界
- **负责**：MusicXML 导入解析、练习步骤构建、A0/C8 空间校准、手部追踪按键判定、AR 高亮引导。
- **不负责**：MIDI 映射、Dialogue 模型推理、曲谱转 MusicXML（仅消费外部准备好的 MusicXML）。
- **位置**：`LonelyPianistAVP/` 与 `LonelyPianistAVPTests/`。

## 目录范围
| 路径 | 角色 | 备注 |
| --- | --- | --- |
| `LonelyPianistAVP/AppModel.swift` | 全局状态中枢 | 串接导入、校准、练习会话、手部追踪 |
| `LonelyPianistAVP/ViewModels/` | 会话状态编排 | `PracticeSessionViewModel` |
| `LonelyPianistAVP/Services/HandTracking/` | 手部追踪与按键判定 | ARKit + 几何检测 |
| `LonelyPianistAVP/Services/Calibration/` | 校准点捕获 | A0/C8 数据来源 |
| `LonelyPianistAVP/Services/RealityKit/` | 空间叠层渲染控制器 | 指尖点、reticle、键位高亮 |
| `LonelyPianistAVP/Services/` | MusicXML/步骤/存储服务 | parser/import/stepBuilder/store |

## 入口点与生命周期
| 入口 / 类型 | 位置 | 何时触发 | 结果 |
| --- | --- | --- | --- |
| App 启动 | `LonelyPianistAVPApp.swift` | 启动时 | 建立 WindowGroup + ImmersiveSpace |
| 文件导入 | `ContentView.handleImportResult` | 用户选择 MusicXML | 复制文件 -> parse -> build steps -> 更新 AppModel |
| 进入 AR Guide | `ToggleImmersiveSpaceButton` | 用户点击 Start AR Guide | 打开 ImmersiveSpace |
| 校准点捕获 | `ImmersiveView` SpatialTapGesture | 用户点 Set A0/C8 后空间点击 | 更新 calibrationCaptureService |
| 手部追踪循环 | `HandTrackingService.start()` | ImmersiveView onAppear | 持续更新指尖坐标 |

## 关键文件
| 文件 | 用途 | 为什么值得看 |
| --- | --- | --- |
| `AppModel.swift` | AVP 状态汇聚与 session 配置触发 | 决定“何时可开始引导” |
| `ContentView.swift` | 非沉浸式入口 UI | 导入、校准状态、练习控制起点 |
| `ImmersiveView.swift` | 沉浸式核心交互 | RealityView update + HUD 控制 |
| `ViewModels/PracticeSessionViewModel.swift` | 练习状态机 | step 推进与反馈逻辑中心 |
| `Services/HandTracking/HandTrackingService.swift` | ARKit 手部追踪接线 | 指尖数据来源 |
| `Services/HandTracking/PressDetectionService.swift` | 几何过平面检测 | “按下”判定核心 |
| `Services/MusicXMLParser.swift` | XML 解析与时间线处理 | 音符正确性的基础 |
| `Services/PracticeStepBuilder.swift` | 解析事件到步骤转换 | 引导粒度定义 |

## 上下游依赖
| 方向 | 对象 | 关系 | 影响 |
| --- | --- | --- | --- |
| 上游 | 外部准备好的 MusicXML | 文件输入来源 | 解析质量决定后续步骤质量 |
| 上游 | ARKit HandTrackingProvider | 指尖位置实时流 | 不可用时引导无法自动推进 |
| 下游 | RealityKit overlay controllers | 可视化输出层 | 当前步骤与反馈色态可见化 |
| 下游 | 本地 calibration/imported file 存储 | 状态恢复与复用 | 提升二次进入体验 |

## 对外接口与契约
| 接口 / 命令 / 类型 | 位置 | 调用方 | 含义 |
| --- | --- | --- | --- |
| `MusicXMLImportServiceProtocol` | `Services/MusicXMLImportService.swift` | `ContentView` | 文件导入与副本落地 |
| `MusicXMLParserProtocol` | `Services/MusicXMLParser.swift` | `ContentView` | XML -> `MusicXMLScore` |
| `PracticeStepBuilderProtocol` | `Services/PracticeStepBuilder.swift` | `ContentView` | score -> step 列表 |
| `PressDetectionServiceProtocol` | `Services/HandTracking/PressDetectionService.swift` | `PracticeSessionViewModel` | 点位 -> 按下音符集合 |
| `PianoCalibrationStoreProtocol` | `Services/PianoCalibrationStore.swift` | `AppModel` | 校准读写 |

## 数据契约、状态与存储
- 关键模型：
  - `MusicXMLNoteEvent`（tick、duration、staff、voice）
  - `PracticeStep`（按 tick 分组）
  - `PianoCalibration`（A0/C8/planeHeight/whiteKeyWidth）
  - `PianoKeyRegion`（中心与边界盒）
- 状态：
  - `PracticeState: idle/ready/guiding/completed`
  - `TrackingState: idle/running/unavailable`
  - `ImmersiveSpaceState: closed/inTransition/open`
- 存储：
  - Documents 下导入谱面副本与 `piano-calibration.json`。

## 配置与功能开关
- `noteMatchTolerance` 默认 1（±1 半音容错）。
- `PressDetectionService.cooldownSeconds` 默认 0.15。
- `ChordAttemptAccumulator.windowSeconds` 默认 0.6。
- 校准可切换 `raycast` / `manualFallback` 模式。

## 正常路径与边界情况
- 正常路径：导入 MusicXML -> 构建 steps -> 完成 A0/C8 校准 -> Start AR Guide -> 手势触发步骤推进。
- 边界情况：
  - 解析失败：`importErrorMessage` 显示错误。
  - 校准不完整：保存失败并提示 `Calibration is incomplete`。
  - 手部追踪不支持：状态标记 unavailable 并中止更新。
  - 按下无关音符：反馈 `wrong`（红色）。

## 扩展点与修改热点
- 扩展点：
  - 更复杂 step 匹配策略（节奏容差、手别策略）。
  - 键位几何改进（黑白键差异建模）。
  - 更强校准流程（多点拟合、自动平面估计）。
- 高风险区：
  - `MusicXMLParserDelegate.finalizeNote` 时间线计算；
  - `PracticeSessionViewModel.handleFingerTipPositions`；
  - `ImmersiveView` update 循环与状态同步。

## 测试与调试
- 测试文件：
  - `LonelyPianistAVPTests/MusicXMLParserTests.swift`
  - `LonelyPianistAVPTests/PracticeStepBuilderTests.swift`
  - `LonelyPianistAVPTests/StepMatcherTests.swift`
  - `LonelyPianistAVPTests/ChordAttemptAccumulatorTests.swift`
- 调试抓手：
  - HUD `Hands: ...` 与 `Practice: ...` 文案。
  - 绿色手指点 + 黄色 reticle + 键位高亮的三层可视化。

## 示例片段
```swift
let detected = pressDetectionService.detectPressedNotes(
    fingerTips: fingerTips,
    keyRegions: keyRegions,
    at: timestamp
)
```

```swift
if buildResult.unsupportedNoteCount > 0 {
    appModel.importErrorMessage = "Imported with \(buildResult.unsupportedNoteCount) unsupported notes ignored."
}
```

## Coverage Gaps
- 当前键位几何按 88 键等间距近似，黑键与真实键形差异尚未单独建模。
- 未见针对 Immersive UI 的自动化测试，主要依赖手工场景验证。

## 来源引用（Source References）
- `LonelyPianistAVP/LonelyPianistAVPApp.swift`
- `LonelyPianistAVP/AppModel.swift`
- `LonelyPianistAVP/ContentView.swift`
- `LonelyPianistAVP/ImmersiveView.swift`
- `LonelyPianistAVP/ToggleImmersiveSpaceButton.swift`
- `LonelyPianistAVP/ViewModels/PracticeSessionViewModel.swift`
- `LonelyPianistAVP/Services/HandTracking/HandTrackingService.swift`
- `LonelyPianistAVP/Services/HandTracking/PressDetectionService.swift`
- `LonelyPianistAVP/Services/Practice/ChordAttemptAccumulator.swift`
- `LonelyPianistAVP/Services/MusicXMLParser.swift`
- `LonelyPianistAVP/Services/PracticeStepBuilder.swift`
- `LonelyPianistAVP/Services/PianoCalibrationStore.swift`
- `LonelyPianistAVPTests/MusicXMLParserTests.swift`
