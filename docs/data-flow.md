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
- macOS 绑定或替换用户曲目的 mp3/m4a 时，同样只把 `fileImporter` URL 交给 `Library.AudioImportService`；它在 security scope 内复制到 `SongLibrary/audio/` 并只把相对文件名写入 index。旧的异步 URL 解析、选择变化或曲目删除后不得启动试听；删除先停止试听，再从 index、score、audio 和 progress 依次清理，后续清理失败只报告事实而不回滚已提交的 index mutation。
- macOS 从已选 Library entry 解析沙盒副本，经 `PracticePreparationService` 生成同时具备 steps 与 measure spans 的 `PreparedPractice`，再交给 `PracticeRoundSessionController`、`MIDIPracticeSession` 与 `GrandStaffNotationView`；controller 是 range、resume、attempt facts、assessment/coaching 与 feedback 的唯一 non-spatial owner，准备或 progress corruption 停在可恢复 UI，不建立 steps-without-measures fallback。
- `PracticePreparationService` 先生成唯一 `ScorePerformancePlan`，再单向投影 `PracticeStep`、`PianoHighlightGuide`、notation projection、timeline 和 sequence。
- 在 preparation 进入计划构建前，MusicXML 的每个普通 note/rest 必须有 14 项标准 `MusicXMLNoteType` 之一，非 grace note 还必须有显式 duration；不完整或非标准谱面以 typed failure 停止。整小节 rest 的无 type 例外由 `isMeasureRest` 语义字段决定，不能由字符串或 duration fallback 推断。
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
- 音符、休止符、flag 和 beam 的 14 项时值映射由 `MusicXMLNoteType` 单向提供；layout 使用 MusicXML 已解析的 3840 ticks/quarter 时间轴，不保存或重建原始 type token。
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
- macOS 通过 `PracticeRoundSessionController` 及其共享 `PracticeRoundConfigurationController` 应用 passage、hand、tempo、loop 和 required successes；应用时先失效旧 MIDI generation、停止旧输入，再从新 active range 的首步重建同一 visit。exact configuration/resume 直接恢复；无效状态按同一共享规则修复并写回，且不丢失已批准的小节 facts。macOS 不接入麦克风音频识别；没有 selected output 只隐藏回放，不阻断 MIDI 输入。

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

## 手部可视化

```text
HandTrackingProvider
  → ARTrackingService
  → HandSkeletonSnapshot current-value async stream
  → NeonHandOverlayController
  → fixed-capacity LowLevelMesh / fluorescent glove
```

- 手套只在 practice 的 `.mixed` `ImmersiveSpace` 自动显示；不进入 `.full`，也不隐藏系统手部，因此真实钢琴、双手和荧光半透明轮廓可同时可见。
- `ARTrackingService` 是唯一的真机骨骼来源；拒绝授权、不支持、停止或关节不完整时 controller 只隐藏对应手套。原始关节和派生 mesh 均不写入 progress、文件或诊断。
- Simulator 以条件编译的合成双手仅驱动 controller 渲染，供不佩戴设备时调整视觉效果；它绝不回灌 AR service、触键判定、练习 observation 或真机降级路径。真机的追踪精度、舒适度和实时表现仍需 Apple Vision Pro 验收。

## 示范手引导

```text
PianoKeyContactTimeline + PianoFingeringPlanner + PianoKeyboardGeometry
  → PianoDemonstrationHandTargetResolver (ready plan only)
  → PianoDemonstrationHandPoseResolver
  → PianoDemonstrationHandsOverlayController
  → packaged 21-joint left/right rigs
  → prepare / attack / rebound / hold joint transforms
```

