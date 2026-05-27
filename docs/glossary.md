# Glossary

| 术语 | 含义 |
| --- | --- |
| recorder | macOS app 的核心功能：监听 MIDI、录制 take、导入 MIDI、回放。 |
| take | 一段录制或导入的 MIDI note 序列。macOS 与 AVP 都有 take 概念，但存储实现不同。 |
| `RecordingTake` | 录制 take 的领域模型。macOS 与 AVP 各自有模型文件。 |
| `PianoModeProtocol` | AVP 钢琴模式接口，定义准备路由、readiness、练习追踪模式与录制来源标签。 |
| real audio mode | AVP 真实钢琴（音频识别）模式。需要校准与麦克风输入。 |
| Bluetooth MIDI mode | AVP 真实钢琴（蓝牙 MIDI）模式。需要校准和至少一个 MIDI source。 |
| virtual piano mode | AVP 虚拟钢琴模式。需要完成 3D 键盘放置。 |
| `PracticeSetupState` | AVP 准备阶段状态：钢琴类型、校准、虚拟琴放置、BLE MIDI source 数量、导入曲谱。 |
| `WindowTransitionState` | AVP 三窗口切换状态，替代旧式 flow-state 文档模型。 |
| `PreparedPractice` | MusicXML 经准备管线产出的练习输入，包含 steps、timelines、guide、notation 相关数据。 |
| `PracticeStep` | 练习中的一个推进单位，包含 expected notes 与左右手语义。 |
| guide | 空间高亮与谱面渲染所需的按键/音符提示数据。 |
| grand staff | 双谱表显示模型，用于 AVP practice window。 |
| autoplay | AVP 自动演奏功能，由 `PracticePlaybackControlService` 与 timeline 相关服务协调。 |
| phrase | AI 即兴使用的短片段输入，通常从练习录制或 clip selector 得到。 |
| MIDI 1.0 / MIDI 2.0 | CoreMIDI 输入协议。AVP BLE MIDI 同时支持两类 event stream。 |
| MusicXML | AVP 曲库导入的乐谱格式。当前 Info.plist 声明 `.musicxml` / `.xml`。 |
| SoundFont | AVP sampler 回放所需音色文件。压缩包未包含 `SalC5Light2.sf2`。 |
