# Practice Learning Loop P1 验收清单

本清单区分自动化证据与需要 macOS / Vision Pro 的设备证据。未执行项目不得标记为通过。

| 项目 | 当前状态 | 证据/说明 |
| --- | --- | --- |
| Swift 语法解析 | pass | Linux 环境对 P1 修改文件执行 `swiftc -parse`。 |
| P1 自动化测试 | blocked | 当前执行环境没有 Xcode、visionOS SDK 与 Simulator；必须在 macOS 运行完整 `HappyPianistAVPTests`。 |
| 八小节 MusicXML fixture | pass | XML 可解析；fixture 包含双手、速度、和弦与 repeat。Xcode test bundle membership 待 macOS 测试确认。 |
| Bravura 字体 | blocked | 仓库未包含 `Bravura.otf`；不得宣称最终谱面字形已验收。 |
| 本地 SoundFont | blocked | 仓库未包含 `SalC5Light2.sf2`；不得宣称本地 sampler 示范播放已验收。 |
| CoreML 即兴模型 | skipped | P1 不依赖模型；仓库未包含生产模型。 |
| 外部 MIDI 输入/输出 | skipped | 需要真实设备与 Vision Pro 验证。 |
| 麦克风多音和弦识别 | skipped | 当前仍为实验能力；三音及以上存在多数命中限制。 |
| paused resume 无自动发声 | code-reviewed | coordinator/session 测试已加入；需 Xcode 执行确认 note-on/play 调用为零。 |
| scene background / back flush | code-reviewed | `PracticeWindowRootView` 与统一 leave lifecycle 已接入；需窗口集成测试。 |

## macOS 验证命令

```bash
xcodebuild test \
  -project HappyPianist.xcodeproj \
  -scheme HappyPianistAVP \
  -destination "$AVP_DESTINATION" \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:HappyPianistAVPTests
```

## 真机验收

1. 导入许可明确的 MusicXML 曲目。
2. 选择片段、手别、速度、循环和连续成功次数。
3. 完成至少一个小节并返回曲库。
4. 关闭并重新打开 App，确认定位到原曲目和原片段，但保持暂停且不自动发声。
5. 进入后台、切换曲目和关闭窗口后，确认最后一次有效进度没有丢失。
