# HappyPianist

HappyPianist 是一个面向 Apple Vision Pro 的钢琴练习应用。它把 MusicXML 转成空间练习引导，并支持音频、蓝牙 MIDI 与虚拟钢琴三种输入方式。

![scene](docs/assets/scene1.jpg)

## 当前能力

- 批量导入 `.musicxml`、`.xml`、`.mxl` 曲谱，以原文件名同卷暂存并逐项建立曲库；同名冲突先停在确认边界，不会静默改名或覆盖。
- App 启动后直接进入曲库；左上角“选择钢琴”和“开始练习”分别通过单层 `pushWindow` 打开准备窗口与练习窗口，关闭后恢复原曲库状态。
- 记录小节级练习事实，恢复上次片段与位置。
- 将连续演奏对齐为按输入能力裁剪的客观 assessment，并展示一个可执行练习建议、非模态即时反馈、练习总结与小节恢复地图。
- 在沉浸空间显示键位高亮与轻量恢复效果。
- 记录结构化诊断事件，并允许用户导出最近七天的安全诊断日志。
- 练习中录制、回放并导出 MIDI take。
- AI 对弹提供用户选择后端的运行期创意响应（本地规则、本地 CoreML、可选 Mac Aria v2）；它不是原谱示范或评分基准，失败不会自动切换后端。

## 能力与验证边界

当前的乐谱回放、MIDI objective assessment、虚拟琴力度和练习建议都是已实现的练习能力，不是“钢琴家级示范”“专业评分”“表现力乐器”或“教师替代品”的通过声明。多 exporter 授权曲库、真机 latency/reliability、钢琴家盲评、教师标注与教学有效性证据尚未完成；对应能力保持 `pending evidence`，缺少合法 exporter 语料的项目为 `blocked evidence`。

完整的当前边界见[钢琴演奏与专业质量边界](docs/piano-performance-quality.md)，每项可升级措辞的条件见[钢琴能力声明证据门](docs/testing/piano-capability-claim-gates.md)。

## 资源状态

仓库已包含 `HappyPianistAVP/Resources/Fonts/Bravura.otf`。以下私有或体积较大的资源不随源码分发：

| 资源 | 影响 |
| --- | --- |
| `HappyPianistAVP/Resources/SeedScores/` | 没有内置生产曲目；依赖私有曲谱的资源集成测试会跳过。 |
| `SalC5Light2.sf2` | 本地 sampler 无法加载钢琴音色。 |
| `AIDuetPerformanceRNN.mlpackage` / `.mlmodelc` | 本地 CoreML 对弹不可用；仍可使用本地规则或网络后端。 |

将所需资源加入 `HappyPianistAVP` target 后再进行对应验收。测试跳过不等于资源集成通过。

## 致谢

- [Anticipation](https://github.com/jthickstun/anticipation) 与 [Anticipatory Music Transformer](https://arxiv.org/abs/2306.08620)
- [stanford-crfm/music-large-800k](https://huggingface.co/stanford-crfm/music-large-800k)
- Apple CoreMIDI、RealityKit、ARKit 与 Salamander Grand Piano 音色采样
- 感谢南客松 S2、`njuer勇闯互联网`、`罗恩`、`大宝哥` 对项目的支持

## 许可证

本项目基于 [AGPL-3.0](LICENSE.APGLv3) 开源。
