# Book Flow 与双页空间乐谱

## 目标

本 feature 现在负责从 **Book Flow / Book Spread 基础** 一路推进到 **Reality-first Spatial Library + Spatial Practice**，而不是停在普通 Window 中。

## 正式视觉验收参考

本 feature 的正式产品原型是以下 **8 张设计稿**：

1. `.github/features/spatial-2026-09-30/设计稿/images/01-Book-Flow曲库.png`
2. `.github/features/spatial-2026-09-30/设计稿/images/02-双页Book-Spread曲目详情.png`
3. `.github/features/spatial-2026-09-30/设计稿/images/03-现实钢琴-MIDI准备.png`
4. `.github/features/spatial-2026-09-30/设计稿/images/04-正常练习.png`
5. `.github/features/spatial-2026-09-30/设计稿/images/05-Companion教学.png`
6. `.github/features/spatial-2026-09-30/设计稿/images/06-Companion陪弹.png`
7. `.github/features/spatial-2026-09-30/设计稿/images/07-实时反馈与空间控制.png`
8. `.github/features/spatial-2026-09-30/设计稿/images/08-练习结果与重练.png`

同时遵守：
- `.github/features/spatial-2026-09-30/设计稿/视觉契约.md`

这 8 张图是**产品结构、空间关系、信息层级和视觉语言的验收参考**，不是逐像素复刻任务。

不要复制图中的：
- 固定房间；
- 固定钢琴型号；
- 特定家具/灯光；
- 示意性的曲名、封面、具体音符；
- AI 生成图可能存在的透视或文字瑕疵。

现实环境继续来自 passthrough；谱面来自用户 MusicXML；钢琴来自用户真实乐器；封面只使用真实已知数据。

完整目标分成两层，但都属于本 feature：

1. **P1–P3：把“书架和书”本身做好**
   - Book Flow；
   - 真正多 system 的双页 Book Spread；
   - Library / Practice 共用分页；
   - 手动 / 自动翻页。

2. **P4–P6：把它们真正放进用户现实空间**
   - Spatial Book Flow world-lock；
   - Book Spread 从曲库迁移到现实钢琴上方；
   - Guide、唯一 Companion Hands、反馈和高频控制整合成 Reality-first Practice。

原型与实现关系：

| 设计稿 | 对应实现 |
| --- | --- |
| **01 Book Flow 曲库** | P1 建立 Book Flow；P4 变成真正 world-fixed 的 Spatial Book Flow |
| **02 双页 Book Spread / 曲目详情** | P2 完成真正多 system 双页谱和练习状态；P3 翻页；P4 放进现实空间 |
| **03 现实钢琴 / MIDI 准备** | 复用现有 A0/C8、WorldAnchor、Bluetooth MIDI 准备链；P5 消费同一 KeyboardFrame，不重做校准 |
| **04 正常练习** | P2/P3 提供双页谱；P5 定位到现实钢琴；P6 与 Guide / Companion / feedback / controls 完整集成 |
| **05 Companion 教学** | P6 统一 Companion Hands，并让 Demonstrate 使用同一双空间手 |
| **06 Companion 陪弹** | P6 将 listen / support / sparse / respond / yield 映射到同一双 Companion Hands，并与真实播放时钟同步 |
| **07 实时反馈与空间控制** | P6 把即时反馈和高频 Practice 操作迁到钢琴/乐谱周边的空间 UI |
| **08 练习结果与重练** | P2 提供谱面上的 stable/learning/resume/focus 数据表达；P6 收口结果、重点小节、重练与返回曲库的 Reality-first 流程 |

最终主流程应成为：

```text
辅助 Library Window
  ↓
Spatial Book Flow
  ↓ confirm
Spatial Book Spread
  ↓ start practice / existing setup when needed
Keyboard-relative Spatial Book Spread
  +
Piano Guide
  +
one Companion Hands pair
  +
spatial feedback / controls
  ↓
finish / save
  ↓
return to Spatial Library
```

普通 Window 仍可保留导入、诊断、复杂设置、录音库等工具职责，但不再作为核心选曲和核心练习界面。

---

# 1. 执行前源码审查结论

## 1.0 本轮独立复核（2026-09-30）

不读取、引用或覆盖已有 `audit*.md`。本节是计划复核，不是已实现 phase 的验收。

**当前规划边界：** 用户现已明确要求把 P4–P6 直接纳入同一个 feature；todo 共 24 tasks。本轮仍然只是 `$writing-plan`：P1–P6 的需求、源码落点、任务拆分和清理归属已被补全，但这不等于任何 phase 已实现，也不等于创建了执行审计。空间扩展中特别确认了 `PreparationWindowRootView.finishSetup()` 与 `PracticeWindowRootView.activateCurrentRequest()` 当前都会关闭 ImmersiveSpace，因此 P5-T3 已明确要求在有效 spatial launch 下改成共享 `.library → .calibration → .practice` mode handoff，而不是只修改新 SceneController。

范围：全仓代码索引与引用定位；完整追踪本 feature 的 App/Library 入口、selection/import/delete/audition/history、resolver/preparation、projection/spacing/engraving/renderer、Practice 安装/范围/导航/autoplay 和现有对应测试。空间扩展阶段进一步追踪了唯一 mixed `ImmersiveSpace`、`ImmersiveView/RealityView`、ARTracking device/world pose、A0/C8 / KeyboardFrame、Real Audio / Bluetooth MIDI readiness、Piano Guide、NeonHand、Demonstration Hands、VirtualPerformer/Xiaocheng、CompanionDecision 与 AI playback queue，以及 Practice Window 的保存/返回生命周期。结合根目录与 AVP 的 AGENTS、Package/Xcode/Makefile、README、`docs/overview.md`、`docs/architecture.md`、`docs/data-flow.md`、`docs/storage.md`、`docs/testing.md` 和上述视觉契约。未声称逐行读完与本 feature 无调用关系的 provider、Python 后端或全仓所有源码；这些路径不应被顺手修改。

### 发现的问题与计划修正

