# Plan P3 - 单页翻动与 Spread 导航

**Goal:** 在 P2 稳定 Book Spread 上增加“像翻一张真实纸页”的过渡，同时让：

- Library preview：用户手动前后翻；
- Practice：演奏位置自动切换 spread；

共用同一个 page-turn presentation。

**Visual acceptance references:**
- `.github/features/spatial-2026-09-30/设计稿/images/02-双页Book-Spread曲目详情.png`（双页作为稳定阅读对象）
- `.github/features/spatial-2026-09-30/设计稿/images/04-正常练习.png`（练习时自动跟随当前演奏位置）
- `.github/features/spatial-2026-09-30/设计稿/images/08-练习结果与重练.png`（结果/重练状态仍在同一 Book Spread 上继续浏览）

P3 只实现手动/自动翻页与 Spread 导航，不改变这三张图定义的谱面视觉体系。

**Non-goals:**
- 不做 deforming mesh / page curl physics；
- 不把 page turn 做成新的 practice clock；
- 不重新引入 continuous scroll；
- 不让 Library 和 Practice 各写一套翻页 renderer；
- 不在 Practice 增加会和自动导航冲突的“自由浏览模式”。

**Approach:** 把翻页实现为只消费目标 `spreadIndex` 的共用 presentation；Library 负责手动改变目标，Practice 只把现有离散 navigation tick 映射为目标 spread。

**Rules:** page-turn 不拥有谱面事实、页码真值或播放时钟；快速目标变化只保留最终目标。

**Phase acceptance:** Library 手动翻页与 Practice 自动翻页使用同一 presentation；快速跳页不积压过时动画，没有重新引入连续滚谱。

---

## P3-T1 建立通用 Spread page-turn presentation

**Goal:** page turn 只做表现，不拥有乐谱事实或导航事实。

### Files

Expected:
- Add: `GrandStaffNotationPageTurnState.swift`
- Add: `GrandStaffNotationPageTurnView.swift`
- Add: Notation tests / previews
- Update: `GrandStaffNotationSpreadView.swift`；本 task 当场由 P2 已接入的共享 Spread 消费，不等 T2/T3 才挂载。

### Navigation unit

导航目标是 **spread index**。

一个 spread 包含：
- left page；
- right page。

Forward：
- source spread = [L0, R0]；
- target spread = [L1, R1]；
- 视觉上只让 source 的 **right sheet** 从右向左翻；
- target left/right 作为翻页前后层提供内容。

双面内容要明确：向前翻 source right 的正面，背面为 **target left**（翻到左侧后文字仍正向），底层露出 target right；向后翻 source left，背面为 **target right**。不能把旧页镜像当作背面、把两个 target page 随意交叉。target page IDs 来自同一 PagePlan，末尾空白面按 P2 的奇数页规则处理。

Backward：
- 镜像，让 source 的 **left sheet** 向右翻回。

不要引入一个“半翻完时 pageIndex+1 的中间正式业务状态”。

### Pure state

纯值 `PageTurnState` 至少表达：

- source spread ID/index；
- target spread ID/index；
- direction forward/backward；
- stable/no transition；
- required monotonic transition generation/identity used to reject stale animation completion；every new target transition increments/replaces it。

它不包含：
- timer；
- current tick；
- practice step；
- parser/score data。

### SwiftUI transition

Use:
- visionOS 的 `perspectiveRotationEffect`（本机 SDK 中带 perspective 的旧 rotation3DEffect overload 已 deprecated）；
- perspective；
- page shadow；
- front/back surface；
- center gutter anchor。

使用 SwiftUI `withAnimation(...completionCriteria:..., completion:...)` 的实际动画完成回调，不用 Task.sleep 猜持续时间；原生 completion API 已核对本机 SDK。completion 同时核对 transition generation 与 score/page-plan identity，避免换曲后相同 spread index 被旧动画回写。

显式放大阅读直接显示同一 PagePlan 的目标双页。

