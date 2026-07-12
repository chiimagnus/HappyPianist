# 术语

| 术语 | 含义 |
| --- | --- |
| `PianoModeProtocol` | 钢琴模式接口，定义准备 route、readiness、追踪模式与录制来源文案。 |
| real audio mode | 真实钢琴麦克风识别模式；需要 A0/C8 校准。 |
| Bluetooth MIDI mode | 真实钢琴蓝牙 MIDI 模式；需要校准和至少一个 CoreMIDI source。 |
| virtual piano mode | 空间虚拟钢琴模式；需要完成平面选择和键盘放置。 |
| `PracticeSetupState` | 准备阶段的钢琴模式、校准、MIDI source 与虚拟琴状态。 |
| `WindowTransitionState` | preparation、library、practice 三窗口的切换状态。 |
| `PreparedPractice` | MusicXML preparation 的完整产物：identity、steps、小节、timelines、guide 与谱面输入。 |
| source measure | 原谱小节身份，是持久化学习事实的聚合单位。 |
| occurrence | repeat/ending 展开后的播放位置，可多次指向同一个 source measure。 |
| `PracticeStep` | 即时练习判定和导航单位。 |
| active range | 当前片段在小节、step、tick、谱面与回放中的统一范围。 |
| pending configuration | 下一轮待应用的手别、速度、循环、成功目标和片段。 |
| active configuration | 当前轮不可变的练习配置。 |
| attempt outcome | matcher 产生的 typed 结果，如 matched、wrong note、missing notes、incomplete chord。 |
| measure fact | 小节级成功、失败、streak 与稳定状态的持久化事实。 |
| hotspot | 从当前片段事实中确定的一个主要卡点。 |
| restoration map | 从小节事实派生的未开始、练习中、稳定状态图。 |
| take | 练习中录制的一段 MIDI 风格事件序列，可回放和导出。 |
| guide | 空间琴键高亮与谱面定位使用的数据。 |
| autoplay | 按 MusicXML tempo、pedal、fermata 与片段范围自动回放。 |
| Local rule backend | 内嵌在 AVP target 的确定性 AI 即兴后端。 |
| CoreML backend | 需要 Performance RNN 模型文件的本地即兴后端。 |
| Aria v2 | Mac 侧可选网络即兴后端，通过 Bonjour + HTTP/WS 连接。 |
| SoundFont | AVP sampler 使用的 `.sf2` 音色文件；源码归档不包含 `SalC5Light2.sf2`。 |