| 风险 | 当前证据 / 原计划缺口 | 修正归属 |
| --- | --- | --- |
| 高：阶段孤立 / 删除后无法构建 | P1-T1 新呈现到 T2 才挂载；原 P2-T2/T3 新分页/Spread 到 T4/T5 才接入，T3 却先删旧 View 仍用的居中成员 | P1-T1 当场接入；P2-T2 改为有停止条件的几何验证，不遗留生产 helper；P2-T3 交付分页、渲染及 Practice 接入并立即清旧；T5 专注生命周期回归 |
| 高：练习范围改变页码 | `PracticeSessionViewModel.notationMeasureSpans` 返回 `activeRange.measureSpans`，而不是完整谱面 | P2-T3 用完整 `session.measureSpans`；范围仅影响 overlay/navigation |
| 高：双声部页首谱号错误 | normalizer 只建立 `logicalInstrument` 映射；原始 timeline 保留各 part 的 staff=1，projection 才映射成显示谱表 1/2；session 没保留 `scoreContext` | P2-T1 当场经 apply/install 传递最小 part/staff 输入；T3 逐 system 解 context，不从首个音符猜 |
| 高：上下谱表记谱事实合并 | `GrandStaffNotationContext` 只有一份 key/meter；timeline 可按 part/staff 区分 | T3 每谱表解析 key/meter；同 tick 页首 attribute 只画一次，音高/调号位置使用相同上下文 |
| 高：小节边界与页首碰撞 | spacing 有独立 barline/attribute/rhythm 字典；旧 makeBarlineTicks 去掉第一个起点；固定 header=7 staff-spaces 容不下大调号/拍号 | T1 保留真实边界/元素 extents；T3 header 与 system packing 同一测量，不用节奏位置插值估算尾部休止小节 |
| 高：断行后标记消失 / 重复 | onset 半开区间不能同时适用于前一小节末尾的 repeat/ending stop；ending renderer 只由 start 起画；beam 模型未区分 source/fallback 来源 | T1 保留 source provenance；T3 结构边界归属与 continuation 专项测试 |
| 高：高度或窗口缩放导致裁剪 | 旧 canvas 高度没有完整 rests/tuplets 输入，固定 beam 上留白；8…22 像素 clamp 与整页等比缩放冲突；Practice 至少 350 高并不证明双页可读 | T2 验证可读性、超宽/超高边界；T3 同一 canonical ink bounds 决定排页和渲染，移除旧像素 clamp/无效参数 |
| 高：休止 / 长延音错页 | 当前高亮 guide 可停留在旧 tick；现有 time cursor 仅返回 step/guide 且不覆盖所有小节起点 | T3 用同一 transport schedule 的离散位置，包括小节边界；不以 guide 优先、不加第二 clock |
| 高：同歌换谱 / 关闭后旧预览回写 | resolver 只按 songID 返回最新条目；import 替换文件后才提交新 version；SongLibraryView.onDisappear 会停止试听、取消导入 | T4 prepare 前核对 resolved fileVersion；导入事务期间取消并关闭 preview；外层 Library 宿主不因 detail 切换消失；关闭/失活取消并清理 |
| 中：摘要与谱面状态对不齐 | aggregate 不是逐小节事实；metadata 缺失或不同 revision 不能当“未练习”；overlay 无小节几何 API | T4 单次 snapshot 派生、核对 revision、最小中性 measure annotation（含休止小节 bounds），不写 progress JSON |
| 中：卡顿 / Swift 6 隔离 | 当前 makePresentation 每次全谱重做；现有部分 layout/context 非 Sendable | T1 单一 owner 非主 Actor 建一次绝对布局、可取消且只留当前值；T3 建一次 page plan；overlay 不触发全谱计算 |
| 中：深色模式 / 无障碍回退 | renderer 使用 `.primary`，新象牙纸面可能白字白底；descriptor 先遍历 notes 再 rests，非时序；翻页双面可重复暴露 VoiceOver | T3 纸面墨色与时序排序；P3-T1 当场处理 Reduce Motion 与动画层 a11y，T4 是验收而非补基础能力 |
| 高：旧 ImmersiveSpace workaround 被错误继承 | `.inTransition` + 最多 40 次 `Task.yield()` + recursive retry / force-closed 只是在修补旧状态机；所有 Calibration/VirtualPiano/Practice caller 都依赖它 | P4-T1 用一个共享 in-flight scene task + 真实 open/dismiss/scene lifecycle facts 替换；删除 `.inTransition`、`recoverIfStuck` 和旧 caller plumbing |
| 高：同一 ImmersiveSpace mode 切换后不仅 AR provider 不更新，mode-specific runtime 也不会自动迁移 | 当前 tracking reconcile 只在 immersive appear/resume；同一 scene 的 `.library → .calibration → .practice` 不会再次触发 `ImmersiveView.onAppear/onDisappear`，所以 Calibration polling/capture、Practice localization、Virtual Piano guidance 等也可能残留或根本不启动 | P4-T1 每次 mode change 走一个明确 oldMode→newMode runtime hook：先退出旧 mode-owned tasks，再 reconcile `ARTrackingRequirements`/hand/plane，进入新 mode-owned lifecycle；不等不存在的下一次 onAppear |
| 高：requirements 变化会重建整个 ARKit runtime，Spatial Library 世界坐标失去连续依据 | 当前 `ARTrackingService.start` 在 `.world → .world+hand` 也 stop 整个 session/new Runtime；但 Library/Calibration/Practice 都持续需要 world tracking | P4-T1 改成同一 ARKitSession 的增量 provider reconcile：保留同一个 WorldTrackingProvider，按需替换 stopped hand/plane provider；full stop/failure 才重建 world runtime |
| 高：AR provider 真实运行态会与手写状态漂移 | 当前不消费 `ARKitSession.events`，`.running/.stopped` 只在本服务调用 run/stop 时手写；系统运行中 pause/stop/error 后可能仍被当成 running | P4-T1 建唯一 session-event task；新增 `.paused`，以真实 provider event/authorization 纠正状态；unexpected stop 不允许 `start` 误 early-return |
| 高：裸 world transform 缺少 runtime identity | `worldFromSpatialLibrary` 若跨 WorldTrackingProvider replacement 复用，会指向失效坐标语义 | P4-T1 暴露 `worldTrackingGeneration`；P4-T2 placement 保存 transform+generation，generation 变化必须 fresh re-place；P5/P6 禁止飞回旧 transform |
| 高：ARTrackingServiceProtocol 泄露测试/内部状态 | `activeRequirements`、`authorizationStatusByType` 没有生产 consumer，只迫使 fake 实现内部细节 | P4-T1 从 protocol 删除；service 私有维护 desired requirements / authorization；保留真正业务需要的 provider states、world support、anchors/snapshots、`worldTrackingGeneration` |
| 高：Spatial Book Flow 大曲库不可浏览 / attachments 无界 | 原计划每 song 一个 Attachment，却只描述 5–7 本可见；没有第 8+ 本的空间浏览操作 | P4-T3 只实例化 selected±3 可见 slice；off-center confirm + 单一 targeted horizontal drag 更新既有 selection |
| 高：空曲库会打开一个没有内容的 ImmersiveSpace | Window 有正式 empty/import 状态，但 Spatial Library 计划曾默认至少一首曲子 | P4-T3/T4：entries 为空时不允许打开空间曲库、不造 fake folio；已打开后删到 0 首则通过共享 coordinator 关闭并回辅助导入 UI |
| 高：Spatial score 物理尺寸可能被多层 magic scale 控制 | P2 只有 canonical page 尺寸，P4 Attachment/P5 placement 都可能各自再缩放 | P4-T3 建唯一 `SpatialBookDisplayMetrics`/等价纯值，Attachment 边界统一 point→meter scale；P5 handoff 只改位置、不改尺寸，用户 scale 只有真机证明需要才在 P5-T4 增加 |
| 高：Window Book Flow 删除后 imported-song delete 能力丢失 | 当前删除入口绑定 drag/hold carousel；辅助 Window 没独立管理入口 | P4-T4 迁移为普通 destructive management action + 系统确认，复用 `SongLibraryViewModel.deleteEntry()`；同 task 删除旧 drag/hold policy/tests |
| 高：Window 收口时可能顺带删掉 local-audio binding | `SongLibraryView` 还承载没有 audioFileName 曲目的本地音频 fileImporter + `bindAudio` | P4-T4 明确保留为辅助管理能力；只移除核心浏览，不删除音频绑定/import 业务路径 |
| 高：Library 按钮可能绕过活跃 Practice/Preparation | shared coordinator 允许 mode switch，但直接 `.practice/.calibration → .library` 会跳过 save/cancel/return | P4-T1 Library summon 复用现有 launch/return/setup lifecycle facts；活跃流程只能走正式 finish/cancel/return，不加影子 active flag |
| 高：校准方向未知却被伪装成 resolved，并且下游还有兼容猜测 | `resolveRuntimeCalibrationFromTrackedAnchors()` 在无法判断 player/interior side / frame 退化时会写 `frontEdgeToKeyCenterLocalZ = 0` 后仍返回 `.resolved`；`PianoCalibration.init` 默认也是 0；`PianoKeyGeometryService` 再把 0 静默解释为 `+Z` | P5-T1 改成 typed recoverable `playerSideAmbiguous`，统一校验水平 A0→C8 frame 不变量；删掉 calibration 的 zero default 与 geometry 的 zero→+Z fallback，更新所有 fixture/caller，不留兼容 initializer |
| 中：score placement preference 过度持久化 | 原 P5-T2 为 X/Y/Z UI 偏好新建 Documents JSON/quarantine/recovery | P5-T2 按 AGENTS 改用 UserDefaults，小型 concrete store，无 protocol/factory/quarantine/recovery UI |
| 高：空间 Start Practice 与旧 Window 入口双轨 | P5 新增 score-attached start，但旧 `SongLibraryView` 按钮/onStartPractice/pushWindow 仍存在 | P5-T3 空间 start 复用 `SongLibraryViewModel.startPractice` gate，同时删除旧 Window 启动链，不留 2D/spatial feature flag |
| 高：空间开始练习若再造 pending coordinator 会形成双 launch 状态机 | `PracticeLaunchViewModel` 已拥有 `requestedSongID + state + activationIdentity + generation`、真实 resolver/preparation、retry/return cancellation；另加 `SpatialPracticeLaunchCoordinator(awaitingPreparation/awaitingPracticeActivation)` 会复制生命周期 | P5-T3 继续使用唯一 `PracticeLaunchViewModel`；setup 未 ready 时先注册现有 `.requested` 但暂不 activate，只补 expected `scoreFileVersionID`/spatial-origin 事实并放进现有 activation/return context；Preparation 用既有 `isFinishingSetup` 区分成功 dismiss 与用户取消 |
| 高：Library preview 与 Practice page navigation 会同时拥有同一 Spread | 原 handoff 只写 Practice become authoritative，没有关闭 preview 的 prepared/navigation lifecycle | P5-T3 成功 activation 后先关闭/cancel Library preview owner 再绑定 Practice owner；失败/取消则 preview 保持唯一 owner；返回 Book Flow 不复活第二页码 owner |
| 高：AI `requestGeneration` 不是唯一播放窗口身份 | `AIPerformanceService.generateContinuousWindow()` 把 `phraseGenerationAtRequest` 传给 queue；同一 generation 可连续接受多个 playback windows，不能用它关联 CompanionAction/shifted schedule/开始时间 | P6-T1 由 `DuetAIPlaybackQueue` 为每个 accepted `WindowItem` 分配独立 `windowID`，并把 action + shifted schedule + 实际 play start 原子发布；requestGeneration 只保留 stale/cancel 语义，不建平行字典 |
| 高：AI note-on/off 没有稳定 occurrence identity | `ImprovScheduleBuilder` 当前生成的 `PracticeSequencerMIDIEvent` 默认 `sourceEventID == nil`；同音高重叠/重复时仅按 MIDI/order 配对会含糊 | P6-T2 在 schedule builder 就给每个 AI note occurrence 生成确定的非 nil sourceEventID，on/off 共享；Companion contact builder 严格按 ID 配对，缺失/冲突直接拒绝，不保留 FIFO 兼容 fallback |
| 高：当前-unit Replay 有声音但没有示范手时钟 | `replayCurrentUnit()` 走 `PracticeManualReplayService`；现有 demonstration timing 只由 Autoplay 发布，因此“复用 Replay 做一键示范”按旧计划会变成音频播放、手不动 | P6-T2 让现有 Manual Replay 在真实 `play()` 后发布同一中性 hand-motion transport/contact timing，并在 stop/reset/replacement 清空；P6-T4 只加 ephemeral Demonstration intent，不新增 playback engine/timer |
| 高：结果/重练仍退回 Window Alert | 第 08 设计稿要求结果与 focus/retry 发生在 Book Spread；当前 `PracticeStepView` 用 round-completion Alert | P6-T4 复用 `PracticeRoundSummaryViewModel/PracticeNextAction/PracticeHotspot` 在 Spatial Book Spread 展示并删除旧 round Alert |
| 高：返回 Spatial Library 会被旧 return lifecycle 关闭 ImmersiveSpace | `PracticeWindowReturnCoordinator` 成功后硬调用 closeImmersive，window onDisappear 又有 system-close | **P5-T3 当场修**：保持 `flush/discard -> finishReturn/finalize -> presentation completion -> teardown -> dismiss Window`，把 hard-coded close 改成中性 completion；spatial return 切 `.practice → .library` 不关 scene，并让 onDisappear 复用 return coordinator 事实避免二次关闭。P6-T5 只回归验证 |