Do not:
- build RealityKit mesh；
- deform page vertices；
- add CADisplayLink/timer；
- pre-render page bitmap solely for animation unless SwiftUI snapshot proves absolutely necessary and is documented; default is live page surfaces。

### Correctness under rapid target changes

If target changes while turning:
- cancel/supersede old transition；
- converge to newest spread；
- do not queue all intermediate spreads；
- completion from stale generation must not overwrite newer target。

固定最小策略：静止时相邻目标做一次翻页；大跨度跳转直接到最终目标；翻动中再次 retarget 立即终止旧过渡并直接显示最新目标，不排队也不积累页层。same target 不重新开始；close/reset/new score 或 page-plan identity 变化直接显示合法 target 并清 transition。只保留当前/目标所需有限页层，不保留截图历史缓存。

### Tests

- stable；
- forward；
- backward；
- same target = no transition；
- first/last boundary；
- rapid target replacement；
- stale completion discarded；
- no unbounded retained page layers。
- forward/back front/back 页码与文字朝向；奇数末页空白；放大阅读；score reset 时旧 completion 被拒绝。

### Cleanup in this task

No old code should need compatibility cleanup here. If a temporary transition wrapper is introduced during implementation, remove it before this task commits.

### Gate

- Notation page-turn tests；
- preview visual inspection；
- 共享 production Spread（至少 Practice 的已有 tick 切页）已使用该过渡；不以纯 state tests 替代真实 consumer；
- `make build:simulator`。

**Atomic commit:** `feat: P3-T1 - 建立通用单页翻动`

---

## P3-T2 Library preview 接入手动翻页

### P3-T1 实施与验证（2026-10-01）

- 共享生产 Spread 当场接入 pure turn state 与 live sheet view；身份为正式 song/revision + 当前 page IDs，generation 仅用于过渡。相邻一次翻动、跳页或翻动中 retarget 直接收敛；same target 保持，reset/非法目标/显式放大清 transition。SwiftUI 原生 `.removed` completion 核对完整 transition，不引入任务计时器或快照缓存。
- 原生 gutter hinge 使用半 gutter 的有限纸容器，避免旋转后偏移整条 gutter；back 面绕 Y 反转后随纸旋转，文字不镜像。正常/显式放大共用 PagePlan。早先附加的专项语义层已按产品决定删除。
- 已核对 SDK visionOS perspectiveRotationEffect 与官方 withAnimation completion 契约；前者不可用于 macOS，Core 的 macOS 验证只用对应平台原生 rotation3DEffect。
- package 255/255（新增 2 个有限状态测试）；native 2/2：`.build/TestResults/PageTurn-T1-1790803699.xcresult`，动态采样 early/middle/end 确认真实动画而非瞬移，rapid retarget 与放大直接收敛。Visual 4/4：结果路径 `/tmp/happy-p3-t1-visual-path.txt`，原两项 goldens 不变。ImageRenderer forward/back 0.25/0.75/end 已目视检查；end 与 upright target 像素相同，临时导出已删除。
- `make build:simulator` PASS：`/tmp/happy-p3-t1-build.log`；docs/data-flow 已同步。Frame progress 必须为 nonisolated 纯 Double 以满足 Swift 6 Animatable 契约；未使用 unsafe 隔离。

**Goal:** Book Flow 打开的动态 Book Spread 可以自然浏览整首谱。

### Files

Expected:
- Update: `LibraryScorePreviewViewModel.swift`
- Update: Library Book Spread detail view created in P2-T4
- Add/Update Library tests

### State ownership

Library preview owns only:
- current target spread index for the currently opened prepared score。

It does not own:
- page plan；
- notation facts；
- duplicate page models。

