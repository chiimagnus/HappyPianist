# 可恢复练习验收清单

同步日期：2026-07-12。

本清单只接受针对同一源码快照执行的证据。2026-07-12 早期记录的 `519/519` Simulator 结果发生在后续冗余清理之前，不能作为清理后源码的最终 Gate。

## 自动化状态

| 项目 | 状态 | 说明 |
| --- | --- | --- |
| Swift 语法解析 | 可在非 Apple 环境执行 | 只能发现语法问题，不能替代 Xcode 类型检查。 |
| 完整 `HappyPianistAVPTests` | **需重新执行** | 必须在包含清理提交的源码上运行 `xcodebuild test`。 |
| 八小节 MusicXML fixture | 文件存在 | `HappyPianistAVPTests/Fixtures/PracticeLearningLoopEightMeasures.musicxml`；测试结果随完整 suite 一并确认。 |
| Bravura | **资源缺失** | `Info.plist` 有声明，但源码归档没有 `Bravura.otf`。 |
| SoundFont | **资源缺失** | 源码归档没有 `SalC5Light2.sf2`。 |
| CoreML 模型 | 不属于练习闭环 Gate | 源码归档没有 Performance RNN 模型。 |
| 外部 MIDI、麦克风与空间行为 | 需要真机 | Simulator 不能替代设备验收。 |

## Xcode 验证

先取得 destination：

```bash
xcodebuild -showdestinations \
  -project HappyPianist.xcodeproj \
  -scheme HappyPianistAVP
```

运行完整 suite：

```bash
xcodebuild test \
  -project HappyPianist.xcodeproj \
  -scheme HappyPianistAVP \
  -destination 'platform=visionOS Simulator,id=<device-id>' \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO
```

验收记录至少包含：

- 命令与退出码
- Xcode / visionOS Simulator 版本
- executed、failed、skipped 数量
- `.xcresult` 路径
- 对 flaky test 的单独重跑结果；不能只用第二次通过覆盖第一次失败

## 必须覆盖的自动化行为

- MusicXML parse、repeat/ending 展开与 source/occurrence identity
- 默认片段与选段 active range
- 单手、双手与空 expected-note 边界
- tempo scale、loop 和 required successes
- wrong note、missing notes、incomplete chord 与 insufficient evidence
- streak 隔离、stable 状态和 passage completion
- A/B 曲目乱序 load、换曲和 score revision
- 原子保存、损坏文件错误与删除曲目清理
- paused resume 不自动发声
- back、background、window close 与 session replacement 的 flush 顺序

## Vision Pro 验收

1. 将 `Bravura.otf` 与 `SalC5Light2.sf2` 实际加入 App target。
2. 导入许可明确的 MusicXML 曲目。
3. 分别使用音频、Bluetooth MIDI 与虚拟钢琴模式进入练习。
4. 选择片段、手别、速度、循环与连续成功目标。
5. 完成部分练习后返回曲库，确认摘要对应正确曲目和小节。
6. 重新进入并确认恢复到原片段和 step，但保持暂停且不发声。
7. 快速执行 inactive/active、换曲、关闭窗口和退出 immersive，确认进度不丢失、输入不残留、反馈不重现。
8. 验证谱面字体、sampler 音色、外部 MIDI、麦克风和空间键位对齐。

未执行的项目必须标记为 `Not Run` 或 `Skipped`，不得写成 Pass。