### 已实际执行的基线

- `make doctor`：通过，Xcode 27.0 / Swift 6.4。
- `make build:simulator`：通过；只证明当前 Apple target 可构建，不证明新功能。
- 默认 `swift test --package-path Packages/HappyPianistCore` 路径的首次验证因默认 macOS deployment 与 `.replacing` availability 不符而编译失败；未修改 Package platforms 来掩盖它。
- 改用 `swift test --package-path Packages/HappyPianistCore --triple arm64-apple-macosx26.0`：实际运行六个 test products，共 **238 tests 通过**，其中 Notation 51、Practice 96、Library 43；这是 macOS package 基线，不能替代 visionOS 集成与 ImageRenderer 验收。
- 日志：`/tmp/happypianist-preflight-core-full.log`、`/tmp/happypianist-preflight-build.log`。未运行 Simulator test / 真机 / 新 UI 手动验收；不挪用旧文档或旧 audit 的通过声明。

当前生产唱片、进度 Ornament、横向谱面仍有真实 caller，不是可立即硬删的死代码。本轮修订计划，不提前删除正在提供功能的 View；替换交付与删除必须在下表指定的同一 task 完成，不能变为末尾清扫任务。

### 强制清理归属

| 替换任务 | 同提交删除 / 迁移 |
| --- | --- |
| P1-T1 | 旧 `LibraryRecordScrollPresentation` 定义与测试；新值立即由当前 carousel 使用 |
| P1-T2 | Vinyl/Tonearm、旋转 TimelineView 状态、Record/Crate 命名、labelColor 与旧文案/图标/caller |
| P2-T1 | 旧 monolithic LayoutService；全谱重复计算与 layout 的 highlight 依赖；不存在另一条 legacy engraving |
| P2-T3 | 旧 GrandStaffNotationView、viewport pixel clamp/固定 header/centering scaffolding、current-tick context helper、notationMeasureSpans 子集入口、全部 smooth scroll schedule；共享 transport 时间/手部 contact timeline 不删 |
| P2-T4 | selected confirm → toggle playback、旧 progress Ornament/empty animation、仅其使用的 libraryViewHeight/测量、旧 reset-dialog 挂载（确认能力迁入 detail） |
| P3-T1 | 如有试验动画 wrapper 当场删；不新增兼容旗标、计时器或 bitmap 缓存 |
| P4-T1 | 用共享 coordinator **替换**旧 immersive owner；删除 `.inTransition`、`recoverIfStuck`、yield-loop/recursive retry、`PracticeImmersiveCloseCoordinator`、旧 `PracticeImmersive*` contract/adapter 名称与 caller plumbing；同 task 把 ARTrackingService 改为保留 world provider 的增量 reconcile + session-events 真状态同步，并从 protocol 删除无生产 consumer 的 `activeRequirements` / `authorizationStatusByType` |
| P4-T4 | Window Book Flow 核心 browsing/confirm 路径退出 production；删除旧 drag-delete/hold policy/tests；imported-song delete 迁到辅助管理 UI 后继续走现有业务 gate |
| P5-T1 | 删除“方向无法判断但用 zero offset 继续 `.resolved`”以及 `PianoCalibration` zero default / `PianoKeyGeometryService` zero→+Z 的兼容兜底；统一 horizontal-frame + player-side invariant，改成 typed recoverable failure |
| P5-T2 | P4 selected Spread 的临时 Library scene ownership 当场迁到唯一 SpatialScore controller；UserDefaults preference 同时接入这个真实 production owner，不留孤立 store |
| P5-T3 | 成功 Practice activation 释放 Library preview page owner；空间 Start Practice 复用唯一 `PracticeLaunchViewModel` 并删除旧 Window start button/onStartPractice/pushWindow 链；同 task 把成功 return 改成 same-ImmersiveSpace `.practice→.library`，不复制第二份 launch/score/page/return state |
| P5-T4 | **不作为延期清理桶**；P5-T1/T2/T3 各自在生产路径接入时删除被替代的 fixed translation/debug placement。T4 只增加最终位置微调/重置并验证 resolver + keyboard-local preference |
| P6-T1 | 删除 `isVirtualPerformerEnabled/setVirtualPerformerEnabled` 等旧产品 API 命名和被新 playback presentation 取代的 phase-only glue |
| P6-T2 | Demonstration-only motion plan/clip-set/transport/callback/session/skeleton/root-planner 命名迁成共用 `PianoHand...` 内核，并把可复用纯运动代码移动到中性 `PianoHandMotion/`；不留 deprecated alias/旧 forwarding file |
| P6-T3 | 当场删除 NeonHand、旧 Demonstration overlay、VirtualPerformer/Xiaocheng/第二台 performer piano 与仅服务这些 renderer 的测试/资产；rig/loader/asset/generator 迁成 Companion identity；旧 `DemonstrationHands/` 目录清空删除；同步更新 `HappyPianistAVP/AGENTS.md`；**同时删除旧 persistent Demonstration setting/AppStorage**，中间态只允许内存 ephemeral demonstration intent |
| P6-T4 | 新增 one-shot Companion Demonstration 空间动作但不重建持久 setting；删除 View-local autoplay 真值、旧 round-result Alert、重复 score/2D keyboard/top cue/永久 toolbar；结果/focus/retry 回到 Spatial Book Spread |
| P6-T5 | 只做 E2E/lifecycle/teardown/真机回归；successful return 已由 P5-T3 修成 same-ImmersiveSpace `.practice → .library`，T5 不再第一次重构返回路径，也不承接更早 task 的清理 |

