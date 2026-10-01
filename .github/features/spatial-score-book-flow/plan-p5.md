# Plan P5 — Companion Hands、空间反馈与结果重练

**Goal:** 3D 使用同一双伙伴手完成真实教学/陪弹；高频操作、反馈与结果/复测全部围绕同一谱和琴。
**Non-goals:** 不删原 2D Neon/示范手/VirtualPerformer/settings，不改 AI 算法/backend，不新建 audio engine/动画时钟/角色。
**Approach:** 先接一次性教学与真实 replay timing；随后把 AI 播放事实接到同一手 renderer；最后补全控制/反馈/谱上结果和辅助设置。
**Acceptance:** D07/D08/D09 完整；3D 无重复用户手/角色/琴，Guide fallback 可见，重练真修改音乐范围，2D 原功能仍可用。
**Rules:** 动作消费 actual playback，不以提交时间/latest schedule 猜开始；asset/coverage 失败不能改音乐或假成功；声音/录音/AI 互斥复用原 owner。

依赖：P4 正式练习/保存闭环与 keyboard frame。教学/陪弹的 controls 在各 task 同时接入，不等最后才创建 consumer。

## P5-T1 在同一空间手 renderer 接入一次性真实教学

**当前事实：**
- `PianoDemonstrationHandsOverlayController` 已有异步左右 21-joint rig、reset/失败处理与 Guide suppression。
- `PianoFingeringPlanner → PianoHandMotionClipBuilder → PianoHandMotionPlayer` 已有真实接触/动作内核。
- 当前 `pianoDemonstrationHandsTiming` 非 autoplay 返回 manual，但 `PianoHandMotionPlayer.samples` 只接受 transport；不能把“manual”当已有可用教学动画。
- `PracticeManualReplayService` 掌握实际 warmUp/load/play/currentSeconds 与 generation，当前没有供手渲染的 replay timing。

**Files：**
- Add: `HappyPianistAVP/Services/Spatial/SpatialCompanionHandsController.swift`，同 task 被 3D practice scene 安装。
- Modify: `HappyPianistAVP/Services/Practice/Playback/PracticeManualReplayService.swift`、`ViewModels/Practice/Session/PracticeSessionViewModelPlayback.swift`。
- Reuse/最小共享提取: `Services/Practice/DemonstrationHands/PianoHandMotionPlayer.swift`、`PianoHandMotionClipBuilder.swift`、`PianoDemonstrationHandsOverlayController.swift`、`Models/Immersive/PianoDemonstrationPlanning.swift`。
- Modify: `HappyPianistAVP/Views/Spatial/SpatialPracticeView.swift`、`Views/Spatial/SpatialExperienceView.swift`。
- Assets: 复用 `Packages/RealityKitContent/Sources/RealityKitContent/RealityKitContent.rkassets/PianoDemonstrationHandLeft.usdc` / `PianoDemonstrationHandRight.usdc`，不新造另一双。
- Tests: 新 `HappyPianistAVPTests/Spatial/SpatialCompanionTeachingTests.swift`；现 `Practice/PracticeManualReplayCoordinatorTests.swift`、`Piano/PianoHandMotionPlayerTests.swift`、`PianoDemonstrationHandsOverlayControllerTests.swift`、`PianoHandMotionQualityTests.swift`。
- Docs: `docs/architecture.md`、`docs/data-flow.md` 的新旧 renderer ownership。

**实施：**
1. 3D 谱旁“示范当前片段”是一次性动作，使用既有 replay plan/performance sequence、选定 hand/range/tempo/route；结束自然退手，保留停止，不变永久 hands toggle。
2. 手 timing 从实际 play 成功/currentSeconds/current generation 发布；包含真实 sequence lead-in、暂停/停止与 contact timeline。loading/preparing 不当已触键，不能拿 UI 点击时钟。
3. 从 actual replay timeline 生成 contacts→fingering→motion，重用现 off-main builder 与质量拒绝，geometry/range/revision/generation 更新拒绝旧结果。
4. 若需泛化 sample/rig 应在现共享内核最小位置提取，新/旧 renderer 都消费；不复制 IK/骨架/asset loader，不删除仍被原 2D 使用的 public timing/settings/APIs。
5. 3D 只有一个左右手 root，teaching 先接这对。legacy demonstration/Neon/VirtualPerformer 不在新 scene composition；没有全局删除计划。
6. 只对当前确实可见且有有效 contact coverage 的音符 suppress Guide；单手资产/coverage/Reduce Motion 不显示时对应 Guide 恢复。用户真实手不重绘，虚拟手不参与输入/碰撞/判定/progress。
7. replay 完成、停止、seek/范围变、新曲、后台/reset、退出取消加载/build、停声音并移 root，late asset 不恢复；识别恢复沿原 effect handler，不能只把 UI 关掉。

