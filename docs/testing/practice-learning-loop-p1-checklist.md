# Practice Learning Loop P1 验收清单

本清单区分自动化证据与需要 macOS / Vision Pro 的设备证据。未执行项目不得标记为通过。

| 项目 | 当前状态 | 证据/说明 |
| --- | --- | --- |
| Swift 编译 | pass | Xcode 27.0、visionOS Simulator 26.4 完整 test build 通过。 |
| P1 自动化测试 | pass | `HappyPianistAVPTests` 共 519 项通过，0 失败、0 跳过。xcresult：`Test-HappyPianistAVP-2026.07.12_02-51-53-+0800.xcresult`。 |
| 八小节 MusicXML fixture | pass | fixture 已进入 test bundle；双手、速度、和弦、repeat 与选段回归测试通过。 |
| Bravura 字体 | available | 仓库包含 `HappyPianistAVP/Resources/Fonts/Bravura.otf`；真机字形观感仍按下方清单验收。 |
| 本地 SoundFont | available | 仓库包含 `HappyPianistAVP/Resources/SalC5Light2.sf2`；真机扬声器输出仍按下方清单验收。 |
| CoreML 即兴模型 | skipped | P1 不依赖模型；仓库未包含生产模型。 |
| 外部 MIDI 输入/输出 | skipped | 需要真实设备与 Vision Pro 验证。 |
| 麦克风多音和弦识别 | skipped | 当前仍为实验能力；三音及以上存在多数命中限制。 |
| paused resume 无自动发声 | pass | coordinator/session 回归测试确认恢复后保持暂停，note-on/play 调用为零。 |
| scene background / back flush | automated | lifecycle 与 flush 回归测试通过；直接关闭窗口的 UI 路径仍需真机手工确认。 |

## macOS 验证命令

```bash
rtk xcodebuild test \
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
