# 钢琴演奏证据索引

状态：`partial evidence`。本索引只汇总可复核的测试和协议状态，不保存原始曲谱、逐音 MIDI/音频/手部数据、参与者身份或密钥。专业能力的对外措辞仍由[钢琴能力声明证据门](piano-capability-claim-gates.md)决定。

## 已执行自动化证据

| 证据 | 代码基线 / 版本 | 实际运行 | 结果 | 可证明的范围 |
| --- | --- | --- | --- | --- |
| 完整 visionOS Simulator suite | `4ea2b844c959b16a85208c5f8f058274d5d9918e`（P15-T17 source/test baseline） | `xcodebuild test -project HappyPianist.xcodeproj -scheme HappyPianistAVP -destination 'platform=visionOS Simulator,id=86364D5F-BCCF-48C5-AF79-8154E5689FA3' CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO` | `passed`：2026-07-23 | Swift 6 类型检查和已接入的 Simulator 自动化；不证明真机、听感或教学效果。 |
| 专业 corpus manifest | `f1cc54f`，manifest v1 | `ProfessionalCorpusManifestTests` 由完整 suite 覆盖 | `passed`：2026-07-23 | fixture 登记、授权字段、重复与未登记文件检查。 |
| corpus score / performance snapshots | `902511c`、`2c2d842` | `ProfessionalCorpusScoreSnapshotTests`、`ProfessionalCorpusPerformanceSnapshotTests` 由完整 suite 覆盖 | `passed`：2026-07-23 | 已登记 fixture 的 source facts、event stream、range/seek/loop 与 app/CoreMIDI projection。 |
| observation confusion matrix | `379c163` | `PerformanceObservationConfusionMatrixTests` 由完整 suite 覆盖 | `passed`：2026-07-23 | MIDI、target audio 与 hand 的 capability/calibration 分层 replay；不代表真机准确率。 |
| Simulator 覆盖地图 | matrix v1 | [visionOS Simulator 钢琴演奏全链路矩阵](visionos-piano-performance-matrix.md) | `passed`：2026-07-23 | 准备、回放、输入、录制、alignment、assessment、coaching 与 AI 的自动化入口。 |

完整命令的实际退出状态必须保留在此表；测试文件存在、`build-for-testing` 或旧运行记录都不是当前通过证据。

## 未执行或受阻的证据

| 证据门 | 协议 / 依据 | 状态 | 不能替代它的证据 |
| --- | --- | --- | --- |
| MuseScore、Dorico、Sibelius、Finale 的可授权 fixture | `ProfessionalCorpus/manifest.json` v1 | `blocked evidence`：执行主机没有对应 exporter，也没有经确认的可再分发文件 | 内部 fixture、伪造 exporter provenance 或不明来源下载。 |
| Apple Vision Pro、音频路由、MIDI 与手部真实测量 | [硬件 latency、jitter 与可靠性协议](piano-hardware-latency-protocol.md) v1 | `pending evidence` | Simulator bucket、diagnostic 字段或校准配置。 |
| 钢琴家盲听与演奏评审 | [钢琴家盲听与演奏验证协议](pianist-blind-evaluation-protocol.md) v1 | `pending evidence` | 单个 demo、作者主观听感或测试事件相等性。 |
| assessment 与教师标注一致性 | [演奏 assessment 与教师标注一致性协议](performance-assessment-validity-protocol.md) v1 | `pending evidence` | 规则测试、总分或没有 unknown/insufficient 分层的结果。 |
| coaching 教学有效性 | [coaching 教学有效性协议](coaching-efficacy-protocol.md) v1 | `pending evidence` | 建议点击、accept/skip 或单次 remeasure。 |

## Claim-gate 汇总

| Gate | 当前状态 | 原因 |
| --- | --- | --- |
| CG-001 乐谱忠实示范 | `pending evidence` | 自动化可复核；多 exporter 合法 corpus 为 blocked，真机与盲评未执行。 |
| CG-002 MIDI 演奏评价 | `pending evidence` | replay 与规则自动化可复核；真实 MIDI 和独立教师标注未执行。 |
| CG-003 表现力虚拟琴 | `pending evidence` | 接触/输出自动化可复核；分设备真机测量与盲评未执行。 |
| CG-004 专业虚拟指导 | `pending evidence` | 单一动作与复测规则可复核；assessment validity 与教学有效性研究未执行。 |

## Closeout review

本轮以 CodeGraph 复查了 `PreparedPractice` → `ScorePerformancePlan` → playback consumers、三类平台 adapter → `PerformanceObservation` → analyzer/assessment/coaching，以及 `PracticeAttemptReducer` 的小节级持久化边界。未发现由 guide/step 重建声音、把系统播放混入用户 observation，或把 alignment/逐音 evidence/decision 写入 progress JSON 的残留路径。

该结论只覆盖静态调用关系和完整 Simulator suite；发现新的调用路径或证据状态变化时，先更新本索引与对应 gate，再改变产品措辞。
