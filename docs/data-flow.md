# 数据流

本页只描述跨模块的事实流和生命周期。具体符号、文件位置与调用者用 CodeGraph 查询。

## 主流程

```text
MusicXML / MXL
  → 曲库事务与索引
  → PracticePreparationService
  → ScorePerformancePlan + measure spans
  → Notation renderer projection
  → practice session
  → typed observation / playback
  → assessment / coaching
  → measure facts / session facts
```

## 曲库导入与准备

```text
fileImporter
  → SongLibraryViewModel intent
  → SongLibraryImportTransactionService actor
  → MusicXML import safety validation
  → 同卷 stage + fingerprint + journal
  → SongLibraryIndexStore
  → SongLibraryEntryResolver
  → PracticePreparationService
```

- 支持 `.musicxml`、`.xml`、`.mxl`；正式练习来源不是 MIDI 或 AI 序列。
- preparation 读取 MusicXML/MXL 时，先校验常规文件；MXL 在解包前及实际 extraction 前都校验 entry 数、单 entry/总声明解压大小、压缩比和 archive 相对路径，任一拒绝不产生部分 score。
- 导入在 security scope 内拒绝非普通文件、symlink、超出大小限制或 unsafe MXL central directory；仅通过 MusicXML 公开验证后才写同卷 `.partial` 和 journal，再以字节数/SHA-256 校验后提交 target/index；冲突停在用户确认边界。
- bootstrap 先恢复未完成事务，再读取 index，最后扫描 bundle；损坏的非空 JSON fail closed，不得按空库覆盖。
- macOS host 使用同一 transaction actor：`fileImporter` 提供的 security-scoped URL 只在 `stageImports` 内获取和释放，成功后只保留 sandbox `SongLibrary` 内的副本、相对文件名与 fingerprint；不保存外部 URL、bookmark 或绝对路径，也不尝试读取 visionOS container。
- macOS 从已选 Library entry 解析沙盒副本，经 `PracticePreparationService` 生成同时具备 steps 与 measure spans 的 `PreparedPractice`，再交给 `MIDIPracticeSession`、小节事实 reducer 与 `GrandStaffNotationView`；准备或 progress corruption 停在可恢复 UI，不建立 steps-without-measures fallback。
- `PracticePreparationService` 先生成唯一 `ScorePerformancePlan`，再单向投影 `PracticeStep`、`PianoHighlightGuide`、notation projection、timeline 和 sequence。
- `Practice` 是 preparation 与共享 runtime 的包边界，依赖 `MusicXML`、`MIDI` 和 `Diagnostics`；曲库、SwiftUI/RealityKit、AVAudio、音频识别与手部/虚拟琴不得被它反向引用。
- prepared result 必须同时有可演奏 steps 与 `MusicXMLMeasureSpan`；缺少小节结构时返回 typed failure，不建立 legacy fallback。
- preparation failure 的 UI、技术详情和诊断事件来自同一 typed failure；stale generation 不发布旧结果。

## 记谱渲染

```text
ScoreNotationProjection + overlay + measure spans + hand mode
  → Notation layout / accessibility descriptor
  → Canvas renderer + VoiceOver overlay
```

- `Notation` 只消费 Practice/MusicXML 的事实；session 仅提供当前 context 与 transient overlay，不能把导航、progress 或 AR guide 传入 renderer。
- 记谱高亮、Dynamic Type、Differentiate Without Color 和 VoiceOver 描述是派生表现，不写入 progress。

## 练习启动与本轮配置

```text
Library selection
  → PracticeLaunch request
  → exact song UUID + entry token + revision restore
  → preparation/apply
  → ready
  → immutable active configuration
  → PracticeActiveRange
```

- Library 只登记 request；practice window 激活 request 后才解析曲谱、恢复 progress 和进入 immersive flow。
- exact revision 可恢复 passage、resume 和 measure facts；旧 revision 只继承手别、速度、循环和 required successes。
- active configuration 在一轮中不可变；pending 设置只影响下一轮。
- active range 同时约束 step 导航、谱面 viewport、琴键高亮、autoplay、manual replay 和完成边界。
- 恢复后停在 ready/paused，不自动发声；无效 passage/resume 回退到当前曲谱整首并 checkpoint。

## 输入、对齐与指导

```text
MIDI / target audio / hand contact
  → PerformanceObservation
  → matcher / recording / AI phrase
  → PracticePerformanceAnalyzer
  → alignment
  → capability-aware assessment
  → MusicalIssue
  → one CoachingAction
```

| 输入 | 能提供的证据 | 明确不能推导 |
| --- | --- | --- |
| CoreMIDI 输入 | pitch、onset、release、velocity、controller、polyphony | hand、finger、姿势 |
| 定向麦克风 | 目标音集合、有限 onset/confidence | 逐音 release、velocity、复杂复调、完整踏板 |
| 手部接触 | 键位、onset/release、hand/finger、位置、估算 velocity | 未经真机验证的精确力度、姿势质量、踏板 |

