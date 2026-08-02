# 数据流

本页只描述跨模块的事实流和生命周期。具体符号、文件位置与调用者用 CodeGraph 查询。

## 主流程

```text
MusicXML / MXL
  → 曲库事务与索引
  → PracticePreparationService
  → ScorePerformancePlan + measure spans
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
  → 同卷 stage + fingerprint + journal
  → SongLibraryIndexStore
  → SongLibraryEntryResolver
  → PracticePreparationService
```

- 支持 `.musicxml`、`.xml`、`.mxl`；正式练习来源不是 MIDI 或 AI 序列。
- 导入先写同卷 `.partial` 和 journal，再以字节数/SHA-256 校验后提交 target/index；冲突停在用户确认边界。
- bootstrap 先恢复未完成事务，再读取 index，最后扫描 bundle；损坏的非空 JSON fail closed，不得按空库覆盖。
- `PracticePreparationService` 先生成唯一 `ScorePerformancePlan`，再单向投影 `PracticeStep`、`PianoHighlightGuide`、notation projection、timeline 和 sequence。
- prepared result 必须同时有可演奏 steps 与 `MusicXMLMeasureSpan`；缺少小节结构时返回 typed failure，不建立 legacy fallback。
- preparation failure 的 UI、技术详情和诊断事件来自同一 typed failure；stale generation 不发布旧结果。

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
| Bluetooth MIDI | pitch、onset、release、velocity、controller、polyphony | hand、finger、姿势 |
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
  → FilePracticeProgressRepository actor
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
- 显式返回顺序：失效新 generation → 停止输入/输出 → flush progress → 终结 recorder → 关闭 immersive → 返回 Library。失败时留在当前窗口，不静默丢增量。

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
