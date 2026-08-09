# 验证与测试

这是唯一测试知识入口。代码结构和测试符号用 CodeGraph 查询；本页只记录如何运行、每层能证明什么、人工/真机证据如何绑定，以及日常 smoke 检查。

## 证据层级

| 层级 | 能证明什么 | 不能替代 |
| --- | --- | --- |
| Swift Testing / fixture | Model、reducer、range、matcher、alignment、assessment、coaching 的确定性规则 | Apple 平台、硬件、听感、教学效果 |
| `xcodebuild test` / Simulator | Swift 6 类型检查、App target 集成、生命周期、reset、资源协议和持久化边界 | 真机 latency、手部精度、音频听感 |
| Vision Pro 真机 | MIDI、麦克风、手部、音频 route 的 latency、jitter、漏触发和恢复 | 钢琴家审美与教学有效性 |
| 钢琴家盲评 | 参考回放的 fidelity、voicing、pedal、articulation、style plausibility | 用户演奏评价正确性 |
| 教师标注 / coaching 研究 | assessment 一致性和指导动作的 before/after 改善 | 代码正确性与平台可靠性 |

任何单层通过都不能升级产品能力措辞。能力声明的当前允许表述和 `pending` / `blocked` 语义见[质量边界](piano-performance-quality.md)。

## 自动化运行

日常入口：

```bash
make doctor
make destinations
make build
make test
```

macOS host 使用完全独立的入口：

```bash
make build:mac
make test:mac
```

它们只使用 `HappyPianistMac`、`platform=macOS` 和自己的 result bundle；不读取 `SIMULATOR_ID`，也不 boot visionOS Simulator。共享包仍单独运行 `swift test --package-path Packages/HappyPianistCore`，visionOS 仍使用 `make build` 与 `make test`。

MusicXML fixture 必须为每个普通 note/rest 提供标准 `<type>` 和非 grace 的显式 `<duration>`；package tests 覆盖 14 个标准 type 从 parser 到 `PreparedPractice` 和 notation layout、1024 分音符的 15-tick 精度、0–8 层 beam，以及缺失/非标准 type 的 typed failure。无 type 只在语义整小节 rest fixture 中合法。

需要完整运行日志时：

```bash
xcodebuild -showdestinations \
  -project HappyPianist.xcodeproj \
  -scheme HappyPianistAVP

xcodebuild test \
  -project HappyPianist.xcodeproj \
  -scheme HappyPianistAVP \
  -destination 'platform=visionOS Simulator,id=<device-id>' \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO
```

macOS MIDI host 的确定性覆盖使用：

```bash
rtk xcodebuild test \
  -project HappyPianist.xcodeproj \
  -scheme HappyPianistMac \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:HappyPianistMacTests/MIDISettingsViewModelTests \
  CODE_SIGNING_ALLOWED=NO
```

它覆盖持久化只含 unique ID、所选输入断开后停止且不回退、输出切换的 flush/reset/stop 顺序；`HappyPianistMacTests/MacPracticeViewModelTests` 还覆盖 fixed-score MIDI match/wrong evidence、measure facts reload、passage/hand/tempo/loop 的 exact restore、invalid repair 与 selected-input loss；`HappyPianistMacTests/MacRecordingWorkflowTests` 覆盖 take 的 open-note close、return/input-loss/save-failure 重试、CRUD、export、no-output 与 stale playback reset；`HappyPianistMacTests/MacPracticeExitGuardTests` 覆盖原生窗口关闭与应用退出必须先经过异步 finish gate；`HappyPianistMacTests/MacDiagnosticsViewModelTests` 验证诊断 export/clear 和 archive 隐私脱敏。仍需在真实设备上确认所选输出未通过 MIDI-Thru 或 loopback 回灌到所选输入。

记录提交 SHA、Xcode、visionOS、destination、命令和完整退出结果。`build-for-testing`、`swiftc -parse` 或 Linux harness 只能作为局部证据，不是 `xcodebuild test` 通过证据。

Simulator 至少覆盖：