- observation 携带 source、capability、generation、单调时钟、channel/group、confidence 和 calibration reference。
- system playback、AI 输出、旧 generation、paused/suspended 和非 guiding 状态不生成用户 attempt。
- unknown、ambiguous、insufficient 和 degraded 保留原状态；不能用默认零分或相邻半音容差填补。
- alignment、逐音证据、target、issue、decision 和 before/after 只存在运行期；只有批准的小节聚合进入 progress。
- coaching 每次最多选择一个有范围、来源和 completion condition 的 action；点击或 accept 不代表改善。

## 进度与会话

```text
typed attempt
  → PracticeAttemptReducer
  → source-measure fact
  → PracticeProgressCoordinator
  → Library.FilePracticeProgressRepository actor
  → progress-v1.json
```

```text
Practice window visit
  → PracticeSessionRecorder actor
  → checkpoint / flush
  → session fact
```

- `PracticeStep` 是即时判定单位；source measure 是持久化学习单位。
- progress、score metadata 和 sessions 是同一 JSON schema 内的独立数组；每次 mutation 读取磁盘最新版本，只改自己的 concern。
- progress 保存当前配置、resume point、小节 maturity/metric summaries 和必要 session facts；不保存 cue、summary、map、RealityKit entity、逐音 evidence、原始输入或 AI 内容。
- `PracticeSessionRecorder` 以 Practice window visit 复用；首次真实进入 guiding 才创建 session。scene、guiding、settings、round、退出边界立即 checkpoint，连续 guiding 最多每 30 秒一次。
- MIDI-only 显式返回顺序：失效输入 generation → 停止输入 → reset/flush 输出 → 等待已接受 observation 的 recorder 写入 → flush progress → 终结 session → 关闭 immersive → 返回 Library。失败时留在当前窗口，不静默丢增量。

## 回放、录制与 AI

```text
ScorePerformancePlan
  → PerformanceRangeStateResolver
  → PerformanceTransportReducer
  → AutoplayPerformanceTimeline / PlaybackSequenceBuilder
  → AVAudioSequencer 或 CoreMIDI
```

- range、seek、loop、stop、interruption 和 route change 共享 reset 规则：逐 identity note-off、踏板归零、all-notes-off、all-sound-off。
- `RecordingTakeRecorder` 从 canonical observation 记录可重放事件；target audio 因缺少可靠逐音 release/velocity 不进入 MIDI take。
- visionOS 的 CoreMIDI 输入明确使用 `.allCurrentSources`；macOS 只启动用户选定的单个稳定 endpoint unique ID，设备枚举 index 和显示名不参与选择或持久化。所选输入断开即停止、递增 generation 并要求用户重新连接或重新选择，绝不回退到别的输入。
- macOS 输出是可选的 stable endpoint unique ID：缺失或断开只禁用回放/参考，不影响输入判定。更换输出前先取消旧目标未来事件，并向全部通道发送 all-notes-off 与 all-sound-off 后释放旧输出；设备显示名和原始 MIDI 不写入设置或进度。
- macOS selected-input loss 先使 session 不再接受 observation，再经共享 session 完成 reset/flush、已接受 observation drain 与 approved measure facts flush；完成或明确返回后只恢复所选端点监测，不自动恢复练习。系统可见 endpoint 只能证明路由存在，wired/BLE、断连、输出 reset 与物理 loopback 仍需单独硬件证据。
- take 保留 source/capability/clock/calibration 事实；MIDI 7/14-bit 事件只在回放或导出边界生成。
- AI phrase 只来自用户 observation；用户选择的 backend 失败、超时、invalid response 或 quality gate failure 时停止本次生成，不自动 fallback。
- `CreativeDuetResponse` 只在运行期存在，不改写 score plan、assessment target 或 progress。

## 诊断与隐私

```text
typed domain failure / aggregate output metric
  → DiagnosticEvent
  → Diagnostics.AppDiagnosticsReporter
  → os.Logger
  → exportable JSONL（仅低频安全事件）
```

- 业务代码不直接调用 `os.Logger` 或文件 store；统一入口决定事件是否可导出。
- 可导出事件只能包含枚举、阶段、计数、耗时桶、capability、calibration ID/version、设备/OS 和枚举 route。
- 禁止写入绝对路径、MusicXML 正文、逐音 MIDI/音频/手部数据、设备序列号、路由显示名、AI prompt/正文、密钥或认证信息。
- 日志默认保留七个日历日；导出由用户触发，不自动上传。
- `Diagnostics` 是独立 Swift package 的根产品；其 archive 使用 ZIPFoundation，但 App target 不直接链接 ZIPFoundation。
