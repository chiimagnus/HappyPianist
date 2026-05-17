# AVP Piano Modes（钢琴模式能力矩阵）

本文回答两个问题：
1) **体验可组合**：三种钢琴模式如何复用同一条「选曲 → Step3 练习」主流程。
2) **能力可替换**：输入源、tracking、匹配规则、推进策略如何被拆成可独立替换的组件。

> 约定：本文的“模式”指 `PianoModeProtocol` 的实现；它是“产品体验层的能力集合”，并不等同于某个单一 Service。

## 总览：三种模式的能力矩阵（体验视角）

| 能力/体验维度 | 真实钢琴（音频） | 真实钢琴（蓝牙 MIDI） | 虚拟钢琴 |
| --- | --- | --- | --- |
| 入口卡片 | “真实钢琴（音频）” | “真实钢琴（蓝牙 MIDI）” | “虚拟钢琴” |
| 准备阶段（Preparation）主要目标 | 完成校准，让系统知道真实钢琴在空间中的位置 | 连接系统 Bluetooth MIDI + 完成校准 | 放置虚拟钢琴（空间中） |
| 进入曲库/练习的准入条件 | 校准完成 | 校准完成 + 已连接 Source 数量 > 0 | 虚拟钢琴已放置 |
| Step3 的“弹奏输入”来自哪里 | 主要来自手势触键（按键接触推断）；并可能叠加麦克风音频识别（受设备/设置影响） | 来自蓝牙 MIDI 的 `noteOn` 事件 | 来自虚拟琴键触碰（down/started/ended） |
| 是否需要 App 即时发声 | 不需要（真实钢琴自己发声） | 不需要（真实钢琴自己发声） | 需要（虚拟钢琴由 App 播放） |
| Step3 的“按对了 → 下一步”判定风格 | 集合/窗口内匹配为主（容错见下） | 事件/窗口内聚合为主（容错见下） | 集合/窗口内匹配为主（容错见下） |
| Tracking 侧重点（练习时） | `practiceVirtualOrAudio` | 默认 `practiceBluetoothMIDI`（当未开启虚拟钢琴叠加） | `practiceVirtualOrAudio` |
| 录制来源文案 | 手势触键推断 | Bluetooth MIDI | 虚拟钢琴触键 |

## 总览：能力拆分（技术视角）

下面这些“可替换能力”共同组成 Step3 的体验：

- **模式能力（体验层组合）**：`PianoModeProtocol`
  - 提供：卡片文案/图标、准备页、准入条件、tracking 选择、录制文案、练习会话注入（依赖组合）
- **输入源（事件流）**：`PracticeInputEventSourceProtocol`
  - 提供：蓝牙 MIDI 输入的异步事件流（`AsyncStream`）
- **音频识别（事件流 + 状态流）**：`PracticeAudioRecognitionServiceProtocol`
  - 提供：麦克风识别的事件流、状态更新、debug snapshot
- **匹配规则（按对与容错）**
  - `ChordAttemptAccumulatorProtocol`：负责把短时间窗口内的“按下集合”累积起来
  - `StepMatcherProtocol`：负责判断 pressed 集合是否匹配 expected 集合（含 tolerance）
- **推进策略（手动下一步/重播）**：`ManualAdvanceStrategyProtocol`
  - 提供：按“逐步/按小节”等策略计算下一步索引与重播范围
- **tracking 服务**：`ARTrackingServiceProtocol`
  - 提供：指尖/世界锚点/平面锚点等数据源与 provider 状态
- **发声/自动播放服务**：`PracticeSequencerPlaybackServiceProtocol`
  - 提供：自动播放、one-shot、live notes（虚拟钢琴触键实时发声依赖它）

## 模式与实现入口（从代码定位到体验）

### 模式定义与注册
- 协议：`LonelyPianistAVP/Services/AppFlow/PianoModeProtocol.swift`
- 注册表：`LonelyPianistAVP/Services/AppFlow/PianoModeRegistryService.swift`
- 默认三模式实现：`LonelyPianistAVP/Services/AppFlow/DefaultPianoModes.swift`

### 模式如何驱动用户体验主流程
- 选择模式（卡片列表）：`LonelyPianistAVP/Views/PianoChoose/PianoTypePickerView.swift`
- preparation 窗口派发准备页：`LonelyPianistAVP/Views/Preparation/PreparationWindowRootView.swift`
- “能否进入曲库/练习”的 gating：由各模式实现 `PianoModeProtocol.canProceedToLibrary(flowState:)`（准备页按钮禁用/启用）

### 模式如何影响 Step3（练习会话注入 + tracking + 录制）
- 注入练习会话（为不同模式组合不同依赖）：`LonelyPianistAVP/Services/Practice/Session/PracticeSessionViewModelFactoryService.swift`
- 练习时 tracking 模式选择：`LonelyPianistAVP/ViewModels/ARGuideViewModel.swift`
- 录制来源文案：`LonelyPianistAVP/ViewModels/ARGuideViewModel.swift`

## 补充：对“可组合/可替换”的直观理解

- “可组合”指：**主流程 UI 不需要分叉成三套**。模式只负责把自己需要的准备页/准入条件/输入链路注入进去。
- “可替换”指：输入源、tracking、匹配、推进等能力**各自都有协议边界**；未来想做“更慢按也能过的和弦识别”，可以只替换/新增一个匹配组件，而不是把整个练习流程推倒重来。