**验证：**
- 真实 replay fixture 与 sound fake currentSeconds，不以 timer 驱动：lead-in/首击/休止/结束、左右手 independent coverage、停止/重播/乱序 build。
- samples 不再“manual 永远空”，clip identity 与当前 transport 匹配；实际 rig transform 和 Guide visibility 恢复，不只 callback 命中。
- asset 单手失败、coverage 拒绝、Reduce Motion、reset late load；共享旧 renderer/timing/replay 仍通过。
- 真正 xcodebuild test/build；实际 D08 teaching 操作；现质量 corpus 阈值复用，physical AVP 音画/键面对齐单独留证。

**Gate / 原子提交：** 一次示范声音、手、Guide 与结束链真实成立；`feat: P5-T1 - 接入真实时序的空间教学手`。

## P5-T2 用实际 AI 播放窗口驱动同一双 Companion Hands

**当前根因：**
- `AIPerformanceService.State` 只有 active/generating/playing/latestSchedule/status，不暴露 validated action/start。
- `DuetAIPlaybackQueue.WindowItem` 持 shifted schedule/routing/provider/requestGeneration，callback 只 PlaybackPhase。
- requestGeneration 来自 phraseGeneration，是取消隔离代次；多个有效窗口可共享，不能作为唯一 playback window ID。
- 实际 `service.play` 成功之后才进入 playing，动画不能按 submit/latestSchedule 当已播放。

**Files：**
- Modify: `HappyPianistAVP/Services/Practice/AI/Playback/DuetAIPlaybackQueue.swift`、`Services/Practice/AI/AIPerformanceService.swift`、`ViewModels/Practice/AI/ARGuideAIPerformanceViewModel.swift`。
- Modify: `HappyPianistAVP/Services/Spatial/SpatialCompanionHandsController.swift`、`Views/Spatial/SpatialPracticeView.swift`；同 task 接 live AI producer→motion→renderer→控制。
- Reuse/最小泛化: `Packages/HappyPianistCore/Sources/Practice/PianoFingeringPlanner.swift`、`PianoHandMotionClip.swift`；现 motion builder/player。
- Tests: 新 `HappyPianistAVPTests/Spatial/SpatialCompanionDuetTests.swift`；现 `Practice/DuetAIPlaybackQueueTests.swift`、`DuetOutOfOrderResponseTests.swift`、`DuetParallelInputWhilePlaybackTests.swift`、`DuetDisableTeardownTests.swift`。
- Docs: `docs/data-flow.md`，现 diagnostics/隐私边界不扩写原始数据。

**实施：**
1. accepted WindowItem 持独立唯一 windowID、validated CompanionAction 与 shifted schedule；requestGeneration 仍只拒绝 stale。playing event/state 在实际 play 成功且当前时发布真实开始/位置事实；pending schedule 不能覆盖 current playing。
2. action 随真实窗口在同一 queue item 原子携带，不新建 generation→action dictionary。无音频时 listen/yield 可以用 validated semantic action；有音频时只能取 playing window 对应 action。
3. 将真实 note-on/off/时序转 contact timeline：配对 channel/pitch/lifetime、重音/重复音/踏板的实际播放语义，不以 MIDI channel 猜左右手。使用已知声部/合理可证映射；无法安全分手/指法/动作时对应手降级 Guide，不修改真实 audio content。
4. 对窗口范围复用 fingering/clip builder/player，用实际播放开始/position 与 PerformanceClock 同源；迟到 motion 只采当前仍 playing 的窗口，不从头再播手。只留当前/必要 pending facts，容量有界。
5. teaching 与 AI 用同一双 rig。一次性教学开始前通过既有互斥停止/拒绝当前 AI，AI 不能抢教学；支持 support/sparse/respond 的动作密度，yield 依据真实 playback stop 退手/清 pending。
6. 新 Companion 控制使用现 AI enable/service/backend 选择路径；原 isVirtualPerformerEnabled 与旧设置仍用于真实 legacy consumer，不做全局重命名/删除，不新建第二 AI-enabled shadow 状态。renderer 是否显示由产品路径决定，不把“开启 AI”绑定到必须安装旧角色。
7. backend 错误提示并停止本次生成，不自动切后端；3D 不暴露 Qwen/Aria/RTT/internal action 标签，不以假动作掩失败。任何 failed rig/coverage 都恢复对应 Guide。
8. stop/yield/新窗口/新曲/后台/退出清实际音频与当前表现，已经 playing 的音频是否保留沿现 queue policy，不因新输入 generation 错停合法 playback。

**验证：**
- 同 requestGeneration 两 accepted windows 不同 windowID；pending replacement 不改 current action；load/play 失败不发布 playing hands。
- 实际 sound fake play/currentSeconds + 动作采样，note-on/off 对齐、lead-in/晚到 clip、generation/geometry/session 身份隔离。
- listen/yield/support/sparse/respond、teaching/AI 互斥、单手 unknown/collision/asset fail、Guide 真恢复。
- stopAll/yield 清 pending/声音/rig，late asset/network 不复活；旧 2D VirtualPerformer 继续原活动状态与音频语义。
- 真实 xcodebuild test/build，D08 全动作短片；physical AVP 同步/遮挡/对齐，无法测则 pending。代码 tests 不证明 AI 音乐质量或教学效果。

