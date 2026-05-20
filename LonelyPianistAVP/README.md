# LonelyPianistAVP

这是 Apple Vision Pro 练习端。当前 app 使用 preparation、library、practice 三个窗口和一个沉浸空间，支持真实钢琴（音频识别）、真实钢琴（蓝牙 MIDI）和虚拟钢琴三种模式。

## 用户流程

1. 在 preparation window 选择钢琴类型。
2. 按所选模式完成准备：
   - 真实钢琴（音频）：完成 A0/C8 校准。
   - 真实钢琴（蓝牙 MIDI）：完成校准并连接 BLE MIDI source。
   - 虚拟钢琴：在沉浸空间内完成虚拟琴放置。
3. 进入 library window，选择 bundled 曲目或导入 MusicXML。
4. 进入 practice window，使用谱面、高亮、输入匹配、录制、回放和 AI 即兴功能。