On a new score:
- ready 首次展示时，若已有匹配 selection identity 与 prepared scoreRevision 的 snapshot resume 且命中真实 measure，则从该 resume spread 打开；否则 spread 0。
- 不自动跳 focus；迟到的 history reload 可更新标记，但不能夺走用户已浏览的 target。
- close/非 active scene 取消并清 prepared/navigation，遵守 P2-T4；reopen 用同一上述规则，不额外存一份“上次浏览页” JSON。
- next/previous 只在合法页内 clamp；身份失效不 clamp 到另一个 score 掩盖错误。

### Interaction

Current Window foundation should use a minimal spatially sensible interaction:

- gaze + pinch / tap on outer right page edge -> next spread；
- gaze + pinch / tap on outer left page edge -> previous spread；
- optional small page-corner affordance attached to the page itself；
- no persistent bottom toolbar；
- no generic Next/Previous button panel。

命中区用带文本标签的 Button，点击/凝视+pinch 不是 onTapGesture 的别名；页缘大小与窗口缩放保持可点。关闭控件贴近乐谱，返回当前 selection；不为 preview 新开窗口或重建外层 SongLibraryView。

Avoid a horizontal free-scrolling gesture that makes the Book Spread feel like the old continuous score strip.

### Relationship to Book Flow

While detail is open:
- Book Flow selection remains the song identity；
- Book Flow does not continue scrolling underneath and change the opened score；
- closing detail returns to the same selected folio。

No second selectedSong state.

### Audio audition

Page navigation does not affect preview playback state.

`LibraryNowPlayingBar` remains the audition owner.

### Tests

- open score -> spread 0/resume target；
- next/previous；
- first/last clamp；
- close/reopen same selected score policy explicit；
- score change resets/clamps navigation；
- preparation generation replacement cannot leave stale spread index；
- audition unaffected。

### Manual Simulator acceptance

- right page edge advances；
- left edge goes back；
- one visible sheet turns；
- no toolbar；
- no old horizontal scroll strip。

**Atomic commit:** `feat: P3-T2 - 曲库接入手动翻页`

**Gate:** preview/annotation/history late-response 与 page-turn targeted tests、`make build:simulator`，实际 Simulator 页缘/关闭回同一 selection 验收。

---

## P3-T3 Practice navigation tick 驱动自动翻页

### P3-T2 实施与验证（2026-10-01）

- Preview owner 仅增加 targetSpreadIndex，ready 一次性从现有 snapshot closure 读取精确 resume occurrence；核对 selection song/fileVersion、prepared revision、正式 occurrence/page query。前后边界 clamp，close 清零，显式 reopen 重新准备；晚到 overview 不再请求导航，focus 永不自动跳。
- snapshot 原丢失 occurrenceIndex 的 resumeSourceMeasureID API 与所有 consumer/test 全部删除，改为完整 resumeOccurrenceID；resume annotation 也只标精确 occurrence，不能错误标同 source 的其他 repeat。
- 外页缘 native labelled Buttons + adjustable action，共用 VM turn；正常页缘预留平台 padding，不遮挡墨迹，不增加 toolbar/横向滚动，也不重建 audition。
- 7 参数 initial-policy 实际全部通过：匹配/缺历史/错 revision/错 fileVersion/错 song/同 source 外来 occurrence/focus-only；覆盖边界、close/reopen、late snapshot 不夺页、试听持续。Snapshot 测试保留 occurrenceIndex=2 的完整值，验证不再丢失编号；原 cancellation/rapid/version/error/history/reset 边界复跑。
- 初始定向选择中旧 annotation 名称未命中，实际 1 个参数化测试（7 cases），不冒称 2 个。枚举后扩大 51/51；最终含 native Root 52/52：路径 `/tmp/happy-p3-t2-final-path.txt`，日志 `/tmp/happy-p3-t2-final.log`。capture native 1/1，真实 simctl `/tmp/happy-p3-library-page-edges.png` 已目视确认 3/4、外缘控件与试听条；移除 capture cue/wait 后重跑最终集。
- build 日志 `/tmp/happy-p3-t2-build.log`；docs/data-flow 同步。真实页缘点击在 P3-T4 汇总，不把 VM turn 当 UI 点击证据。

