# 术语表

## 业务术语
| 术语 | 定义 |
| --- | --- |
| Piano Dialogue | 你弹一句、AI 回一句的轮转式流程 |
| Step 1 / 2 / 3 | 校准、选曲、练习三步流 |
| Take | 一次录音或对话回放的持久化产物 |
| Fallback（兜底） | 当理想数据缺失时，系统主动选择替代行为继续运行；可能导致还原度偏离 MusicXML 语义 |

## 架构术语
| 术语 | 定义 |
| --- | --- |
| `MIDIEvent` | macOS 统一输入模型 |
| `DialogueNote` | Swift 和 Python 共享的音符契约 |
| `PracticeStep` | AVP 练习推进单元 |
| `PracticeStepNote` | step 内单个音符的期望值（含 `midiNote`、`staff/voice`、以及由 staff 推导的 `hand`） |
| `ScoreHand` | 谱面左右手语义：`right/left`；当前由 staff 推导（`staff <= 1` 为右手，`staff >= 2` 为左手；缺失 staff 视为右手） |
| `MusicXMLPianoGrandStaffNormalizer` | 钢琴双 part 归一化器：将 MusicXML 中两个独立 `<part>`（高/低音谱号）合并为单 part + staff=1/2，修复左手音符丢失问题 |
| `MusicXMLHandRouter` | 单谱表导入兜底路由器：当 score 未出现 `staff>=2` 且音域足够宽时，按 pitch 阈值把 notes 自动补成 staff=1/2，以驱动左右手与双谱表渲染 |
| `PianoModeProtocol` | AVP 钢琴模式协议：定义模式 id、pickerCard、准入条件、tracking 选择、准备页工厂与练习会话工厂；通过 `PianoModeRegistryService` 注册三种默认模式（RealAudio / BluetoothMIDI / Virtual） || `PracticeSessionViewModelFactoryService` | 按 `PianoModeProtocol` 实现创建 `PracticeSessionViewModel` 并注入对应模式的依赖（替代旧 extension 拆分方式） |
| `PracticeMIDIInputCoordinator` | BLE MIDI 练习输入协调器：消费 MIDI1/MIDI2 note-on 推进 step（使用 `MIDIPracticeStepMatcher`） |
| `PracticeAudioRecognitionCoordinator` | 音频识别练习输入协调器：RealAudio 模式下消费音频识别结果推进 step |
| `PracticePlaybackCoordinator` | 练习回放协调器：管理 autoplay、manual replay 与 sequencer 生命周期 |
| `PracticeHighlightGuideController` | 练习高亮引导控制器：管理当前 step 的 highlight guide 数据 |
| `CalibrationFlowViewModel` | Step 1 校准流程 ViewModel：从 ARGuideViewModel 拆分出的校准编排逻辑 |
| `PracticeLocalizationViewModel` | 练习定位 ViewModel：从 ARGuideViewModel 拆分出的定位编排逻辑 |
| `PracticeFlowCoordinator` | 练习流程协调器：编排 Step 3 的进入/退出与窗口切换 |
| `PianoModePreparationRoute` | 钢琴模式准备页路由：替代旧 AnyView factory 的类型安全路由方案 |
| `AsyncStreamBroadcaster` | 多播 AsyncStream 工具：允许多个订阅者消费同一事件流（用于 BLE MIDI 事件广播） |
| `MIDIPracticeStepMatcher` | BLE MIDI 模式下的确定性 step 判定器：不依赖 velocity 门槛，按 note-on 推进 |
| `AudioStepAttemptAccumulator` | 音频模式下的 step 匹配累积器：按音频识别结果判定 step 通过 |
| `PracticeHandGateController` | 练习手部门控控制器：管理 hand-separated step matching 的左右手分别满足逻辑 |
| `StepMatcher` | step 匹配协议：定义 step 通过判定的抽象接口 |
| `AIPerformanceCoordinator` | AI 表演协调器：管理虚拟表演者的生成、回放与交互 |