- `pianoDemonstrationHandsEnabled` 默认 `false`，只保存展示偏好；设置页的开关即时改变沉浸空间，绝不写入 round configuration、progress 或 session JSON。
- 开启时按音符混合示范手与 `PianoGuideOverlayController` 键面贴片：只有 ready plan 中已可达且成功提交给 21 关节 rig 的音符会短暂抑制对应贴片；planning pending、无解、缺少几何或尚未加载资产的音符继续显示贴片。二维 `PianoKeyboard88View` 继续从同一个 guide 渲染高亮。
- 示范手只消费 ready plan 的手别和 1–5 指法；未知手别的 staff 1/2 归属仅存在于 planner 输入，渲染层不得重新分配或回写曲谱、plan 或手部分配。
- 自动播放把同一份 `AutoplayTimelineTimeSchedule`、transport generation 与采样时刻交给示范手；controller 按注入的 `PerformanceClock` 逐帧采样，按 `hand → occurrenceID` 保留每个音符自己的 onset、release 与进度。预备窗口取该 occurrence 的实际 pre-roll（最多 `0.45 s`），时刻由 note 的 source event 查得，因此 lead-in、pause、seek 与 loop 不会另走一套时间线。`RealityView.update` 只采样和应用既有 rig，不启动轮询或动画 task。
- `PracticePlaybackControlService` 在每个 transport generation 从该 timeline 与 schedule 建立 `PianoKeyContactTimeline`；它按 source event 的实际 event time 投影 occurrence 的 onset/release、score hand/staff、原始 fingering、guide、step 和 range-start carried-in 事实。缺少任一 on/off 的 occurrence 明确不可规划；示范手只消费这条线，绝不从 tempo map 重算秒数。
- `PracticeSessionViewModel` 是指法 planning 的唯一生命周期 owner：它把同一 contact 线和校准键盘快照交给 Core 的 off-main planner，并以 song、range、hand mode、tempo、geometry cacheID 与 transport generation 拒绝过期回写。未完成、取消或无解时不产生示范手 target，键面高亮保留；seek、loop、clear、shutdown 与 geometry 替换均先取消旧 task。
- 指法 ready 后，session 在同一 generation gate 下把纯值 snapshot 交给 off-main `PianoHandMotionClipBuilder`。`PianoHandMotionClip` 只包含键盘局部整手 transform、21 个 joint rotation、score/skeleton/generator metadata 与 occurrence coverage，结构上不允许 joint translation；未完成或过期 clip 不发布。P2-T4 的 candidate 尚未进入 controller，T8 才由唯一播放器替换 P1 的逐帧 pose 路径。
- pose resolver 在提交 rig 前核对每个 occurrence 的指尖残差；超过 `5 mm` 的是明确降级红线，标记为 `unreachable` 并交回键面贴片，绝不静默截断后继续抑制该键。可达目标仍保持 `< 0.0001 m` 的接触精度；`5 mm` 不是放宽后的精度目标。
- controller 不读 ARKit、不挂 `InputTargetComponent`/碰撞、不产生 observation。两手从 RealityKitContent 异步加载 Blender 生成的骨骼资产，渲染期只旋转既有 21 关节并移动整手 root，始终保留绑定姿态的局部平移与骨长；reset 会取消资产加载和击键动作并移除所有子实体，不回退到旧基础体手型。
- 手动练习没有未来 onset，示范手以 guide 出现时刻开始预备并记录一次未对齐时序诊断；它不声称与音频 onset 对齐。
- Reduce Motion 直接显示终态。Simulator 使用现有虚拟钢琴的 geometry 与 guide，所以能预览此渲染；真机仍需人工检查坐姿舒适度、键面接触、遮挡和视觉比例。

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
- MIDI-only 完成/返回顺序：失效输入 generation → 停止输入 → reset/flush 输出 → 等待已接受 observation 的 recorder 写入 → 完成 capability-aware assessment 与最多一个 coaching action → flush progress → 终结 session → 返回 Library。loop 也必须在 assessment/flush 后才开始下一轮；失败时留在当前窗口，不静默丢增量。

## 回放、录制与 AI

```text
ScorePerformancePlan
  → PerformanceRangeStateResolver
  → PerformanceTransportReducer
  → AutoplayPerformanceTimeline / PlaybackSequenceBuilder
  → AVAudioSequencer 或 CoreMIDI
```

- range、seek、loop、stop、interruption 和 route change 共享 reset 规则：逐 identity note-off、踏板归零、all-notes-off、all-sound-off。
- `Practice` 的 `RecordingTakeRecorder` 从 canonical observation 记录可重放事件；`TakePlaybackController` 用同一 transport generation 在取消后阻止过期 load/play。target audio 因缺少可靠逐音 release/velocity 不进入 MIDI take。
- visionOS 的 CoreMIDI 输入明确使用 `.allCurrentSources`；macOS 只启动用户选定的单个稳定 endpoint unique ID，设备枚举 index 和显示名不参与选择或持久化。所选输入断开即停止、递增 generation 并要求用户重新连接或重新选择，绝不回退到别的输入。
- macOS 输出是可选的 stable endpoint unique ID：缺失或断开只禁用回放，不影响输入判定。manual replay 以 `AutoplayPerformanceTimeline` 与 `PlaybackSequenceBuilder` 输出完整 active range，含 tempo、controller、边界 note-off 与 full reset；开始时关闭 attempt acceptance，取消/结束后按 generation 恢复。更换输出前先取消旧目标未来事件，并向全部通道发送 all-notes-off 与 all-sound-off 后释放旧输出；设备显示名和原始 MIDI 不写入设置或进度。
- macOS selected-input loss 先使 session 不再接受 observation，再经共享 session 完成 reset/flush、已接受 observation drain 与 approved measure facts flush；完成或明确返回后只恢复所选端点监测，不自动恢复练习。系统可见 endpoint 只能证明路由存在，wired/BLE、断连、输出 reset 与物理 loopback 仍需单独硬件证据。
- take 保留 source/capability/clock/calibration 事实；MIDI 7/14-bit 事件只在回放或导出边界生成。
- macOS take 只订阅 selected MIDI input 的 canonical observation；manual replay、take playback 和任何后续 AI output 都不会写入 take。显式退出、受控 route change、原生窗口关闭和应用退出共享唯一顺序：停止 input → full reset output → drain observation → 原子写入 take → flush progress → finalize session；take/progress 任一写入失败就取消离开并保留 pending data 供重试。导出 URL 只在用户 action 中交给系统 document exporter，不进入持久化或诊断。
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
- exportable event 的自由文本在写入 JSONL 前经过统一隐私闸门；绝对路径、曲谱 XML、逐音 MIDI/observation、AI response、认证标记、换行原文或超长内容会替换为 `[redacted]`，system log 不会反向成为 archive 来源。
- 禁止写入绝对路径、MusicXML 正文、逐音 MIDI/音频/手部数据、设备序列号、路由显示名、AI prompt/正文、密钥或认证信息。
- 日志默认保留七个日历日；导出由用户触发，不自动上传。
- `Diagnostics` 是独立 Swift package 的根产品；其 archive 使用 ZIPFoundation，但 App target 不直接链接 ZIPFoundation。