**Gate / 原子提交：** 真实播放事实到唯一手的端到端 invariant 成立；`feat: P5-T2 - 用真实陪弹窗口驱动统一空间伙伴手`。

## P5-T3 补全空间控制、谱上反馈与结果复测

**现有 consumer 与边界：**
- `PracticeStepView` 的 toolbar、settings、alerts/cue 是原 2D 产品，保留不改形态。
- `PracticeRoundSummaryViewModel` 用小节 progress/configuration/coaching 生成 nextAction。
- `PracticeSessionViewModel.perform(action)`、pending round configuration、skipCoachingDecisionAndContinue 拥有真实行为；UI 不能自行改 steps/进度。
- RecordingViewModel/TakePlayback/AI/autoplay 的现互斥和 output reset 必须共用。

**Files：**
- Modify: `HappyPianistAVP/Views/Spatial/SpatialPracticeView.swift`、`SpatialBookPageContentView.swift`、`ViewModels/Spatial/SpatialExperienceViewModel.swift`、`SpatialScoreBookViewModel.swift`。
- Add: `HappyPianistAVP/Views/Spatial/SpatialPracticeResultView.swift`，同 task 为 Completed book 的局部消费。
- Reuse: `ViewModels/Practice/Step/Feedback/PracticeRoundSummaryViewModel.swift`、practiceFeedbackViewModel、session round configuration controller。
- 必要共享副作用 consumer: `HappyPianistAVP/ViewModels/ARGuideViewModel.swift` 的 recording/AI/autoplay actions；不删原 settings/TakeLibrary。
- Tests: 新 `HappyPianistAVPTests/Spatial/SpatialPracticeControlsTests.swift`、`SpatialPracticeResultTests.swift`；现 `Practice/PracticeRoundSummaryViewModelTests.swift`、`PracticeLearningLoopIntegrationTests.swift`、`Recording/ARGuideRecordingViewModelTests.swift`。
- Docs: `docs/data-flow.md`、`docs/configuration.md`。

**实施：**
1. 谱旁按需控件补节拍器/录音/速度/手模式/范围/示范/Companion。基础暂停/退出继承 P4，不常驻成 toolbar，不用无标签图标/秘密手势。业务互斥在既有 action owner 生效，禁用只是呈现。
2. 复杂设置、backend 与录音库明确辅助入口复用原组件；不挂载原 PracticeWindowRootView/PracticeStepView 去承载设置，避免启动第二 launch/open/lifecycle。
3. 辅助 Window 只负责设置，不接管练习；其 inactive/disappear 不 flush/stop 新空间。用户在设置主动改变配置沿现 pending/apply/rebuild/save gate；若 platform scene 真的 inactive 则由 spatial owner 按 P4 暂停，不猜“只是打开窗口”。
4. cue 贴当前谱中对应小节，未知/证据不足/低置信度不涂错误；coaching 一次一个范围/动作/完成条件。反馈事件不写新 progress 字段。
5. Completed 在同一 book 显示真实 summary、小节事实与 focus；不跳旧 Alert、不造 dashboard。选择合法小节/建议调用 existing nextAction/configuration；按 perform 的结果继续或走 P4 的安全返回。
6. 重练/继续/扩大范围/降低速度/跳过建议产生真实 session config/retest 关联；page target 由新音乐位置更新，不只是把高亮移过去。晚到 cue/result 不能盖新轮。
7. 完成不等于已经保存，所有回库/退出仍 P4 gate；无第二份 progress/summary JSON。隐藏颜色有形状/文本，large text 与 VoiceOver 可操作整个结果。

**验证：**
- 所有 controls 实际 effect：play/stop、record start/stop、排斥冲突 playback、配置重建失败保留会话；不仅 Button closure。
- result→合法 focus→perform→真实 passage/tempo/range/round/retest→再次 complete，只有一个建议；unknown/low confidence 无错误。
- auxiliary settings open/close 不重启 launch、不关 scene、不更换 owner；主动 apply/后台/退出真实输出 cleanup。
- 保存失败仍原谱/轮，原 2D toolbar/alert/settings/recording 回归；定向 Apple tests/build，实际 D07/D09/D10 操作。
- 动态反馈/结果只展示批准的聚合事实，不新增进度字段/敏感日志。

**Gate / 原子提交：** 3D 主流程控制、结果与复测无需旧 Practice Window；`feat: P5-T3 - 补全空间控制反馈与谱上复测`。

## Phase Audit

完成后创建新版 `audit-p5.md`。分别审音乐时序、Guide coverage、手/音频 teardown、真实复测和 auxiliary lifecycle；“事件已发/分支已选”不替代声音停止/文件保存/配置改变。旧 2D renderer 必须仍可用，禁止全仓零旧符号作为 Gate。
