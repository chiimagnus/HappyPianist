# AVP 练习音频：Step「下一步」短促音排查记录

本文记录一次真实排查：在 Step 手动模式下，**点击「下一步」会播放一个非常短促的声音**，但同一页面的「播放琴声 / 重播」按钮声音正常；按小节（measure）重播也基本正常。

## 现象（Symptom）

- 手动前进方式为 **逐步（step）** 时：
  - 点击 **「下一步」**：会听到一个“极短”的音（像被立刻掐断）。
  - 点击 **「播放琴声」**：声音正常（持续时间符合预期）。
- 手动前进方式为 **按小节（measure）** 时：
  - 点击 **「重播本节」**：整体听感正常（第一声问题另见 sequencer 预滚说明）。

## 根因（Root Cause）

**「下一步」按钮的代码路径比「播放琴声」多做了一次 stop，并且 stop 会发出 all-notes-off 类的“清音”指令。**

在 `PracticeSessionViewModel.skip()` 中，历史上为了“跳步时确保自动播放的音停掉”，会先调用：

- `stopAutoplayAudio()` → `sequencerPlaybackService.stop()`

而当前的 `AVAudioSequencerPracticePlaybackService.stop()` 会做：

- `sequencer.stop()`
- `allNotesOff()`（MIDI CC123: All Notes Off）
- `stopOneShotNotes()`

关键点在于：即使此时并没有在 autoplay / manual replay，**这套 stop 仍然会对 sampler 发出清音指令**。在某些时机下，这个清音指令会与紧接着的 `playCurrentStepSound()`（one-shot 的 `startNote`）发生竞态，导致刚开始的 note 被立刻 stop，于是听起来就“短促”。

这也解释了为什么同一模式下：

- **「播放琴声」正常**：它直接走 `playCurrentStepSound()`，不会先 stop 整个播放服务。
- **「下一步」异常**：它先 stop（清音），再进入下一步并触发播放，于是更容易被“清音尾巴”截断。

## 修复（Fix）

把 `skip()` 里的 `stopAutoplayAudio()` 限定在“确实有音频播放需要停止”的场景：

- 仅当 `autoplayState == .playing`（自动播放中）或 `isManualReplayPlaying == true`（小节重播中）时才 stop 音频。
- 在纯手动 step 前进（非 autoplay、非 manual replay）时不再调用 stop。

对应代码：

- `LonelyPianistAVP/ViewModels/PracticeSessionViewModel.swift`：`skip()` 中对 `stopAutoplayAudio()` 加 guard（条件调用）。

## 为什么日志看起来很吵（Debug Notes）

排查过程中出现大量：

- `audio service stopped`

这是 `PracticeSessionViewModel.stopAudioRecognition()` 的 debug log（音频识别服务 stop），在状态切换（autoplay / manual replay / 不满足 guiding 条件）时可能触发，**不等价于音频播放 stop**，容易造成误判。自 2026-04-29 起该日志只会在识别服务确实处于 running 时才打印，以降低噪声。

另一个常见噪声是 RemoteIO 相关错误（例如 `AURemoteIO ... -10851 ... 0 Hz`），这表示音频识别引擎启动失败（输入格式/会话状态异常等），可能导致识别侧反复启停，但与本次“下一步短促音”的最终根因不同。

## 经验总结（Takeaways）

- “跳步时先 stop 一下”这类保护逻辑要非常克制：**stop 往往不仅仅是停止 transport，还会隐含发送 all-notes-off / reset**。
- 当同一个声音在两个按钮上表现不同，优先对比两条路径里“额外的 stop / reset / 清音”步骤。

## 更新记录（Update Notes）
- 2026-04-29: 同步 `stopAudioRecognition()` 的日志降噪：只在 running→stopped 时记录 `audio service stopped`，避免把“识别服务 stop”误读为“播放 stop”。