重复守卫只在已证明同一无悬挂执行段上游保证不变量、无外部/异步边界时删除；UI disabled 不是 service 权限证明。输入/文件校验、导入原子性与备份恢复、过期任务隔离、无障碍基础不列入删除项。

## 1.1 Library 不是只换两个 View

当前唱片隐喻散落在：

- `LibraryRecordCarousel.swift`
- `LibraryRecordCarouselActions.swift`
- `VinylRecordView.swift`
- `TurntableTonearmView.swift`
- `LibraryNowPlayingBar.swift` 的 `record.circle`
- `SongLibraryView.swift` 空曲库文案与调用
- `SongLibraryTrackPresentation.labelColor`
- `LibraryRecordScrollSelectionTests.swift`
- `LibraryDeletionHoldPolicyTests.swift`
- preview / accessibility 文案中的“唱片架 / 唱片 / crate”

因此 P1 必须在**替换任务本身**清掉这些旧命名与视觉，不允许把清理拖到 P3。

### 需要保留的真实安全边界

以下不是“多余安全围栏”，不得因为清理旧 UI 而删除：

- bundled 曲目不可删除；
- import active 时禁止删除/开始练习；
- destructive delete 的 hold-to-confirm；
- selection persistence 的 generation / debounce；
- import transaction 的取消/恢复边界。