| 链路 | 可验证边界 |
| --- | --- |
| MusicXML、playback、range | source/performed identity、事件顺序、范围重建、loop、app/CoreMIDI projection |
| MIDI、音频输出、reset | timestamp、generation、controller、失败恢复、interruption、route change、无残留发声 |
| 手部输入 | contact 生命周期、calibration version、tracking loss、unknown/insufficient、重复触键 |
| recording、session、progress | checkpoint、generation、恢复、flush-before-teardown、持久化边界 |
| alignment、assessment、coaching | occurrence、missing/extra/ambiguous、能力分层、证据状态、单一动作、复测 |
| AI 生命周期 | 取消、乱序响应、generation 隔离、teardown |

Simulator 不证明真实 MIDI、麦克风、手部追踪、audio onset、route recovery 或钢琴听感。

### 教师手纯值质量 Gate

`HappyPianistTestFixtures/Resources/Fixtures/HandMotionCorpus/manifest.json` 固定音阶、琶音、密集和弦、重复音、大跳进、跨手与 pause/range 时间孔。`PianoHandMotionQualityTests` 通过 session 在运行期同样使用的唯一纯值 clip builder 断言每个 fixture/occurrence 的完整 coverage、P95 接触残差 ≤ 5 mm、P95 时序误差 ≤ 50 ms、最大时序误差 ≤ 100 ms、单位四元数与无 collision 降级；失败信息必须包含 fixture 和 occurrence。clip/session cancellation 与 player generation 继续由对应 session/player 回归测试覆盖。

这只是程序化 skeleton 的确定性 Gate，不证明 Blender 网格在真机的实际接触、遮挡、舒适度或音画同步；这些仍按下方真机协议记录为独立证据。

资源缺失时，依赖 `SeedScores/`、`SalC5Light2.sf2` 或 CoreML 模型的测试可以跳过；跳过不等于资源集成通过。

## 日常 smoke checklist

### 曲库与准备

- [ ] App 启动进入 Library；曲目、作曲家、来源和 selection 一致。
- [ ] 切曲停止旧试听，不并播；批量导入 `.musicxml`、`.xml`、`.mxl` 后重启仍存在。
- [ ] 同名冲突停在确认边界，不静默覆盖或改名；删除只影响对应 score/audio/progress。
- [ ] 损坏 index、导入取消、缺失 audio 和事务恢复有明确状态，不按空库覆盖。
- [ ] setup 未完成时不能开始练习；准备失败有 typed 状态、重试和返回。

### 练习与恢复

- [ ] preparation / practice pushed window 关闭后回到 Library；快速点击只创建一个 request/session。
- [ ] exact revision 恢复 passage、手别、速度、循环、required successes 和 resume step。
- [ ] 旧 revision 只继承允许的偏好；无效 passage/resume 回退整首并 checkpoint。
- [ ] 右手、左手、双手、有限 range、tempo、loop 都停在 active range 内。
- [ ] correct、wrong、missing、incomplete、unknown 分开；完成摘要最多一个 action。
- [ ] accept、skip、remeasure 不直接增加 progress 成功数；自动播放和 AI 不算用户输入。

### 输入、输出与生命周期

- [ ] MIDI 首音、和弦、velocity、release、controller、timestamp、generation 正确。
- [ ] macOS 仅启动所选输入；断开后不自动切换或恢复，需用户显式重新选择；切换输出后无残留发声，且输出 loopback 不回灌到输入。
- [ ] 麦克风无声、错音、权限拒绝、切换模式和旧结果不会推进新 step。
- [ ] 手部保留 hand/finger identity；palm、tracking loss、低置信度、calibration 变化不误触发。
- [ ] stop、seek、loop、interruption、route change、断连和重启后无 stuck note 或旧输出。
- [ ] 后台、窗口关闭、退出 immersive、切曲和 session replacement 取消长任务并释放输入。
- [ ] 返回前等待 progress flush 和 session finalization；失败时留在当前窗口。

### macOS MIDI 硬件（`pending evidence`）

每一项记录 commit、日期、macOS/Xcode、route 类型与结果；不记录设备显示名、序列号、绝对路径或原始 MIDI。

- [ ] 连接一个 wired MIDI endpoint，选定该输入并完成首音、和弦、release、controller 与 timestamp 检查。
- [ ] 通过系统设置配对一个 BLE MIDI endpoint，再选定它完成同样检查；App 不扫描或配对设备。
- [ ] 在 guiding 中断开所选输入并重新连接：确认立即停止、无自动 fallback 或自动恢复，随后由用户手动重新选择。
- [ ] 选定输出后切换或断开它：确认 flush、all-notes-off、all-sound-off 后无残留发声；无输出时输入判定仍可完成。
- [ ] 负向测试 MIDI-Thru/软件 loopback：在受控测试中确认回灌会成为输入事件后立即停止该配置，并在真实练习前物理断开。软件不声称能识别物理回灌。

