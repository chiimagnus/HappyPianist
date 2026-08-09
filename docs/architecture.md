# 架构

源码目录、符号定义和调用关系由 CodeGraph 提供；本页只记录不能从调用图直接得到的职责、边界和不变量。

## 依赖方向

```text
SwiftUI / RealityKit
        ↓
ViewModel / AppState
        ↓
Services / Repositories
        ↓
Models / Contracts
```

- **Model**：纯数据与契约，不持有 UI 或文件、网络、设备副作用。
- **View**：渲染和发送 intent，不直接读写 repository 或设备。
- **ViewModel**：编排状态、生命周期和依赖，不复制服务事实。
- **Service / Repository**：隔离文件、MusicXML、音频、MIDI、ARKit、AI 与诊断副作用。

`HappyPianistAVP` 与 `HappyPianistMac` 是独立 composition root 与 App Sandbox container。两者只能经由共享 package products 复用业务核心，不能共享 App service、persistent Documents、platform adapter 或窗口/空间 UI。Mac host 只包含 2D 曲库、系统可见 CoreMIDI 与共享 MIDI-only lifecycle；AR/RealityKit、手部/虚拟琴、音频识别、AVFoundation 与 AI 仍只在 AVP host。

共享根模块的依赖只能向下：`Diagnostics` 不依赖 App、Practice、Library、MusicXML、MIDI 或任何 UI/设备框架；App 仅通过其公开契约注入 reporter、store 与 exporter。

`MusicXML` 同样是根模块，仅依赖 Foundation、UniformTypeIdentifiers 与其单次声明的 ZIPFoundation；它不得引用 Practice preparation error、Library、MIDI、Diagnostics 或任何 UI/设备框架。

`MIDI` 只依赖 `Diagnostics`，拥有 CoreMIDI transport 与稳定端点契约；Practice、录制和 AI 只消费其事件/输出协议，不得反向依赖 CoreMIDI 实现。

`Practice` 依赖 `MusicXML`、`MIDI` 与 `Diagnostics`：它拥有准备输入契约、唯一的 `ScorePerformancePlan` 及 steps、琴键和记谱投影，以及匹配、对齐、assessment、coaching、transport、progress contracts、session recorder、MIDI take（模型、JSON store、replay/export）和共享 MIDI-only lifecycle。它只通过 `MIDI` 的契约工作，不直接导入 CoreMIDI；不得引用 App、Library、Notation、SwiftUI、RealityKit、AVAudio、音频识别或手部/虚拟琴实现。

`Notation` 只依赖 `Practice` 与 `MusicXML`：它拥有 Grand Staff 的 glyph、layout、Canvas/SwiftUI renderer 和 accessibility overlay，只接收 projection、overlay、measure spans、context 与 hand mode。它不得引用 session navigation、progress、Library、AR/RealityKit 或 piano-key tint types；Practice 不得反向引用 Notation。

`Library` 只依赖 `Practice`、`MusicXML` 与 `Diagnostics`：它拥有曲库 index、路径、文件 store、导入/恢复事务、entry resolver、bootstrap loader 与 `FilePracticeProgressRepository`。导入在 security scope 内先通过 MusicXML 的公开 archive safety validation，再复制到 app container；它不得引用 `Bundle.main`、AVAudio、SwiftUI、RealityKit 或 Library presentation。Practice 只声明进度契约，绝不反向引用 Library。

新增服务先定义稳定协议，再由 `LiveAppGraph.make()` 注入并接入 consumer。单一实现不提前建 factory、manager 或兼容层。

## 运行边界

