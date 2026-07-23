# 钢琴能力声明证据门

Gate schema：`v1`。本文件把实现、自动化、Simulator、真机与人工研究分开记录；功能已存在、测试文件存在或协议已写好，都不能单独将能力标为 `passed`。

## 状态与证据绑定

- `pending evidence`：需要的测试、设备测量或人工研究尚未完成或尚未绑定实际 run record。
- `passed`：每一层所需证据均已按同一 app/score/rubric 或 calibration version 运行、复核并在 evidence index 留下聚合记录。
- `blocked evidence`：缺少合法语料、可用硬件、参与者授权或其他必要条件；阻塞项不允许绕过，也不等同失败实现。

每条证据记录必须绑定提交 SHA、fixture ID/score revision、测试或协议版本、设备/OS/route（适用时）、rubric 或 calibration version、日期和聚合结果。`unknown`、`degraded` 与 `insufficient` 必须保留，不能改写为错误或通过。

## CG-001：乐谱忠实示范

**需求范围：** `ARCH-001`、`SCORE-001` 至 `SCORE-014`、`PERF-001` 至 `PERF-007`。  
**当前允许措辞：** 已覆盖语义的、可审查且可重复的 MusicXML 驱动示范；不是钢琴家参考演奏或通用出版谱面。  
**Gate 状态：** `pending evidence`（多 exporter 授权语料目前另有 `blocked evidence`）。

| 证据层 | 绑定的文件 / 版本 | 当前状态 | 通过条件 |
| --- | --- | --- | --- |
| corpus 与 source facts | `PianoPerformanceFixtureManifest.json` v1、`ProfessionalCorpus/manifest.json` v1、`ProfessionalCorpusScoreSnapshotTests` | `blocked evidence` | 每个目标 exporter 有已授权 fixture，且 source facts、normalization、performed order 与 notation snapshots 经 review 通过。 |
| event 与输出等价性 | `ProfessionalCorpusPerformanceSnapshotTests`、`PerformanceEventSnapshot` | `pending evidence` | 同一 fixture 的 note/controller/tempo/pause/order/approximation，以及 app/CoreMIDI event stream 均有实际 run record。 |
| Simulator 集成 | `visionos-piano-performance-matrix.md`、完整 `xcodebuild test` | `pending evidence` | 对应提交的完整 Simulator run log 通过。 |
| 真机与听感 | `piano-hardware-latency-protocol.md` v1、`pianist-blind-evaluation-protocol.md` v1 | `pending evidence` | 指定音源、路由与曲目完成聚合 latency/reliability 和独立钢琴家盲评。 |

## CG-002：MIDI 演奏评价

**需求范围：** `ARCH-002`、`ARCH-003`、`OBS-001`、`OBS-002`、`OBS-009`、`ASSESS-001`、`ASSESS-004`、`ASSESS-005`。  
**当前允许措辞：** 对具备相应输入 capability 的 MIDI 演奏给出可追溯的客观指标；不是专业级评分或教师诊断。  
**Gate 状态：** `pending evidence`。

| 证据层 | 绑定的文件 / 版本 | 当前状态 | 通过条件 |
| --- | --- | --- | --- |
| rule 与 replay | `PerformanceAssessmentTests`、`PerformanceAlignmentTests`、`PerformanceObservationConfusionMatrixTests` | `pending evidence` | capability/calibration 分层 replay 的实际 run record 通过，且 unknown/insufficient 不计为错误。 |
| Simulator 生命周期 | `visionos-piano-performance-matrix.md` 的 MIDI、recording、alignment、assessment rows | `pending evidence` | 对应提交的完整 Simulator run log 通过。 |
| 真机 MIDI | `piano-hardware-latency-protocol.md` v1 | `pending evidence` | 指定 MIDI 设备的 timestamp、jitter、disconnect/recovery 和输入 capability 记录可复核。 |
| 教师有效性 | `performance-assessment-validity-protocol.md` v1、rubric `performance-assessment-v2` | `pending evidence` | 独立教师标注完成；按 pitch/timing/duration/dynamics/voicing/pedal 报告 agreement、precision、recall、correlation 和 unknown handling。 |

## CG-003：表现力虚拟琴

**需求范围：** `PERF-008` 至 `PERF-012`、`OBS-004` 至 `OBS-008`。  
**当前允许措辞：** 使用版本化校准把接触速度映射为独立 velocity，并保留能力边界；不是已经过真机验证的表现力乐器。  
**Gate 状态：** `pending evidence`。

| 证据层 | 绑定的文件 / 版本 | 当前状态 | 通过条件 |
| --- | --- | --- | --- |
| 接触与输出规则 | `VirtualPianoInputControllerTests`、`HandPianoActivityGateTests`、`PracticeSequencerPlaybackServiceProtocolTests` | `pending evidence` | 每音 velocity、release、重复音、和弦、pedal、stop/reset 的实际 run record 通过。 |
| Simulator 边界 | `visionos-piano-performance-matrix.md` 的 hand tracking、audio failure 与 playback rows | `pending evidence` | Simulator 只验证状态机、calibration version、unknown/insufficient 和恢复，且有完整 run log。 |
| 真机性能 | `piano-hardware-latency-protocol.md` v1、`PianoOutputMeasurementMetadata` | `pending evidence` | 分设备、OS、route、calibration 的 latency、jitter、chord spread、miss/false-positive、stuck-note 与 recovery 基线达到批准阈值。 |
| 钢琴家听感 | `pianist-blind-evaluation-protocol.md` v1 | `pending evidence` | 独立钢琴家对力度、声部、踏板、articulation 与可练习性完成匿名评审。 |

## CG-004：专业虚拟指导

**需求范围：** `ASSESS-003`、`GUIDE-001`、`GUIDE-002`、`GUIDE-003`。  
**当前允许措辞：** 基于可用证据选择一个有范围、来源与 completion condition 的练习动作；不是专业教师替代品。  
**Gate 状态：** `pending evidence`。

| 证据层 | 绑定的文件 / 版本 | 当前状态 | 通过条件 |
| --- | --- | --- | --- |
| 决策与复测规则 | `PracticeCoachingDecisionTests`、`PracticeLearningLoopIntegrationTests`、`CoachingDecisionService` | `pending evidence` | 单一动作、evidence check、accept/skip/remeasure 和 provenance 的实际 run record 通过。 |
| assessment 有效性 | `performance-assessment-validity-protocol.md` v1、rubric `performance-assessment-v2` | `pending evidence` | 触发指导的 assessment 已通过对应 CG-002 的教师标注 gate。 |
| 教学有效性 | `coaching-efficacy-protocol.md` v1 | `pending evidence` | 预登记的 before/action/dose/after/control/transfer/adverse-effect 研究完成并保留聚合结果。 |
| 钢琴家与教师审查 | `pianist-blind-evaluation-protocol.md` v1 | `pending evidence` | 独立评审确认动作可执行、边界恰当，且不把 insufficient 证据升级为确定性建议。 |

## 结论规则

四个 gate 都以最弱的必需层决定状态：任何 `pending evidence` 或 `blocked evidence` 都禁止升级对应产品措辞。实际 run log、硬件聚合指标和人工研究结果登记在[钢琴演奏证据索引](piano-performance-evidence-index.md)；其中自动化通过也不能覆盖未执行的真机、盲评或研究门。