这些属于数据安全或并发生命周期，不是兼容层。

---

## 1.2 旧 Book/Record tap 语义与新产品冲突

当前：
- 点未选中 item → 选中；
- 再点已选中 item → 播放/暂停。

新产品最终应为：
- 点/确认未选中 item → 选中并居中；
- 确认中央选中 folio → 打开 Book Spread；
- 试听继续由现有 `LibraryNowPlayingBar` 独立按钮负责。

Book Spread 尚未完成前，P1 可以暂时维持当前播放动作以保持每个阶段可用；但 **P2 Library detail 接管时必须当场删除 selected-item toggle-playback 路径和对应测试，不保留兼容分支**。

---

## 1.3 Notation 当前不是“可直接分页”的模型

现有：

`GrandStaffNotationLayoutService`

同时负责：

1. 从 `ScoreNotationProjection` 生成 engraving facts；
2. 解析 accidental / chord / beam / marks / spanners；
3. 计算全局 horizontal spacing；
4. 根据 `scrollTick` 做 viewport clipping；
5. 把绝对位置归一化到当前 viewport；
6. 根据 active range 再裁剪；
7. 生成 tie/slur/tuplet continuation。

这几层职责纠缠在一起。

所以不能直接“新增 PaginationService，然后重复调旧 LayoutService”。那会：
- 重复 spacing；
- 每个 system 重做全曲 engraving；
- system 边界 context 错误；
- 容易让 spanner / beam / ending 在换行处断掉。

P2 必须先把 **score-level engraving / spacing** 与 **system slicing / viewport presentation** 分离，再做 pagination。

同一首曲子的 Library preview 与 Practice 还必须共享 canonical page geometry：system/page 边界以 staff-space/page units 决定，宿主窗口只负责等比显示，不能因为 pixel size 不同导致页码漂移。

---

## 1.4 每个 system 都需要自己的记谱上下文

当前 `PracticeSessionViewModel.currentGrandStaffNotationContext` 只根据“当前演奏 tick”解析一次：
- clef；
- key signature；
- meter。

单 viewport 可以这样做；一页同时显示多个 system 后就不成立。

每个 system start 必须根据 `MusicXMLAttributeTimeline` 解析自己的 context。

因此 P2 接入新 spread 后，应删除：
- `currentGrandStaffNotationContext`
- host 里的 notation clef/key text helper（若无其他调用）

不能继续让 Practice host 给整页只传一个 current-tick context。

---

## 1.5 分页不能只看小节宽度

系统换行必须同时保证音乐结构：

- accidental 必须先按完整 source measure 解析，不能因为 system break 重置错；
- tie / slur / tuplet 跨 system 必须继续；
- repeat ending 跨 system 必须继续；
- source explicit beam 若跨 measure boundary，该 boundary 不可切断；超宽组独占 system 并按完整 ink bounds 均匀 fit，提供放大阅读，不能以“轻微超宽”裁掉内容；
- repeat / attribute change 保留 source tick；
- 每个 system start 重述当前 clef / key / meter。

不额外实现“专业出版级自动美化”或 courtesy signature 系统；只保证当前已经支持的 notation facts 不因分页丢失。

---

## 1.6 旧横向滚动还有一套专用 runtime

当前 autoplay 为旧连续横向谱面维护：

