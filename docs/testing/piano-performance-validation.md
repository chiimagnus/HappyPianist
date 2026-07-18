# 钢琴演奏专业化验证手册

本文定义钢琴演奏链路的证据层级。任何单一层级的通过都不能替代其他层级，也不能单独证明系统已经达到专业演奏、评价或教学质量。

## 证据层级

| 层级 | 验证对象 | 主要入口 | 能证明什么 | 不能替代什么 |
| --- | --- | --- | --- | --- |
| 确定性快照 | MusicXML 事实、演奏事件、来源与排序 | `MusicXMLScoreSnapshot`、`PerformanceEventSnapshot` | 同一输入产生稳定事实；字段没有静默丢失 | Swift 类型检查、平台集成、听感 |
| Fixture manifest | 回归语料来源、授权、导出器和覆盖语义 | `PianoPerformanceFixtureManifest.json` | 专业 fixture 可追踪且没有未登记文件 | 真实制谱软件 corpus 和授权复核 |
| 输入重放 | matcher、recording 和时钟逻辑 | `PerformanceInputReplaySupport` | 算法在确定性事件序列下可重复 | MIDI、麦克风或手部真机时延 |
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

## 真机证据最小记录

每次运行至少记录：

- 日期、Xcode、visionOS、设备型号和输入设备；
- 使用的曲目 fixture ID 与 score revision；
- event-to-audio、MIDI、手部和麦克风延迟统计；
- 同音重复、和弦 onset spread、踏板切换和停止后的卡音情况；
- 失败步骤、复现方法和对应诊断事件。

日志只保存低频计数、阶段、耗时桶和 capability；禁止导出原始曲谱、逐音 MIDI、音频、手部轨迹或绝对路径。

## 人工证据边界

钢琴家盲听和教学有效性实验必须使用预先写明的 rubric。参与者身份、样本顺序和预期答案不能泄露给评分者。人工证据只能补充自动化与真机证据，不能覆盖未通过的代码或平台验证。
