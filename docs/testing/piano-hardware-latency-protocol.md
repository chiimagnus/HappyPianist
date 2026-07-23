# 钢琴硬件 latency、jitter 与可靠性协议

状态：`pending evidence`。本协议定义采样和记录方式；没有实际 Apple Vision Pro、钢琴和路由运行记录时，不产生任何通过结论或阈值。

## 前置记录

每一轮先固定并记录：提交 SHA、日期、Apple Vision Pro 型号、visionOS/Xcode、真实钢琴与 MIDI 连接方式、音频输出路由、曲目 fixture ID 与 score revision。

记录当前校准而非只写“已校准”：calibration ID/version、键面偏移、释放滞回、最小/满量程击键速度、力度上下限、曲线指数和重复触键防抖。每项指标还要写样本数；不要把不同设备、OS、路由或 calibration version 合并为一个平均值。

`PianoOutputMeasurementMetadata` 只允许写入安全的聚合上下文：calibration ID/version、sample count、设备型号、OS 版本和枚举化 audio route。不得写设备序列号、用户命名的路由、绝对路径、原始 MIDI/音频/手部帧或 AI 正文。

## 测量矩阵

| 指标 | 起点与终点 | 最少观察 | 失败/恢复检查 |
| --- | --- | --- | --- |
| event-to-audio | 计划或 MIDI event 的 host time → 外部录音中的 audio onset | p50/p95/p99、样本数、和弦 onset spread | 漏触发、过晚 onset、停止后持续音 |
| hand-motion-to-audio | 同一外部时钟的 hand sample → audio onset | p50/p95/p99、有效/insufficient 样本数 | tracking loss 不得伪装为 miss |
| MIDI jitter | MIDI source timestamp/host time → 接收与提交时间 | p50/p95/p99、late、dropped、cancelled | USB/Bluetooth 各自统计，重连后无旧 generation |
| chord spread | 同一和弦各音 audio onset 的最大差 | 每种织体的分布与样本数 | 快速和弦、重复同音和高密度段落 |
| miss 与 stuck note | 预期 event、实际音频/MIDI 与 stop/reset | miss、false positive、reset 成功/失败 | 连续踏板、断连、interruption、route/media-services recovery |

## 执行

1. 从当前 calibration 开始，不静默改 knob；需要调整时新建 calibration version，并分开记录前后结果。
2. 每个设备/路由/fixture 先采集 baseline，再覆盖轻触、重击、快速重复、半踏板、长 sustain、和弦和 route recovery。
3. 对每项同时记录有效样本与 insufficient 样本；缺少同步、tracking 或可靠 onset 的样本不计入 miss。
4. 停止、断连、interruption、route change 与 media-services reset 后至少重新开始一次，记录恢复是否成功与是否有 stuck note。
5. 仅保存聚合指标和本页前置记录。原始观察数据不得进入进度 JSON 或可导出诊断。

## 阈值与结论

首次运行只建立 baseline，不预填“合格” latency、jitter、spread 或可靠性阈值。钢琴家与产品验收在查看分设备、分路由、分 calibration 的 baseline 后，才可为具体 capability gate 设阈值。一个设备上的结果不得推广到其他设备或路由。

记录模板：

```text
状态：pending / passed / blocked
设备、OS、路由：
钢琴/MIDI：
fixture ID / score revision：
calibration ID/version 与 knobs：
sample count / insufficient count：
event-to-audio、hand-to-audio、MIDI jitter、chord spread：
miss / false positive / stuck note / route recovery：
运行日志与证据位置：
```