**Goal:** 加固 P2-T3 已接通、P2-T5 已验证的 discrete `notationNavigationTick` 到共用动画层的行为，不另建 navigation owner。P3-T1 已挂载过渡，此任务负责实际 transport/快速导航边界，而不是第一次让组件进入生产。

### Files

Expected:
- Update: `GrandStaffNotationSpreadView.swift` or a thin host wrapper
- Update: `PracticeStepView.swift`
- Update: Practice tests

### Rules

1. Compute:
   `targetSpread = pagination.spreadIndex(containingTick: notationNavigationTick)`

2. Same spread:
   - no animation；
   - highlight updates only。

3. Next spread:
   - forward page turn。

4. Previous spread:
   - backward page turn。

5. Jump across multiple spreads:
   - converge directly to final target；
   - 按 T1 策略直接替换，不播放跳过页的翻动；
   - do not animate each skipped spread。

6. Session/song reset:
   - reset transition generation；
   - show target spread directly if carrying prior animation would be misleading。

7. Active range changes:
   - may change target tick/spread；
   - do not recompute pagination identity。

### No second clock

Do not add:
- Timer；
- playback polling；
- scroll schedule；
- display link。

The existing Practice session remains sole time owner.

### Tests

- manual step next within same spread；
- manual step crosses spread；
- backward retry；
- autoplay crossing spread；
- large jump；
- resume target；
- session reset；
- rapid navigation updates；
- stale transition completion discarded。

### Gate

- targeted Practice/Notation tests；
- `make build:simulator`；
- Simulator manual/autoplay/resume crossing real page boundary。

**Atomic commit:** `feat: P3-T3 - 练习位置驱动自动翻页`

---

## P3-T4 final real validation

### P3-T3 实施与验证（2026-10-01）

- T1 共享 Spread 已在真实 PracticeStepView 的 full input→PagePlan→discrete tick consumer 中生效。本任务不改同一已正确 consumer，也不新增 host/clock，仅增加已接入链路的回归。
- dense 512 steps 正式 PreparedPractice 测试贯穿安装→manual skip 同页→真实 moveToStep 跨页→retryMeasure 向后→重新应用 full passage→大跳→快速替换→reset/new song。完整 PagePlan/buildCount 在导航/range 下不变；换谱 page IDs 相同也由正式 song identity 拒绝旧 completion。
- 既有 controlled sequencer rest-boundary 测试继续走真实 transport/poll service，并接入同一 turn state，确认无 guide 时向前翻页，暂停迟到 sample 不换目标；真实 progress 恢复的 3 参数场景首次目标直接显示末双页。
- 初始新测试编译暴露嵌套 #require 的 Swift macro 限制与 reset API 名称错误，仅修正测试表达及使用实际 resetSession；未新增业务 workaround。
- 定向 3/3（包括真实 native shared Book）：路径 `/tmp/happy-p3-t3-specific-path.txt`，`/tmp/happy-p3-t3-specific.log`；扩大 Gate 与 build 的最终日志 `/tmp/happy-p3-t3-wide.log`、`/tmp/happy-p3-t3-build.log`。先存示范手失败仍单独隔离，不混入通过数字。

**Goal:** 完成翻页主功能的真实验收。用户另行授权全项目删除系统辅助模式专用代码、测试和要求，并统一系统语义字体；相关实际验证另记。

### Navigation readability

Book/page navigation and current focus cannot rely only on:
- green/amber；
- opacity。

Keep geometric/textual state.

### Real validation

Run:

1. Book Flow scroll/selection；
2. open real dynamic score；
3. manual Library page turn；
4. close/reopen；
5. Practice manual progression；
6. autoplay crossing page；
7. backward/retry。

### Tests / build

- targeted Notation + Library + Practice；
- package tests；
- `make build:simulator`；
- full simulator test target when practical；
- if full target has pre-existing failures, record exact failing tests and do not misattribute them to this feature。

