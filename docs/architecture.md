# 架构

源码位置、符号和调用关系由 CodeGraph 提供；本页只记录依赖方向与跨模块不变量。

```text
SwiftUI / RealityKit → ViewModel / App state → Service / Repository → Model / Contract
```

- View 只渲染和发送 intent；ViewModel 编排状态与生命周期；副作用留在 Service/Repository；Model 保持纯数据和契约。
- `HappyPianistAVP` 是唯一 composition root 和 sandbox；AR/RealityKit、手部/虚拟琴、音频识别、AVFoundation 与 AI 都属于该 host。
- 共享包只沿依赖方向组合，任何模块都不能反向引用 host UI 或 platform adapter；精确 package graph 由 CodeGraph 提供。
- 新服务从稳定协议和 composition root 注入开始；单一实现不预建 factory、manager 或兼容层。

## 不变量

- MusicXML 是唯一正式曲谱来源；`PreparedPractice` 必须同时具备可演奏 steps 与 measure spans，`ScorePerformancePlan` 再单向投影声音与表现。
- `PracticeStep` 只做即时判定；source measure 才持久化学习事实。alignment、逐音证据、coaching、手部和空间表现始终留在运行期。
- 未知、低置信度、`insufficient` 与降级能力不是用户错误；AI/system playback、旧 generation 或后台事件不能写入用户 observation 或 progress。
- progress、metadata 与 session 分 concern 更新；诊断只经 `DiagnosticsReporting`，导出不得含原谱、原始输入、绝对路径、AI 正文或凭据。
- 主 Actor 不做解析、文件 I/O 或设备重活；结束会话前失效输入、停止输入和输出、保存事实并取消长任务。

验证范围见[测试](testing.md)，产品能力措辞见[质量边界](piano-performance-quality.md)。
