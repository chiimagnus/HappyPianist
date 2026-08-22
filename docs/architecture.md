# 架构

源码位置、符号和调用关系由 CodeGraph 提供；本页只记录依赖方向与跨模块不变量。

```text
SwiftUI / RealityKit → ViewModel / App state → Service / Repository → Model / Contract
```

- View 只渲染和发送 intent；ViewModel 编排状态与生命周期；副作用留在 Service/Repository；Model 保持纯数据和契约。
- `HappyPianistAVP` 是唯一 composition root 和 sandbox；AR/RealityKit、手部/虚拟琴、音频识别、AVFoundation 与 AI 都属于该 host。
- 共享包依赖向下：`Diagnostics` 与 `MusicXML` 是根；`MIDI` 只依赖 Diagnostics；`Practice` 依赖 MusicXML、MIDI、Diagnostics；`Notation` 依赖 Practice、MusicXML；`Library` 依赖 Practice、MusicXML、Diagnostics；`LibraryPresentation` 只依赖 `Library`，提供 AVP 使用的纯 SwiftUI 曲库表现。任何模块都不能反向引用 host UI 或 platform adapter。
- 新服务从稳定协议和 composition root 注入开始；单一实现不预建 factory、manager 或兼容层。

## 不变量

- MusicXML 是唯一正式曲谱来源；`PreparedPractice` 必须同时具有可演奏 steps 与 measure spans。
- `ScorePerformancePlan` 是声音事件唯一真源，steps、guides、notation 和 tempo 只能从它或 source score 单向投影。
- `PracticeStep` 仅用于即时判定；source measure 才是 progress 的持久化单位。occurrence identity 描述播放位置，source identity 聚合学习事实。
- alignment、逐音 evidence、target profile、`MusicalIssue`、coaching decision、手部骨骼和空间表现均为运行期数据。未知、低置信度、`insufficient` 或降级能力不是用户错误。
- AI/system playback、旧 generation 或后台事件不得进入用户 observation 或 progress；AI 严格使用用户选定后端，失败即停止本次生成。
- progress、metadata、session 在同一 JSON 文档中仍是独立 concern；诊断只经 `DiagnosticsReporting`，导出不含绝对路径、原谱、逐音输入、传感帧、AI 正文或凭据。
- 主 Actor 不做解析、文件 I/O 或设备重活；会话结束前依次失效输入、停止输入、flush 输出与 recorder、保存事实并取消长任务。

验证范围见[测试](testing.md)，产品能力措辞见[质量边界](piano-performance-quality.md)。
