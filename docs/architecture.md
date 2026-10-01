# 架构

源码位置、符号和调用关系由 CodeGraph 提供；本页只记录依赖方向与跨模块不变量。

```text
SwiftUI / RealityKit → ViewModel / App state → Service / Repository → Model / Contract
```

- View 只渲染和发送 intent；ViewModel 编排状态与生命周期；副作用留在 Service/Repository；Model 保持纯数据和契约。
- `HappyPianistAVP` 是唯一 composition root 和 sandbox；AR/RealityKit、手部/虚拟琴、音频识别、AVFoundation 与 AI 都属于该 host。
- 共享包只沿依赖方向组合，任何模块都不能反向引用 host UI 或 platform adapter；精确 package graph 由 CodeGraph 提供。
- 新服务从稳定协议和 composition root 注入开始；单一实现不预建 factory、manager 或兼容层。

## 沉浸空间与 AR 生命周期

- App 只有一个 `.mixed` `ImmersiveSpace`。`AppState.immersiveMode` 是 `.library / .calibration / .practice` 的唯一产品模式事实；`ImmersiveSpacePresentationCoordinator` 只串行化 open/dismiss 请求，不复制业务状态。
- `ImmersiveView.onAppear/onDisappear` 经 `ARGuideViewModel` 是 mounted `open/closed` 的唯一写入链。普通 mode 切换不会等待新的 scene lifecycle，而是立即退出旧 mode runtime、进入新 mode runtime。
- `.library` 只需要 world tracking。Calibration/Practice 按需增加 hand/plane；`ARTrackingService` 在普通 mode 切换中保留同一 `ARKitSession + WorldTrackingProvider`，只增量重配可选 provider。
- `ARKitSession.events` 与 provider 自身 `state` 是运行状态事实源；`.paused` 与 `.stopped` 不合并。手/平面不可用时清除对应瞬时投影，world 暂停不更换 generation。
- `worldTrackingGeneration` 只在完整 runtime/world provider 重建时递增。沉浸运行时 suspend、显式 stop、world stop/error 或 `session.run` 失败会完整失效当前 runtime；普通 hand/plane 增删不会清空 world anchor cache。
- Spatial Library 根节点只保存 session-scoped `world transform + worldTrackingGeneration`：首次进入时从 device pose 取 yaw 定位并保持 world-fixed；普通 mode 切换复用，同一 ImmersiveSpace suspend/关闭或 generation 变化立即失效。它不是持久化 WorldAnchor。

## 不变量

- MusicXML 是唯一正式曲谱来源；`PreparedPractice` 必须同时具备可演奏 steps 与 measure spans，`ScorePerformancePlan` 再单向投影声音与表现。
- `PracticeStep` 只做即时判定；source measure 才持久化学习事实。alignment、逐音证据、coaching、手部和空间表现始终留在运行期。
- 未知、低置信度、`insufficient` 与降级能力不是用户错误；AI/system playback、旧 generation 或后台事件不能写入用户 observation 或 progress。
- progress、metadata 与 session 分 concern 更新；诊断只经 `DiagnosticsReporting`，导出不得含原谱、原始输入、绝对路径、AI 正文或凭据。
- 主 Actor 不做解析、文件 I/O 或设备重活；结束会话前失效输入、停止输入和输出、保存事实并取消长任务。
- 实时陪伴决策通过 CompanionDecisionBackendProtocol 注入；RuleBasedCompanionDecisionBackend 是默认基线，电脑端 Qwen3.5 是唯一实验型网络实现。Qwen Companion service 是四语义、A/B 消偏和 `semantic-v1` mapping 的唯一网络 runtime owner；Swift 只发送严格 compact state 并接收最终 CompanionAction。播放生命周期由 DuetAIPlaybackQueue 唯一维护为 `idle / preparing / playing`：只有 `playing` 算 Companion active；用户输入只淘汰未开始的旧窗口，`listen` 清 future、`yield` 才停止当前播放，`support / sparse / respond` 保留当前播放。所有 `.yield` 必须满足真实 playback active 且 playback start 后出现新的用户 note-on。生成窗口、请求节奏与 token 数仍由 DuetPhrasePolicy 负责。Aria 网络生成只有 Bonjour + HTTP `/generate`；协议 v3 请求只包含 note、真实 CC64 与 `max_tokens`，discovery+HTTP 共用 350ms 完整-response deadline，server 以 single-flight `busy` 拒绝积压。旧 WebSocket 分块、旧协议兼容与 provider fallback 都不保留。音乐生成与陪伴决策分别选择，任一后端失败都不得静默切换实现。

验证范围见[测试](testing.md)，产品能力措辞见[质量边界](piano-performance-quality.md)。