命令与报告隔离遵守 P2 的“验证命令规则”：用实际 discovered IDs，确认非零测试；package macOS 通过不是 Simulator 通过；不覆盖旧 result bundle、不关掉用户已有 Simulator。最终验收不能拿本轮审查的 238 个现有 package tests 当新功能通过证据。

### Cleanup rule

P3-T4 删除用户明确取消的 P1–P3 专项功能；除此之外仅清理 P3 自身代码。

It must **not** be the place where we finally notice:
- Vinyl old code；
- old scroll schedule；
- old viewport view；
- old context helper。

Those must already have been deleted in P1/P2.

### Docs

Update `docs/testing.md` only with actual evidence from this execution.

### Phase completion checklist

### P3-T4 已验证部分与剩余验收（2026-10-01）

- 将全部 4 个会替换同一 key window 的原生测试归入 `NativeBookWindowTests @Suite(.serialized)`，不将普通业务测试串行化。真实日志证明 Swift Testing 顶层任务仍可能重叠，即使 Xcode 单 destination / parallel-testing NO；无保护地交叉替换和 defer restore 同一 window 会破坏验收对象。由共享资源拥有者收敛，不新建窗口/设备，也不加测试延迟绕过竞争。
- 新增 same score 的 page IDs 改变、空 plan、奇数末页 blank-underlay 检查；live 正反面、动态图像变化、rapid retarget 继续成立。旧专项语义层已删除。临时输出/capture waits 均已删，纸面实现只有排版事实与有限 presentation，无 timer/bitmap/debug 分支。
- 最终 Gate **174/174（1 serialized suite），0 failed/skip**：`.build/TestResults/BookFlow-P3-final-gate-1790804759.xcresult`，`/tmp/happy-p3-final-gate.log`；逐 discovered IDs `/tmp/happy-p3-final-enum.txt`、`/tmp/happy-p3-final-ids.txt`。最终 package **256/256**，96/69/10/17/43/21：`/tmp/happy-p3-final-package.log`；最终 build PASS：`/tmp/happy-p3-final-build.log`。
- 真实完整 target **1050 passed / 12 failed / 0 skipped（1062 total）**：`.build/TestResults/BookFlow-P3-full-1790804842.xcresult`，`/tmp/happy-p3-full.log`。失败中 11 个 test ID 与 `3ba1f4e` baseline 完全一致：bothPackagedHandRigsMatchTheAuthoredSkeletonContract、builderAddsAValidatedPreparationFrameBeforeTheFirstOnset、builderCreatesOneDeterministicClipPerPlannedHandOffMain、builderKeepsHeldFingertipsOnTheirKeysDuringTheNextAttack、builderLiftsThePalmByOnlyTheRequiredKeyboardClearance、builderValidatesThePublishedSkeletonAtTheContactPoint、handMotionCorpusMeetsCoverageTimingAndContactGates、handRigLoadsPackaged21JointAssetAndAppliesClipFrame、hidingTeacherHandsImmediatelyRestoresKeyboardHighlights、localSamplerPauseResumeAndPlaybackRateUseTheSameSequencer、pianoDemonstrationHandsTimingDoesNotLeakTransportAcrossRestart。不能声称完整 target 通过。
- 新首次观察的 recorderSemanticEventsReturnBeforeSlowPersistenceCompletes 用 20 次 yield 而非完成信号采样 Task；test 与 PracticeSessionRecorder 实现相对 baseline diff 零。追踪 setGuiding/setSettingsPresented→startPendingRecordPersistence：semantic 方法返回不等待 gated IO；定向 1/1 通过：`.build/TestResults/Recorder-Observed-Failure-Probe-1790805009.xcresult`，`/tmp/happy-p3-recorder-probe.log`。证据支持调度敏感的既有测试，不将“复跑成功”当修复，也不改无关 recorder/rig 或扩大授权范围。
- UI capture 已查看 P1 Flow、T2 实际 Library 第 3/4 页外缘控件、T5 实际 Practice 手动/恢复/休止跨页；用户已确认 P1 人工滚动。最终现有 AVP 已安装最新 App 并启动正常 Library，`/tmp/happy-p3-final-user-library.png` 已检查，没有新设备/关闭服务/删除数据。
- **仍缺真实页缘点击人工确认**。Peekaboo 本地/精确 PID/刷新均无法识别 Device Hub 的稳定窗口代；已通过官方实际 DeviceHub.app 后台打开既有界面，booted device 仍只有指定 AVP，但工具仍报 SNAPSHOT_STALE/WINDOW_NOT_FOUND。不宣称该人工验收或 P3 Gate 已完成；产品取消的专项验收不再等待。
- docs/testing 与 docs/data-flow 均同步真实验证边界；旧符号 scan/diff check 零（macOS 原生旋转适配并非 visionOS deprecated 路径）。计划文件保留本地，不加入代码提交。