- `PracticeSessionNotationGuideScrollPoint`
- `notationGuideScrollSchedule`
- `notationGuideScrollScheduleBaseTick`
- `notationGuideScrollScheduleTaskGeneration`
- `notationGuideScrollScheduleTimelineEventCount`
- `PracticePlaybackControlService.smoothNotationScrollTick()`
- `ensureNotationGuideScrollSchedule(...)`
- `PracticeSessionViewModel.notationViewportTick()`

分页以后不需要连续 interpolation。

只需要：
> 当前 practice / autoplay 的离散 navigation tick → page/spread index。

所以 **P2 Practice 接入时就删除整套 scroll-schedule 代码**；不能改名后继续保留，更不能拖到 P3 最后清理。

---

## 1.7 Library 当前没有真正谱面 preview 数据

`SongPracticeLibrarySnapshotBuilder` 只提供历史摘要，没有 `ScoreNotationProjection`。

真正谱面事实来自唯一正式路径：

`SongLibraryEntryResolver → PracticePreparationService → PreparedPractice`

而 `PreparedPractice` 已包含：

- `notationProjection`
- `measureSpans`
- `attributeTimeline`
- `scoreContext`
- `performancePlan`

因此 Library Book Spread preview 必须复用这条 preparation source of truth。

禁止：
- Library 自己再写 parser；
- 为 preview 再造一套 score projection；
- 用 PDF/bitmap 替代动态 notation；
- 为“更快”引入静默 fallback preview。

如果 preview prepare 失败，就显示明确失败状态；不偷偷退回旧唱片详情。
## 1.8 Library 练习状态需要逐小节数据，而不是只有总数

当前 `SongPracticeLibraryOverview` 已有：

- stable / learning / unpracticed **总数**；
- `resumeSourceMeasureID`；
- `focusMeasures`。

但原型 02 需要把 stable / learning 直接标在对应小节上。

因此 P2-T4 必须让现有 `SongPracticeLibrarySnapshotBuilder` 同时派生“逐 source measure 的 learning state”。聚合统计和逐小节状态必须来自同一份 `uniqueCurrentFacts`，不能让 Book Spread 自己再读取 progress repository 或复制一套合并规则。

`MusicXMLMeasureSpan.sourceMeasureID` 已提供谱面小节与 progress source measure 的正式映射。

当前 `SongLibraryView` 还把 `LibraryPracticeProgressOrnamentView` 作为 trailing glass ornament 挂在曲库右侧；它的 overview/invitation 内容会被新的 Book Spread 直接取代。因此 P2-T4 必须迁移 loading/unavailable/recovery 行为后，当场删除 `LibraryPracticeProgressOrnamentView.swift` 与只为它服务的 `LibraryPracticeEmptyAnimationView.swift`，不能让新旧练习历史 UI 并行。

其中“练习记录损坏 → 明确确认后备份并重置”属于真实数据恢复边界，必须迁移保留，不能因为删除旧 Ornament 一起删掉。

## 1.9 项目已经有可复用的空间基础，不需要另造第二套 AR 架构

当前真实能力：

- App 已有唯一 `.mixed` `ImmersiveSpace`，内容入口是统一的 `ImmersiveView/RealityView`；
- `ARTrackingService.deviceWorldTransform(atTimestamp:)` 已能取得当前设备的世界位姿；
- `AppState` 已有 immersive open/transition/closed 状态，但 mode 只有 calibration/practice；
- 现有 A0/C8 WorldAnchor 校准会得到 `PianoCalibration → KeyboardFrame → PianoKeyboardGeometry`；
- Real Audio 与 Bluetooth MIDI 都要求真实钢琴校准完成，因此可共用同一个 KeyboardFrame；
- `KeyboardFrame.+Z` 只是右手坐标约定，源码明确不保证“朝向用户”；已有 `frontEdgeToKeyCenterLocalZ` 才是正式的钢琴内侧方向事实。

因此：

- P4 复用现有 mixed ImmersiveSpace，不创建第二个空间；
- Spatial Library 只需要 session-scoped 世界 transform，不给每本 folio 建 WorldAnchor；
- P5 的 score transform 必须是 `worldFromKeyboard × keyboardLocalScoreTransform`；
- 不保存 score 世界坐标，也不创建 score 专属 persistent WorldAnchor。

## 1.10 当前空间视觉存在三条互相冲突的“手/角色”路径

当前 `ImmersiveView` 同时管理：

- `NeonHandOverlayController`：把用户真实 tracked hands 再画成青/紫霓虹手；
- `PianoDemonstrationHandsOverlayController`：一双虚拟教学手；
- `VirtualPerformerOverlayController`：Xiaocheng + 自己的 performer piano + gait/head/arm 动画。

这和当前产品定义冲突：

> 用户真实手保持 passthrough；Teaching 与 AI Duet 只能有同一双 Companion Hands；当前默认不显示 Xiaocheng 完整角色或第二台 AI piano。

因此 P6 必须**替换并删除**旧视觉实现，而不是只隐藏它们：

- 删除 Neon user-hand renderer，但保留 AR hand tracking 输入；
- Demonstration / AI 共用一套 Companion hand rig / motion pipeline / overlay controller；
- 删除 VirtualPerformer/Xiaocheng 当前 renderer、专属 piano 与只服务它的动画逻辑；
- full Companion character 以后如果重新设计，应作为新 feature，而不是保留当前死代码作为兼容层。

## 1.11 AI Companion 手必须跟真实音频播放时钟同步

现有 `CompanionAction` 已有：
- listen / support / sparse / respond / yield。

但 `AIPerformanceService.State` 目前没有把 validated action 暴露给 UI，而且 `DuetAIPlaybackQueue` 的 callback 只暴露 idle/preparing/playing。

真正的音频开始点发生在 `service.play()` 成功之后。并且当前 queue 的 `requestGeneration` 实际来自 `phraseGenerationAtRequest`，它只用于 stale/cancel 判定；同一 generation 可以产生多个连续 accepted windows，所以它不是播放窗口唯一 ID。