| `PianoModeRegistryService` | 钢琴模式注册表：持有 `[any PianoModeProtocol]`，按 id 查找模式；注入到 `WindowCoordinator` 与 `ARGuideViewModel`，驱动类型选择、准备页工厂与练习会话注入 |
| `WindowCoordinator` | AVP 窗口导航协调器：持有 `FlowState` 与 `PianoModeRegistryProtocol`，并通过 `pendingTransition(from,to)` 让目标窗口在激活后关闭来源窗口，实现“单窗口可见”的多窗口导航 |
| `MIDI1InputEvent` | AVP BLE MIDI 输入事件模型（MIDI 1.0 channel voice）：note on/off、CC、pitch bend、program change、pressure 等 |
| `MIDI2InputEvent` | AVP BLE MIDI 输入事件模型（MIDI 2.0 channel voice）：note on/off、CC、pitch bend、program change、pressure 等（保留高精度值域） |
| `PracticeState` | AVP Step 3 练习状态机：`idle`（无 steps）、`ready`（已就绪但未开始）、`guiding`（引导中）、`completed`（完成） |
| `DataProviderState` | AR tracking provider 的运行状态 |
| `ARTrackingMode` | ARTracking provider 运行模式：校准/练习（BLE MIDI 练习阶段不启用 hand） |
| `KeyboardFrame` | 从 A0/C8 推导的键盘局部坐标系（A0 为原点，+X 指向 C8） |
| `frontEdgeToKeyCenterLocalZ` | 在 keyboard-local 中，前沿线（z=0）到按键中心线的 Z 偏移（通常为 ±keyDepth/2） |
| `AutoplayPerformanceTimeline` | 统一调度 note on/off、踏板、guide、step 和 fermata pause 的播放时间线 |
| `PianoHighlightGuide` | 钢琴高亮引导元素，包含 trigger/release/gap 三种类型 |
| `PianoHighlightGuideKind` | 引导类型：trigger（按下）、release（松开）、gap（空闲） |
| `GrandStaffNotationView` | AVP 练习页的双谱表五线谱视图（Canvas + Bravura SMuFL 绘制 staff lines、clef/key/time、barlines、noteheads、stems、beams、flags；支持垂直滚动） |
| Bravura / SMuFL | SMuFL（Standard Music Font Layout）是音乐符号字体的 Unicode 编码标准；Bravura 是其开源参考实现（501 KB OTF），用于五线谱中谱号/调号/拍号/升降号的高质量渲染 |
| `GrandStaffNotationContext` | 五线谱左侧上下文（谱号/调号/拍号）契约 |
| `Hand-separated step matching` | 练习判定开关：当开启时，当前 step 的右手 expected 与左手 expected 需要分别满足才算通过（缺失某只手 expected 视为已满足） |
| `GazePlaneDiskConfirmationViewModel` | 虚拟钢琴放置确认状态：圆盘可见、双手掌心稳定倒计时、确认完成 |
| `KeyContactDetectionService` | 虚拟钢琴按键接触检测服务，使用迟滞避免误触 |
| `VirtualPianoKeyGeometryService` | 虚拟钢琴 88 键几何生成服务 |
| `VirtualPianoOverlayController` | 虚拟钢琴 3D 键盘 RealityKit 渲染控制器 |
| `PlaneDetectionProvider` | ARKit 平面检测 provider（本项目用于 horizontal planes） |
| `MusicXMLExpressivityOptions` | MusicXML 表现力选项，控制 wedge、grace、fermata、arpeggiate、words semantics 的启用 |
| Bonjour（mDNS/DNS-SD） | 局域网服务发现机制；本项目用 `_lonelypianist._tcp.local.` 广播/浏览后端 |
| Local Network 权限 | visionOS 的局域网访问授权；被拒绝时 Bonjour 浏览会进入 `.denied` |
| `GenerateParams.strategy` | 后端生成策略：`model`（加载大模型）、`deterministic`（轻量规则生成）、`rule`（规则引擎：和声/节奏/动机） |
| `PhraseRecorder` | AVP 侧把真实/虚拟按键事件录成短句片段，用作后端生成的输入 |

