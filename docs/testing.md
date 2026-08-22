# 验证与测试

本页说明每层测试能证明什么，以及如何记录不能由自动化替代的证据。能力措辞和 `pending` / `blocked` 定义以[质量边界](piano-performance-quality.md)为准。

## 日常命令

```bash
make doctor
make destinations
make build
make test
make build:mac
make test:mac
swift test --package-path Packages/HappyPianistCore
```

`make test` 会限制 Simulator boot（180 秒）、destination 查找（60 秒）和整次 action（900 秒），并开启单测试 timeout（默认 120 秒、最大 300 秒）。`make test:device` 与 `make test:mac` 也使用相同的 destination 和单测试 timeout。Simulator 超时会终止独立进程组，并把不含 app container 的诊断写至 `.build/TestResults`。受控异步测试必须使用有界等待（如 `TestAsyncWait`），不得使用无界 `Task.yield()` 轮询；需要调整时只覆盖相应 Make 变量，不得移除边界。

`make build:mac` 和 `make test:mac` 只使用 macOS scheme/destination/result bundle，不启动或读取 visionOS Simulator；`make clean` 会清理两个 App scheme。`build-for-testing`、语法检查或 Linux harness 都不能替代实际 `xcodebuild test`。

## 证据分层

| 层级 | 可证明 | 不能替代 |
| --- | --- | --- |
| Swift Testing / fixture | 纯模型、reducer、range、matcher、alignment、assessment、coaching | Apple 平台、硬件、听感、教学效果 |
| `xcodebuild test` / Simulator | Swift 6、target 集成、生命周期、资源协议、持久化 | 真机 latency、追踪精度、音频听感 |
| Apple Vision Pro 真机 | MIDI、麦克风、手部、audio route 的 latency/jitter/恢复 | 钢琴家审美、教学有效性 |
| 钢琴家盲评 | 回放 fidelity、voicing、pedal、articulation、style | 用户演奏评价正确性 |
| 教师标注 / coaching 研究 | assessment 一致性和指导前后改善 | 代码正确性、平台可靠性 |

每次实际运行记录 commit、Xcode、OS、destination、命令、退出结果、score/fixture revision 和适用的 calibration。跳过的私有 SoundFont、CoreML 或 SeedScores 资源测试不等于资源集成通过。

## 必须覆盖的自动化边界

- MusicXML parser 到 `PreparedPractice`、14 种标准 note type、缺失/非标准 type 的 typed failure，以及 measure spans；
- source/performed identity、range/loop、MIDI/音频输出 reset、generation、interruption 与无残留发声；
- observation 的 capability、unknown/insufficient、alignment、assessment、单一 coaching action；
- recording、session、progress 的 checkpoint、flush-before-teardown、恢复与持久化边界；
- AI 请求取消、乱序响应、generation 隔离与 teardown；
- macOS 选定 MIDI input 的断连行为、output flush、take 保存/导出及原生窗口退出 gate。

### 示范手纯值 Gate

`HandMotionCorpus/manifest.json` 覆盖音阶、琶音、密集和弦、重复音、大跳进、跨手和 pause/range 用例。`PianoHandMotionQualityTests` 对运行期同一纯值 clip builder 断言每个 fixture/occurrence 的 coverage、P95 接触残差不大于 5 mm、P95 时序误差不大于 50 ms、最大时序误差不大于 100 ms、单位四元数和无 collision 降级；builder 专属测试覆盖首击准备、held contact 与过渡约束。

这只验证程序化 skeleton，不能证明 Blender 网格真机接触、遮挡、舒适度或音画同步；缺资产时回退键面贴片必须仍可见。

## 手工与真机记录

日常 smoke 至少检查：导入/恢复和冲突、单一练习入口、range/tempo/loop、正确/错误/未知分流、切换或断开输入输出、stop/seek/后台/窗口关闭后的无残留发声、progress 脱敏、VoiceOver/Dynamic Type/Reduce Motion。

真机按独立设备、OS、route、score revision 与 calibration 记录 p50/p95/p99 latency/jitter、miss/false-positive/stuck-note、断连/中断/route change 恢复。无可靠同步、tracking 或 onset 的样本标 `insufficient`，不计为 miss；仅保存聚合桶与样本数，不保存原始 MIDI、音频、手部帧、序列号或绝对路径。

涉及专业表述时，使用已授权材料：钢琴家盲评在收样前冻结 rubric 并随机化 sample；教师标注至少两名独立盲标；coaching 研究冻结目标、before、action、完成条件、对照与练习剂量，并报告迁移和副作用。

## 证据状态与模板

| 证据 | 状态 | 不能替代 |
| --- | --- | --- |
| Simulator 自动化 suite、corpus manifest、score/performance snapshot、observation replay | `passed`：2026-08-09，`c1383e3` | 真机、听感、教师或教学证据 |
| 多 exporter 合法 fixture | `blocked evidence` | 内部 fixture、伪造 provenance、不明来源下载 |
| 真机硬件、钢琴家盲评、教师标注、coaching 研究 | `pending evidence` | Simulator bucket、诊断字段、点击次数或单个 demo |

```text
日期：YYYY-MM-DD
commit：
Xcode / OS / device 或 Simulator：
输入与输出 route：
fixture / score revision / calibration：
结果：Pass / Fail / Not Run / pending / blocked
失败步骤与复现：
证据位置：
```