Verify:

- page-turn layer is presentation only；
- Library and Practice share it；
- no timers/scroll runtime reintroduced；
- 放大阅读使用同一 page plan；
- no feature flags / compatibility aliases remain；
- no debug/preview code leaked into production path。

**Atomic commit:** `test: P3-T4 - 收口 Book Spread 翻页验收`

## 用户追加的全项目清理与字体统一（2026-10-01）

- 删除全项目专用语义修饰符、描述器、模式 environment、参数、状态、动态分支、专项测试和 golden；清理活跃与归档计划的过时要求。普通 Button 文案、正常手部/钢琴动画、显式放大阅读不属于删除对象。
- 全仓业务源码、测试、资源与文档扫描零残留；SwiftUI `.font(.system(...))` 为零。界面用系统语义字体，谱内文本从原生 caption 解析并按 staff-space 缩放，测量与绘制共用 metrics；Bravura 音符字体保留。
- 同步删除墨迹服务中仅供旧菱形标记使用的 0.78 staff-space 预留方框；不留下换名字的兼容路径。
- macOS package 257/257，`swift test --package-path Packages/HappyPianistCore --triple arm64-apple-macosx26.0`，`/tmp/happy-cleanup-final-package.log`。初次未指定 triple 的命令因 package 未声明 macOS deployment 而默认 macOS 12 不通过，未改项目正式 visionOS 平台声明来绕过。
- 字体变化更新标准 golden：尺寸 351×229 不变、采样墨迹 1083→1084。首次扩大验证有一次 native 进程 signal kill；没有断言失败或内存终止证据，单独原生复核 5/5 通过，再跑扩大集和最终源码集通过；没有增加延迟或生产恢复补丁。
- 最终源码实际 AVP Gate 191/191，0 failed/skipped，`.build/TestResults/Project-Cleanup-Verified-Gate-1790832767.xcresult`，`/tmp/happy-cleanup-verified-gate.log`；使用实际 discovered IDs（`/tmp/happy-remove-all-a11y-ids.txt`），含 4 个 serialized native。
- 这次追加清理的自动化已完成；原 P3-T4 真实页缘点击确认仍缺，不用 VM 调用冒充。P4–P6 未执行。
- 最终 build PASS：`make build:simulator SIMULATOR_ID=28DABA38-C30B-44B1-9C2B-65D50F7FCC55`，`/tmp/happy-cleanup-final-build.log`。
- 最终完整实际 target 1048/1059、11 failed、0 skipped，`.build/TestResults/Project-Cleanup-Full-1790832858.xcresult`，`/tmp/happy-cleanup-full-summary.json`、`/tmp/happy-cleanup-full.log`。11 个失败 ID 全部匹配之前完整记录及初始基线；没有新增失败，Recorder 本轮通过但未改实现，不宣称已修复。
- 完整测试末尾 Xcode 自己的 simctl diagnose 诊断采集卡住；确认 PPID 属于本轮 xcodebuild 后仅停止该采集子进程，保留实际测试结果并完成 xcresult；未停止测试、重启共享服务或关闭设备。