因此 P6 不能用“schedule 更新时刻”猜手部动画时间，也不能用 requestGeneration 反查当前动作。必须让 queue 为每个 accepted window 分配独立 `windowID`，并原子暴露：

- unique accepted window identity；
- validated CompanionAction；
- shifted schedule；
- 实际 playback start monotonic time。

只保留 current/pending 有界事实，不在 `AIPerformanceService` 再建一张 generation→action 历史表。

AI schedule 再转换成 `PianoKeyContactTimeline`，复用现有：

`PianoFingeringPlanner → PianoHandMotionClipBuilder → PianoHandMotionPlayer`

AI schedule builder 必须先给每个 note occurrence 写入稳定 `sourceEventID`，note-on/off 共享同一 ID；Companion contact conversion 严格按 ID 配对，避免重复同音高时用顺序猜。

Demonstrate 也不能假定现有 Replay 已经提供 hand timing：当前 `PracticeManualReplayService` 只有音频/step cursor，示范手 timing 只接 Autoplay。P6-T2 要让 **同一个 Manual Replay engine** 发布中性 hand-motion timing，这样 P6-T4 的 one-shot Demonstration 才是真正“复用现有 Replay”，而不是暗中再造第二个播放时钟。

这样 Demonstrate 与 AI 使用同一套真实琴键动作基础，不新造第二套手部动画系统。

---

# 2. 不删除的现有能力

执行时不要把所有名为 fallback / guard 的代码都当成垃圾。

以下当前 Notation 能力是负载能力，必须保留并覆盖回归：

- source beam + meter-based fallback beam；
- unsupported notation 的明确 placeholder policy；
- tie/slur/tuplet continuation；
- accidental measure state；
- active range / highlighted event 的派生表现；
- Bravura / SMuFL glyph fidelity；
- VoiceOver / Differentiate Without Color；
- Dynamic Type / Reduce Motion。

“清旧代码”的目标是删除**被新实现替代的 UI / viewport / compatibility path**，不是拆掉音乐正确性与数据安全。

---

# 3. 最终架构

## 3.1 乐谱内容链

```text
MusicXML
  ↓
PracticePreparationService
  ↓
PreparedPractice
  ├─ ScoreNotationProjection
  ├─ measureSpans
  ├─ attributeTimeline
  └─ scoreContext 的 logicalInstrument / structuralPart 映射
          ↓
Score-level engraving / absolute spacing
          ↓
Pagination plan
measure → system → page → spread
          ↓
System renderer
          ↓
SwiftUI Book Spread
          ↓
page-turn presentation
```

Library 的曲库业务数据、导入事务、progress repository 不迁入 Notation。

Notation 不引用 HappyPianistAVP host。

## 3.2 空间呈现链

```text
SwiftUI folio / Book Spread
          ↓
RealityView Attachments
          ↓
RealityKit scene controllers
          ├─ SpatialLibraryRoot
          └─ SpatialScore / KeyboardScoreRoot
          ↓
ARKit world tracking
          ├─ current device pose → session Spatial Library placement
          └─ calibrated A0/C8 → KeyboardFrame → score placement
```

职责边界：

- SwiftUI / Notation：内容、分页、页内交互；
- RealityKit：世界位置、旋转、层级、handoff、空间交互；
- ARKit：设备/world pose、校准 anchor 事实；
- KeyboardFrame：现实钢琴局部坐标；
- 不让 RealityView controller 解析 MusicXML 或拥有 Library/Practice 业务事实。

## 3.3 Spatial Practice 组合

```text
real passthrough environment
  ├─ real piano / real user hands
  ├─ Spatial Book Spread
  ├─ PianoGuideOverlayController
  ├─ CompanionHandsOverlayController
  └─ small spatial feedback / controls
```

唯一 Companion hand motion 来源：

```text
Demonstrate score contacts ─┐
                            ├─> Fingering / MotionClip pipeline
AI accepted playback window ┘
                                      ↓
                         one CompanionHandsOverlayController
```

Practice 的评分、progress、AI generation 和 audio playback 仍各自保留原有单一事实源；空间 UI 只消费它们的 presentation state。

---

# 4. 实现阶段

## P1 — Book Flow

- P1-T1：纯值 Cover-Flow presentation geometry，当场接入当前 carousel 并删除旧模型。
- P1-T2：替换 Vinyl UI，并在同 task 清掉所有唱片/唱臂/Record/Crate 旧视觉语义。

## P2 — 真正的 Book Spread

- P2-T1：拆开 score-level engraving 与旧 viewport clipping；旧 monolithic 路径当场迁移，不复制第二套。
- P2-T2：验证 canonical 页几何、超宽/超高边界、宿主可读性与 Dynamic Type；不遗留无人使用的 production API。
- P2-T3：交付 deterministic pagination、多 system Page / 双页 Spread 并当场接入 Practice；同步删除旧 View/context/横向 scroll runtime。
- P2-T4：Library 中打开 Book Spread preview，selected folio confirm 正式替换旧 tap-to-toggle-playback。
- P2-T5：验证 Practice 范围/恢复/autoplay 与场景生命周期；不能承接 T3 遗留清理。

## P3 — 单页翻页

- P3-T1：建立并接入共用单页前/后翻 transition，当场覆盖 Reduce Motion / a11y，不留孤立组件。
- P3-T2：Library preview 接入手动前后翻页。
- P3-T3：Practice navigation tick 驱动自动翻页，快速跳页只收敛到最终目标。
- P3-T4：Reduce Motion / VoiceOver / Simulator 最终验收，只做验收与本 phase 当场产生的清理，不再承担 P1/P2 的旧代码清扫。

## P4 — Spatial Library

- P4-T1：用一个共享 ImmersiveSpace coordinator 替换旧 yield/recover 状态机，增加 `.library` mode，并让同一 scene 的 mode switch 立即重配 AR providers。
- P4-T2：根据当前设备 pose 建立一次 session-scoped、world-fixed 的 Spatial Library root；用有界真实时钟等待 world tracking/device pose，不建立永久 WorldAnchor。
- P4-T3：只为 selected 周围约 7 本创建独立 RealityView Attachments；支持 off-center confirm + targeted horizontal drag 浏览大曲库，并复用 P1–P3 内容/选择/翻页。
- P4-T4：Spatial Library 接管核心选曲；Window 收敛为导入、删除、诊断、setup 等辅助管理；旧 drag-delete/hold 随 Window Book Flow 当场删除。