| 边界 | 唯一 owner | 必须保持的事实 |
| --- | --- | --- |
| App 与窗口 | `HappyPianistAVPApp`、`AppState` | Library 是入口；preparation 与 practice 是单层 pushed window；immersive space 只承载空间内容。 |
| 组合根 | `LiveAppGraph` | 共享的 index store、曲库 provider、progress repository、diagnostics reporter 与 practice recorder 不在 ViewModel 内重新创建。 |
| 手部可视化 | `ARTrackingService`、`NeonHandOverlayController` | service 将实时骨骼归一为运行期快照并以 current-value async stream 发布；controller 在 `.mixed` immersive practice 中复用固定容量网格渲染荧光手套。Simulator 合成姿态只存在于 controller 的条件编译渲染路径；它不是 AR 输入、练习证据、持久化或诊断。 |
| 示范手引导 | `PianoDemonstrationHandsOverlayController`、`PianoGuideOverlayController` | 默认关闭的 AppStorage 偏好在沉浸空间按 occurrence 混合 Blender 生成的 21 关节骨骼双手与键面贴片；Core 的 `PianoFingeringPlanner` 只消费 transport contact、校准后的纯值键盘快照和可调的 `MotionLimits`，在主 Actor 外以有界确定性 DP 生成指法或显式无解。示范手从当前 transport schedule 按绝对时刻预备、落键、回弹和保持，无法提交的键立即交回贴片。它不参与 ARKit、输入或进度，二维键盘始终保留高亮。 |
| macOS host | `HappyPianistMacApp`、`MacAppGraph`、`MacPracticeViewModel` | 独立沙盒、空 bundled library 和初始导入入口；Mac ViewModel 只绑定 Library resolver、`PracticeRoundSessionController`、MIDI endpoint effect 与 Notation，不复制 reducer、progress 或 playback lifecycle。 |
| 诊断根 | `Packages/HappyPianistCore/Sources/Diagnostics/` | `DiagnosticEvent`、reporter、七日文件 store、OSLog sink、损坏文件隔离与用户归档；不包含音频、AR、Practice 投影或输出指标。 |
| 曲谱根 | `Packages/HappyPianistCore/Sources/MusicXML/` | MusicXML/MXL 解析、结构扩展、模型与安全限制；输入失败以本模块 typed error 表示，不反向依赖 Practice。 |
| MIDI 根 | `Packages/HappyPianistCore/Sources/MIDI/` | 输入/输出 transport、endpoint ID、CoreMIDI route 与输出指标；不包含练习匹配、录制、AI 或界面。 |
| 练习核心 | `Packages/HappyPianistCore/Sources/Practice/` | MusicXML preparation、performance plan、步骤/琴键/记谱投影、运行时 facts/reducers、MIDI-only lifecycle、take 录制/持久化/回放/导出和 progress contracts；不包含曲库文件实现、SwiftUI、RealityKit、AVAudio、音频识别或手部/虚拟琴。 |
| 记谱根 | `Packages/HappyPianistCore/Sources/Notation/` | Grand Staff 的 glyph、layout、rendering、SwiftUI view 与无障碍描述；仅消费 Practice/MusicXML projection，不反向进入 session、progress、Library 或空间功能。 |
| 曲库核心 | `Packages/HappyPianistCore/Sources/Library/` | index、路径、文件、导入/恢复、entry resolver、bootstrap 与 `progress-v1.json` file repository；只依赖 Practice/MusicXML/Diagnostics。 |
| 曲库 App 边界 | `SongLibraryViewModel`、`BundledSongLibraryProvider`、audio services、presentation builders | selection 是内存 intent；`Bundle.main`、音频和 SwiftUI presentation 留在 App，所有持久化事务委托 Library actors。 |
| 曲谱准备 | `PracticePreparationService` | MusicXML 先形成唯一 `ScorePerformancePlan`，再投影 steps、guides 与 notation；播放运行时消费 plan。 |
| 练习会话 | `PracticeRoundSessionController`、`MIDIPracticeSession` | shared controller 唯一拥有 non-spatial range、attempt/progress、feedback 与 assessment/coaching state；host 只编排 presentation/platform adapters。结束顺序是失效输入、停止输入、reset/flush 输出、drain recorder、flush facts、终结 session。 |
| 输入与评价 | platform adapters、`PerformanceObservation`、analyzer | 音频、MIDI、手部证据共用 observation 契约，但保留各自 capability 和 unknown 边界。 |
| 反馈与指导 | assessment、`CoachingDecisionService`、feedback policies | 每次最多一个有范围和完成条件的动作；表现层是持久化事实的派生物。 |
| AI 对弹 | `AIPerformanceService`、`ImprovBackendRegistry` | 严格使用用户选择的 provider；response 是运行期创意内容，不是谱面真值或评分依据。 |

## 不变量

- 正式曲谱来源是 MusicXML；可进入练习的 prepared result 同时具备可演奏 steps 和 measure spans。
- `ScorePerformancePlan` 是声音事件唯一真源；steps、guides、notation 和 tempo 查询都只能从它或 source score 单向投影。
- `PracticeStep` 只负责即时判定；source measure 才是正式练习事实的持久化单位。
- occurrence identity 负责重复结构中的播放位置，source identity 负责跨回合聚合学习事实。
- alignment、逐音 evidence、target profile、`MusicalIssue`、coaching decision 和复测关联只存在运行期。
- 未观察、低置信度、unknown、insufficient 与 degraded capability 不得被改写成用户错误。
- AI/system playback、旧 generation 和后台期间的事件不得进入用户 observation 或 progress。
- 手部骨骼快照与荧光手套均为运行期渲染状态；追踪授权被拒绝、provider 不支持或手部不完整时隐藏，不以假数据替代。只有 Simulator 的渲染分支可生成合成姿态。
- 示范手偏好只保存开关；手型、触键目标、骨骼姿态、动画和键面贴片均是当前 guide 与 transport 的派生渲染状态。每手按 occurrence 独立保留时序，coverage、资产或 `5 mm` 指尖残差失败只让对应键回退贴片；关闭、scene suspend 与退出会取消加载/动作并移除示范手 root，迟到加载不得恢复渲染或 suppression。Reducer、progress 与输入路径均不可引用它。
- progress、metadata、session 是同一 JSON 文件中的独立 concern；调用方不得整份覆盖另两个 concern。
- 诊断只通过 `DiagnosticsReporting` 进入系统日志和筛选后的导出日志；导出不得包含原谱、逐音输入、绝对路径、凭据或 AI 正文。
- 主 Actor 不执行 MusicXML 解析、文件 IO、设备重活；长生命周期任务在 teardown 时取消。

## 修改规则

1. 先用 CodeGraph 查目标符号的调用者和调用路径，再决定共享 owner；不要在每个调用方打补丁。
2. 结构变化只更新 CodeGraph；文档只补充新的意图、不变量或操作约束。
3. 新持久化字段必须先说明 owner、schema 和清理行为；不引入第二套存储。
4. 新输入来源必须定义 observation capability 和未知状态；不把低能力来源伪装成逐音证据。
5. 新实现替换旧实现时，同一 task 删除旧 API、旧状态、旧测试入口和双轨分支。

## 验证分层

- 纯 Model、reducer、range、matcher、alignment、assessment 和 coaching policy：确定性 Swift Testing fixture。
- macOS host：`make build:mac`、`make test:mac` 使用独立 macOS scheme/destination/result bundle；它们不读取或启动 visionOS Simulator。
- SwiftUI、RealityKit、AVFoundation、CoreMIDI 和资源：Xcode / visionOS SDK 与 Simulator。
- 手部追踪、麦克风、真实 MIDI、音频 onset、空间舒适度：Apple Vision Pro 真机。
- 专业能力措辞：遵循[钢琴演奏与专业质量边界](piano-performance-quality.md)和[验证与测试](testing.md)。
