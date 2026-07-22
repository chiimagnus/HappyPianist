# 钢琴演奏专业化验证手册

本文定义钢琴演奏链路的证据层级。任何单一层级的通过都不能替代其他层级，也不能单独证明系统已经达到专业演奏、评价或教学质量。

## 证据层级

| 层级 | 验证对象 | 主要入口 | 能证明什么 | 不能替代什么 |
| --- | --- | --- | --- | --- |
| 确定性快照 | MusicXML 事实、演奏事件、来源与排序 | `MusicXMLScoreSnapshot`、`PerformanceEventSnapshot` | 同一输入产生稳定事实；字段没有静默丢失 | Swift 类型检查、平台集成、听感 |
| Fixture manifest | 回归语料来源、授权、导出器和覆盖语义 | `PianoPerformanceFixtureManifest.json` | 专业 fixture 可追踪且没有未登记文件 | 真实制谱软件 corpus 和授权复核 |
| 输入重放 | matcher、recording、alignment、assessment 和 coaching 生命周期 | `PerformanceInputReplaySupport`、alignment golden replay | occurrence、unknown/ambiguity、能力裁剪、target band、单一动作与复测在确定性事件序列下可重复 | MIDI、麦克风或手部真机时延与教师有效性 |
| visionOS 自动化 | App target、测试 target 和平台 API 集成 | `xcodebuild test` | Swift 6 类型检查与 Simulator 集成 | 真机硬件、音频听感和教学效果 |
| 真机测量 | MIDI、麦克风、手部、音频 transport | Apple Vision Pro + 真实钢琴/MIDI | 延迟、抖动、漏触发、资源恢复 | 钢琴家审美判断和教学有效性 |
| 钢琴家盲听 | 参考演奏的音乐可信度 | 预先定义的曲目与匿名样本 | 声部、力度、踏板、乐句与风格是否可信 | 用户演奏评价正确性 |
| 教学有效性 | 指导是否让演奏改善 | 前测、练习建议、后测 | 建议是否带来可重复的学习改善 | 代码正确性和平台可靠性 |

## 自动化入口

先列出可用 destination：

```bash
xcodebuild -showdestinations \
  -project HappyPianist.xcodeproj \
  -scheme HappyPianistAVP
```

随后选择实际 visionOS Simulator ID：

```bash
xcodebuild test \
  -project HappyPianist.xcodeproj \
  -scheme HappyPianistAVP \
  -destination 'platform=visionOS Simulator,id=<device-id>' \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO
```

`build-for-testing`、`swiftc -parse` 或 Linux 临时 harness 只能作为局部证据，不得记录成 `xcodebuild test` 已通过。

alignment/assessment/coaching 自动化至少要覆盖：score/occurrence identity、bounded window、missing/extra/unknown/ambiguous、输入 capability、target provenance、evidence check、单一动作排序、accept/skip，以及同 source generation 的下一轮 remeasure。测试只能证明规则实现一致，不能证明建议具有音乐或教学有效性。

仓库不提交 `HappyPianistAVP/Resources/SeedScores/` 和 Core ML 模型。依赖这些私有资源的集成测试在资源缺失时会跳过；资源存在时仍会执行，不能把跳过记录为资源集成已通过。

## 输出可靠性验收边界

Simulator 自动化使用统一 `FakePerformanceOutput` 捕获 timestamped batches、capabilities、generation、reset 与 AVAudio 状态，并注入 MIDI send、音频 operation/render 和 disconnect 故障。

Simulator 可以验收：

- timestamp 非零、批次顺序、look-ahead horizon、late clamp 与 generation guard；
- CC64/66/67 capability 量化、reset 顺序、重复 stop 幂等和 disconnect 后无旧 generation 事件；
- interruption、route change、media-services reset 的状态转换，以及 send/load/render 失败先 reset 再发布；
- scheduled/submitted/acknowledged 缺失语义、latency/jitter 分桶、dropped/cancelled 区分和七天隐私安全导出。

必须在 Apple Vision Pro 真机验收：

- [ ] 本地 sampler 实际 audio onset 的 p50 / p95 / p99 与和弦 onset spread；
- [ ] 指定 USB/Bluetooth MIDI 设备的实际接收时延、jitter、丢包与 endpoint 拔插恢复；
- [ ] 扬声器、耳机和目标音频路由的 interruption / route / media-services 恢复与卡音检查；
- [ ] 快速重复音、连续半踏板、长 sustain 和高密度和弦下的 CPU、漏触发与 stuck-note 结果；
- [ ] 每次结果记录设备、OS、路由、fixture ID、score revision、复现步骤和对应聚合诊断。

## Snapshot 规则

- 字段顺序、事件排序、数字精度和空值表示必须稳定。
- 不记录绝对路径、原始 MusicXML 正文、逐音传感器流或密钥。
- 已知错误写入 `PianoPerformanceKnownDeviations.json`，不得用错误输出建立永久“正确”快照。
- 新增 source identity、performed occurrence、controller 或 provenance 时扩展字段；不要改变既有排序原则来掩盖差异。

## Fixture 规则

每个专业 fixture 必须登记：

- 稳定 ID 与文件名；
- 来源和可用授权；
- 导出器或 `unknown`；
- 覆盖的音乐语义；
- 预期 snapshot 名称。

来自 MuseScore、Dorico、Sibelius、Finale 或其他来源的文件，在授权和来源尚未确认时应标记为 blocked，不得伪造 provenance。

### 合成手部触键轨迹

`SyntheticHandContactTraces.json` 以琴键 MIDI 编号和相对键面高度描述确定性输入，直接重放到正式触键检测与虚拟琴发声链路。它覆盖轻触、重击、慢压、同时和弦、重复音、手掌经过、tracking loss、左右手交叉和琴键范围外位置；自动化断言力度单调性、误触发、释放、重触发与 unknown 行为。

这些轨迹是人工构造的测试数据，不是真机录制，也不能证明真实手部追踪的精度或时延。修改 schema 或 calibration 时必须显式升级版本并同步 loader；禁止用缺省字段兼容旧 fixture。

## 真机证据最小记录

每次运行至少记录：

- 日期、Xcode、visionOS、设备型号和输入设备；
- 使用的曲目 fixture ID 与 score revision；
- event-to-audio、MIDI、手部和麦克风延迟统计；
- 同音重复、和弦 onset spread、踏板切换和停止后的卡音情况；
- 失败步骤、复现方法和对应诊断事件。

日志只保存低频计数、阶段、耗时桶和 capability；禁止导出原始曲谱、逐音 MIDI、音频、手部轨迹或绝对路径。

手部触键真机校准还必须：

- [ ] 从当前模式默认值开始，逐项记录键面偏移、释放滞回、最小/满量程击键速度、力度上下限、曲线指数和重复触键防抖；
- [ ] 用轻触、重击、慢压、同时和弦、同指重复音、手掌经过、tracking loss 和左右手交叉各运行至少一轮；
- [ ] 用同一外部时间基准记录 hand sample、note-on 与 audio onset 的聚合 p50 / p95 / p99，以及和弦 onset spread、漏触发和误触发计数；
- [ ] 只保存 calibration ID/version、设备/OS/模式和聚合桶；不得录制、持久化或导出逐帧 finger、palm 或 world position。

## 人工证据边界

钢琴家盲听和教学有效性实验必须使用预先写明的 rubric。参与者身份、样本顺序和预期答案不能泄露给评分者。人工证据只能补充自动化与真机证据，不能覆盖未通过的代码或平台验证。