### 存储与体验

- [ ] progress 只含小节聚合、配置、metadata、session facts；不含 cue、summary、逐音 evidence、AI 或原始传感数据。
- [ ] macOS take 可开始/停止、重命名、删除、清空、回放、seek 和用户触发的 MIDI 导出；无 output 时浏览/编辑/导出仍可用，只有发声 control 禁用。
- [ ] take 可回放/导出；target audio 不进入逐音 MIDI take，return、route change 或 input loss 会在 progress 前先关闭 open note 并写入 take，写入失败可重试且不离开当前 route。
- [ ] Library Ornament 只读展示事实，没有第二个练习入口或隐藏配置。
- [ ] Reduce Motion、VoiceOver、Dynamic Type、Differentiate Without Color 和增强对比度下主流程可完成。

## 真机硬件协议

每轮绑定 commit、日期、Apple Vision Pro、visionOS/Xcode、钢琴/MIDI 连接、audio route、fixture、score revision 和 calibration ID/version。不同设备、OS、route、calibration 不合并平均。

至少测量：

- event-to-audio、hand-motion-to-audio、MIDI jitter、chord onset spread 的 p50/p95/p99；
- miss、false positive、stuck note、断连、interruption、route change、media-services reset 后的恢复；
- 轻触、重击、快速重复、半踏板、长 sustain、和弦和高密度段落。

缺少同步、tracking 或可靠 onset 的样本标为 `insufficient`，不计为 miss。只保存聚合桶、样本数、设备/OS、枚举 route 和 calibration ID/version；不得保存原始 MIDI、音频、手部帧、序列号或绝对路径。首次运行建立 baseline，不预填通用合格阈值。

## 人工与研究协议

### 钢琴家盲评

使用已授权、可追溯的 score fixture 或录音片段；协调人随机化 sample ID 和顺序，评分者看不到模式、预期结论或参与者身份。rubric 在收样前冻结，至少按 fidelity、timing、voicing、pedal、articulation、style plausibility、可练习性分维度评分；缺音频、版本或条件不可确认时标 `insufficient`。

### Assessment 与教师标注

每轮冻结 score/plan、输入 capability、calibration、设备、rubric、target provenance；至少两位教师独立盲标。按 pitch、timing、duration、dynamics、voicing、pedal 报告 agreement、precision、recall、correlation 以及有效/`unknown`/`insufficient` 样本数。规则 replay 不能替代独立标注。

### Coaching 有效性

研究前冻结目标范围、before assessment、action、completion condition、对照和练习剂量。必须比较 before/after、对照、实际剂量、完整段落迁移和副作用；点击、接受、跳过或单次 remeasure 不等于改善。研究记录只用匿名 ID 和聚合结果。

## Evidence index

证据记录状态：

- `pending evidence`：必要证据尚未完成或没有实际 run record；
- `passed`：所有必要层按同一 app/score/rubric 或 calibration version 完成并复核；
- `blocked evidence`：缺少合法语料、硬件、授权或其他必要条件，不等同实现失败。

当前摘要：

| 证据 | 状态 | 不能替代它的东西 |
| --- | --- | --- |
| Simulator 自动化 suite、corpus manifest、score/performance snapshot、observation replay | `passed`：2026-07-23 | 真机、听感、教师或教学证据 |
| 多 exporter 合法 fixture | `blocked evidence` | 内部 fixture、伪造 provenance、不明来源下载 |
| 真机硬件、钢琴家盲评、教师标注、coaching 研究 | `pending evidence` | Simulator bucket、诊断字段、点击次数或单个 demo |

四项能力门 `CG-001` 至 `CG-004` 的措辞和所需证据以[质量边界](piano-performance-quality.md)为准；本页只记录验证方法和证据状态。

## 记录模板

```text
日期：YYYY-MM-DD
commit：
Xcode / visionOS / device / Simulator：
输入与输出 route：
fixture / score revision / calibration：
结果：Pass / Fail / Not Run / pending / blocked
失败步骤与复现：
证据位置：
```