## P5 — Spatial Score Placement

- P5-T1：建立 canonical keyboard-relative score placement resolver，正式处理 KeyboardFrame Z 方向与 player/interior side。
- P5-T2：建立唯一 SpatialScore owner，让 selected Spread 当场从 P4 临时 Library ownership 迁出；同一个 placement ViewModel 读取 UserDefaults 的 keyboard-local X/Y/Z 偏好，不新增 JSON/quarantine/recovery 基础设施。
- P5-T3：在 Spatial Book Spread 上直接“开始练习”，复用 `SongLibraryViewModel.startPractice` 业务 gate；需要时复用现有 Preparation / Calibration，并在共享 ImmersiveSpace 内完成 `.library → .calibration → .practice` handoff；删除旧 Window start-practice 链，并把 T2 已唯一拥有的同一逻辑 Book Spread 迁移到 `KeyboardScoreRoot`。
- P5-T4：使用 entity-targeted RealityKit 交互允许 X/Y/Z 微调、重置，并通过真机验证阅读舒适度。

## P6 — Reality-first Spatial Practice

- P6-T1：让 validated CompanionAction 与真实 AI playback start/window identity 成为正式可渲染状态，并清理“Virtual Performer”产品命名。
- P6-T2：把 AI schedule 转成 contact/fingering/motion clips，与 Demonstration 共用手部动作管线。
- P6-T3：建立唯一 CompanionHandsOverlayController；删除 Neon user-hand renderer、旧 Demonstration renderer、VirtualPerformer/Xiaocheng/第二台 piano 实现。
- P6-T4：把高频 Practice 控制、即时反馈以及 round 结果/focus/retry 空间化；使用 Session 唯一 autoplay state 与明确 Companion/Autoplay/Demonstration 互斥规则；复杂设置继续留辅助 Window；删除旧 round Alert 和重复谱面/钢琴/toolbar。
- P6-T5：保存成功后在同一 ImmersiveSpace 内 `.practice → .library`，避免 Practice Window disappear 二次关闭空间；收口完整 Library → Practice → save → Library 生命周期、a11y、Simulator 与 physical AVP 验收。

---

# 5. 文档同步

- P2-T1 / P2-T3 / P2-T4 更新 `docs/data-flow.md`：Notation 从 projection 进入 score-level engraving，再进入 system/page/spread；overlay 仍是派生表现。T2 实验只记录本地计划，不把未实现结构预写成长期架构事实。
- `docs/architecture.md` 按 owner task 当场同步：P4-T3 写 shared ImmersiveSpace + SpatialLibrary；P5-T3 加 SpatialScore handoff；P6-T3 加唯一 Companion Hands。P6-T5 只做最终一致性检查，不把前面应更新的架构文档拖到最后。
- P6-T3 删除 Neon/Demonstration/VirtualPerformer renderer 的同 task 更新 `docs/data-flow.md`，不能让长期文档继续描述已删除的“荧光手套 + 示范手”路径；后续只在最终生命周期事实变化时再补。
- 测试证据只在实际执行后更新 `docs/testing.md`，不预填“通过”。
- P5 keyboard-local placement preference 使用 UserDefaults，不新增 Documents 持久化文件；只有实际改变 `docs/storage.md` 已列业务存储边界时才更新该文档。

---

# 6. 完成标准

## Book / Notation

- 仓库不再存在 production 使用的 Vinyl / Turntable / LibraryRecord / LibraryCrate UI 语义。
- Book Spread 每页纵向显示多个 Grand Staff systems，而不是把旧单 viewport 缩小两份。
- Pagination identity 与当前 tick/active overlay 无关；相同 score + canonical page geometry 得到稳定分页。
- Library 与 Practice 共享同一 Book Spread/page plan。
- 旧 continuous notation scroll runtime 完全删除。
- 当前已支持的 musical notation / a11y 不因分页回退。

## Spatial Library / Score

- Spatial Book Flow 真正存在于 mixed ImmersiveSpace 世界坐标中，用户移动头部时不会跟脸移动。
- 每个 folio 是独立空间 attachment/entity，不是一整块伪 3D 平面窗口。
- Spatial Library 第一版没有多余 persistent WorldAnchor。
- 选中 folio 可在空间打开动态 Book Spread。
- 同一 Book Spread 可从 Library 迁移到现实钢琴上方，不创建第二份谱面状态。
- score placement 由 KeyboardFrame + keyboard-local offset 决定；不保存世界坐标。
- Real Audio / Bluetooth MIDI 共用同一真实钢琴 placement pipeline。
- 用户微调只在 gesture commit 持久化，并能重置。

## Reality-first Practice

- 用户真实双手保持 passthrough，不再有 Neon duplicate hand renderer。
- Teaching 与 AI Duet 只存在一双 Companion Hands。
- 当前 production 不再有 VirtualPerformer/Xiaocheng/第二台 AI piano 路径。
- AI Companion Hands 使用 validated action + 实际 audio playback start timing，不用 UI 自己猜时钟。
- Piano Guide 继续是唯一琴键引导 renderer。
- 核心 Practice 不再重复显示 Window 谱面、二维练习钢琴和永久底部 toolbar。
- 高频控制/反馈在空间中；复杂配置仍可通过辅助 Window 使用。
- 退出 Practice 仍严格保留 progress flush / failure / explicit discard 安全语义。
- Reduce Motion / VoiceOver / Differentiate Without Color 在空间路径中可用。
- Simulator/build 测试只能证明软件路径；world stability、真实琴键对齐、阅读舒适度和 Companion finger alignment 必须由 physical AVP 证据支持，硬件不可用时明确标记该 Gate 未完成。