## 音频识别术语
| 术语 | 定义 |
| --- | --- |
| `HarmonicTemplateScorer` | 谐波模板评分器，通过谐波能量比和支配度计算音符匹配置信度 |
| `TargetedHarmonicTemplateDetector` | 目标谐波模板检测器，针对预期音符和错误候选音符进行检测 |
| `partial completeness` | 谐波分片完整性，用于判断是否有足够的谐波能量支持音符识别 |
| `tonalRatio` | 谐波能量比，谐波区域能量与周围能量的比值 |
| `dominance` | 支配度，预期音符相对于错误候选音符的能量优势 |
| `rms noise gate` | RMS 噪声门，过滤低能量静音段 |

## 存储术语
| 术语 | 定义 |
| --- | --- |
| `StoredWorldAnchorCalibration` | A0/C8 世界锚点校准 |
| `SongLibraryIndex` | 曲库索引（entries + lastSelectedEntryID） |
| `SongLibraryEntry` | 单条曲目元数据 |
| `RecordingTake` | AVP 录制产物：包含 id、name、createdAt 与 events 列表；由 `RecordingTakeRecorder` 生成，`RecordingTakeStore` 持久化到 `Documents/TakeLibrary/takes.json` |
| `dialogue_debug bundle` | Python 调试落盘目录 |

## 易混淆概念
- **stored calibration**：持久化的 anchor ID。
- **runtime calibration**：当前场景里根据 tracked anchors 解析出来的几何结果。
- **导入成功** 不等于 **可开始练习**：还要能生成有效 steps，并成功定位（虚拟钢琴模式仅需导入谱面）。
- **fallback（兜底）** 不等于 **error handling（错误处理）**：fallback 是主动选择替代行为继续运行，error handling 是捕获错误并恢复。
- **虚拟钢琴模式** vs **实体钢琴模式**：虚拟钢琴无需校准和定位，通过 gaze-plane + 双手掌心确认放置 3D 键盘后直接进入练习；实体钢琴需要 Step 1 校准 + AR 定位。两者共享 `PracticeSessionViewModel` 的匹配与 step 推进逻辑（无 correct/wrong 反馈态），但按键检测路径不同（`KeyContactDetectionService` vs `PressDetectionService`）。
- **staff（谱表号）** vs **左右手（ScoreHand）**：当前系统把 `staff <= 1` 解释为右手、`staff >= 2` 解释为左手；对缺失 staff 的单谱表曲谱，会在导入阶段用 `MusicXMLHandRouter` 补全 staff，之后所有下游（step、guide、五线谱、键盘高亮、按手判定）都只看 staff→hand 推导结果。
- **双 part 归一化** vs **单谱表自动分手**：前者处理"钢琴大谱表被拆成两个独立 `<part>`"的非标准导出（`MusicXMLPianoGrandStaffNormalizer`），后者处理"单谱表内缺失 staff 信息"的简化导出（`MusicXMLHandRouter`）。两者都发生在导入管线早期，且都为下游提供 staff=1/2 的一致数据。
- **PianoModeProtocol** vs **旧 PianoKind 枚举**：旧版用 `PianoKind` 枚举做 switch 分支；新版用 `PianoModeProtocol` 协议 + `PianoModeRegistryService` 注册表，每种模式自包含准备页工厂、练习会话工厂和准入逻辑，无需在调用方做 switch。`FlowState.selectedPianoModeID` 存储模式 id 字符串，由注册表解析为具体模式。

## Coverage Gaps
- 发布和版本语义仍散落在 README 和流程中，没有独立页面。
- 音频识别的各种 fallback 状态和模式切换仍在演进中。
- 虚拟钢琴的迟滞阈值和交互细节可能随真机调优而变化。
