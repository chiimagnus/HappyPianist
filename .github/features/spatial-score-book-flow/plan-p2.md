# Plan P2 - 真正的 Book Spread 分页曲谱

**Goal:** 一条真实路径完成 `score-level engraving → system → page → spread`，同一组组件服务 Library 预览和 Practice。

**Visual acceptance references:**
- `.github/features/spatial-2026-09-30/设计稿/images/02-双页Book-Spread曲目详情.png`
- `.github/features/spatial-2026-09-30/设计稿/images/04-正常练习.png`（仅双页谱的信息密度、谱面结构和练习中当前位置表达）
- `.github/features/spatial-2026-09-30/设计稿/images/08-练习结果与重练.png`（仅 stable / learning / resume / focus / results-on-score 的谱面信息结构）

P2 负责让这些谱面关系成为真实动态 notation；当前 Library/Practice Window 与键盘/设置/Immersive 生命周期仍保留，不声称完成 world-lock、空间控制或最终练习场景。

**Non-goals:** 不做 PDF/bitmap、第二 parser、出版级自动美化、旧横向兼容模式、RealityKit mesh/page curl、piano calibration 或 AR Guide 重构。

**Approach:** 先把当前 viewport-coupled engraving 拆成唯一 score-level absolute layout，再用一次有停止条件的几何探索冻结 canonical page/system 约束；随后在同一条 production pipeline 上交付 pagination + Spread，并分别接入 Practice 与 Library preview。

**Rules:** page/system identity 只由 score facts + canonical page geometry 决定，不由当前 tick、active range 或宿主像素尺寸决定；Library/Practice 共享同一 pagination owner；新路径接入时同步删除旧 viewport/current-context/continuous-scroll 路径，不保留兼容模式。

**Phase acceptance:** 一页能真实容纳多个 Grand Staff systems；Library 与 Practice 对同一谱面得到一致页码；现有记谱/a11y 能力不回退；旧 continuous notation scroll runtime 退出 production。

## 执行顺序与接入边界

- T1：新 engraving/slice 当场替换旧 View 背后的唯一管线。
- T2：验证 canonical 几何与可读性，交付参数和实验记录；不提交无人使用的生产分页 API。
- T3：分页模型、renderer 和 Practice 真实 consumer 是一个闭环；旧 View/context/scroll runtime 在此任务删除。
- T4：Library detail、preview preparation、历史标记与旧 UI 删除是一个闭环。
- T5：验证新的 Practice 范围/恢复/transport 生命周期，不能承担 T3 遗留清理。

这样不再出现“先创建几个新文件，后面的 task 才接入”或“先删 helper、旧 caller 还要再等两个 task”的阶段断裂。

---

## P2-T1 拆分并接入 score-level engraving / system slice

### 已核对的入口和职责

`GrandStaffNotationView → GrandStaffNotationPresentationViewModel.makePresentation → GrandStaffNotationLayoutService.makeLayout → GrandStaffHorizontalSpacingService / GrandStaffChordLayoutService → GrandStaffNotationRenderer`。

旧 makeLayout 同时解析完整 source facts、排版、按 scrollTick 居中/裁剪及烘焙 highlight；makePresentation 在每次渲染重复全谱工作。必须拆开，但不能保留两条 production layout 路径。

### Files / 源码锚点

均为 `Packages/HappyPianistCore/Sources/Notation/`（除另行标注）：
- Add: `GrandStaffNotationScoreLayout.swift`、`GrandStaffNotationScoreLayoutService.swift`、`GrandStaffNotationSystemLayoutService.swift`；单实现不另建协议/工厂。
- Update: `GrandStaffNotationModels.swift`、`GrandStaffHorizontalSpacingService.swift`、`GrandStaffNotationPresentation.swift`、`GrandStaffNotationPresentationViewModel.swift`、`GrandStaffNotationView.swift`。
- Delete: `GrandStaffNotationLayoutService.swift`，本 task 迁移所有生产、package tests、AVP visual tests caller。
- 现有布局/spacing/golden tests 与 `HappyPianistAVPTests/Notation/GrandStaffNotationVisualTests.swift` 同步迁移。
- Update: `Packages/HappyPianistCore/Sources/HappyPianistTestFixtures/Resources/Fixtures/PianoPerformanceKnownDeviations.json` 中指向被重命名/拆分 notation test 文件的路径；不要为了保住 fixture 字符串而留下旧测试文件或 service alias。
- Update: `docs/data-flow.md`。

Host 同任务接入正式映射：`HappyPianistAVP/ViewModels/ARGuideViewModel.swift` 的 applyPreparedPractice、`HappyPianistAVP/ViewModels/Practice/Session/PracticeSessionViewModelCommands.swift` 的 install/clear、`HappyPianistAVP/ViewModels/Practice/Session/PracticeSessionHostState.swift`（或最小共享 runtime score facts）、`HappyPianistAVP/Views/Practice/Step/PracticeStepView.swift` 及直接 tests。T3 消费这个已接通的映射，不等后续任务才补输入。同步更新 `HappyPianistAVPTests/Support/PracticeSessionViewModel+TestConvenienceInit.swift` 的 synthetic fixture，让其明确构造 formal part/staff facts；不为旧测试留下 production 缺映射兼容模式。

### 实施步骤

1. 先建立无 overlay/active-range/scrollTick/像素依赖的 immutable absolute score layout；x 使用 staff-space。保留 notes/rests、accidental、chord/stem/beam/ledger、attribute/marks、已配对 spanners、所有真实 measure boundary 和完整 ink extents。
2. 输入包含完整 projection/measure spans 及明确的 original part/staff → displayed grand-staff 映射。沿用 `PreparedPractice.scoreContext.logicalInstrument` 和 structural part 事实，不复制 normalizer 或从首个 note 猜；空休止 system 也必须有上下文。
   本轮进一步核对：`ScoreNotationProjection.init` 已消费 logical instrument 的 `grandStaffPartAssignments`，其 SourceNote.staff、marks 与 attributeChanges 已是显示谱表编号，不能再次映射。正式 instrument/structuralPart facts 从 preparation 接到 runtime/notation，供身份、完整小节边界与 local context 查询使用；不会新增第二个 normalizer。
3. 使用 spacing 的独立 `barlinePositionsByTick` / `attributePositionsByTick` / `rhythmicPositionsByTick`。不把 `position(at:)` 的末端节奏 clamp 当成真实小节终点；首小节起点不得延续旧 viewport 的丢弃策略。
4. Beam 数据保留 source vs meter-derived provenance 和完整 source group membership，不解析 id 字符串判断来源。explicit beam 跨 staff/measure 的语义不能被 viewport clipping 掩盖。
5. System slice 接受明确的 absolute x/tick 区间与局部 context，再映射到 renderer 的局部坐标；应用 highlight、剪切 spanner 并产生 continuation。范围只 dim 非活动内容，不删除小节结构或改变系统高度。
6. 当前 View 立即用新 score owner + system slice；旧 viewport 的导航方式暂留到 T3，但 engraving 只有一套。给现有公开 View 的源码事实输入及所有 caller 同步更新，不能为了 T3 延后接入。
7. 绝对 engraving 非主 Actor 构建，ViewModel/owner 只编排异步任务和发布结果。按 score identity（包含正式 source facts/映射）管一个当前值；关闭/换谱取消，过期 generation 不回写。必要的值类型显式 Sendable；不靠 `nonisolated(unsafe)`。projection 为空时是明确 loading/no-score，不编造 PreparedPractice fallback。拆分后的 `Notation → Practice → MusicXML` 包依赖保持现状：最小来源映射事实属于现有 source/runtime 层，Practice Core 不可反过来 import Notation 的 PagePlan/UI 类型形成循环。
8. overlay/tick/hand/range 变化只更新局部 presentation；测试不仅比对 x 相等，还证明没有第二次全谱构建。无全局 cache、无第二套 file/progress storage。
9. 删除旧 service/API/helper/tests，本任务 build 后不存在老/新双轨。

### 验证

迁移所有现有 notation tests（source/fallback beam、written rhythms、cross-staff chord、accidentals、repeat/performed occurrence、rests、tie/slur/nested tuplet、unsupported placeholder）。新增：
- overlay/range 改变绝对布局不变、构建次数不增加；
- 首/末/纯休止小节与多 staff 的 measure 边界完整；
- 单 part 双 staff / 双 part 各 staff=1 映射及空 system；
- stale/cancel 绝对布局不能覆盖新 score。
- AVP 原 golden 在同等旧 viewport 参数下保持事实/视觉 parity；不随意改 hash 消除回归。

**Gate:** Notation package tests + AVP notation/glyph/a11y tests + `make build:simulator`；package 测试不能替代 Apple target。

**原子提交:** `refactor: P2-T1 - 拆分并接入谱面绝对布局`

### T1 本轮取证

- 旧 service / caller 迁移后，Notation 58 项通过（`/tmp/happy-p2-t1-full-notation2.log`）；新增完整边界、rest-only、split-part 正式映射、跨小节 source beam provenance、右边缘 closing marks、墨迹/极端谱字与缩放不变回归。
- AVP 初轮 23 项真实测试：22 passed，只有 standard visual hash 不同（`.build/TestResults/ScoreLayout-P2-T1-1790782500.xcresult`）。失败后的诊断收集另超时 600s，不等于测试未运行。
- 临时 parity 实验只在测试中移除新增加的首小节边线；标准图逐像素 hash 恢复为原 `026e009a…`。含首边线的 hash 为 `1e5476dd…`，可访问图仍是 `708c390b…`。实际检查导出 PNG；未盲刷 golden。实验 6/6（`.build/TestResults/ScoreLayout-P2-T1-parity-1790784122.xcresult`）；实验代码已当场删除。
- 完整墨迹包含 notes/rest/dots/accidentals、ledger、stem/flag/beam、曲线/嵌套 tuplets、marks/inline attributes。beam 的 canonical bounds 与 renderer 复用同一 geometry；glyph metrics 由仓库 Bravura.otf 的 CoreText bbox 实测补齐。曲线采用包含控制点的保守包围盒，文字使用 CoreText shaping；不是固定 8-beam padding。
- 后续正式 Gate 与提交已完成，以下记录是实际完成证据；临时 parity 实验已删除。
- 最新 package 全量 245/245（`/tmp/happy-p2-t1-full-package.log`）；正式 AVP 扩大集 72 项已运行，71 passed / 1 failed（`.build/TestResults/ScoreLayout-P2-T1-final-1790784471.xcresult`），失败为 `pianoDemonstrationHandsTimingDoesNotLeakTransportAcrossRestart()` 的 `rejectedOccurrenceIDs.isEmpty`。历史 `.build/TestResults/HappyPianistAVP-Simulator.xcresult`（1022 passed / 11 failed）含同 ID/同断言失败；本任务没有改 clip builder/rig/contact pipeline。保留已知失败，不把扩大集冒称全绿。
- Gate：增加 synthetic source/structural part 一致性回归后，72/72 定向 AVP tests passed / 0 skipped（`.build/TestResults/ScoreLayout-P2-T1-gate-1790784934.xcresult`，`/tmp/happy-p2-t1-gate-test.log`）。此集不含刚刚实际复现的先存示范手失败。`make build:simulator SIMULATOR_ID=28DABA38-C30B-44B1-9C2B-65D50F7FCC55` passed（`/tmp/happy-p2-t1-final-build.log`）。旧 service / alias scan 为零；source facts 不再折叠非法第三 staff。提交 `fad08f07804767374717425061053626b1f021d6`。

---

## P2-T2 建立 deterministic pagination 的几何验证（探索）

**交付物:** 本节内记录经过测量的 canonical page 参数、支持的宿主最小尺寸与显式放大阅读策略，供 T3 实施。不是先提交孤立 PaginationService。

### 为什么先验证

当前 Practice notation 至少 350 高、下方有 88 键；旧 viewport lineSpacing 固定 clamp 到 8…22，header 固定 7 staff-spaces，requiredHeight 不含完整 rests/tuplets geometry。直接缩成两页可能无法读谱，或和 header/标记相撞。相同分页不等于可读性已满足。

### 方法与停止条件

1. 用 T1 的绝对布局和 renderer 做最小临时排页实验；实验文件只放本 feature 本地目录，不新增永久 production helper，也不引入依赖。若临时改测试/生产代码，实验结束当场还原该实验改动。
2. 输入使用现有 notation fixtures、真实 bundled scores，以及长休止、极端音高、嵌套 tuplets、7 升/降调号、跨小节 beam；用 ImageRenderer 测 ink bounds，另在 Simulator 观察真实宿主。
3. 以 staff-space 定义 page aspect、内边距、系统内容宽/页容量、system gap、gutter 与 header extents。禁止固定系统数；普通 resize 不进入分页 identity。
4. 普通显示等比放入同一 spread。显式放大阅读不另排谱：同一 canonical layout 放大并允许纵向阅读；不得复活水平连续滚谱。文字/control 用系统语义字体，谱字不能被旧像素 clamp 再次改大小。
5. 若双页在最小宿主无法读，先调整本 feature 的内容最小尺寸/notation 高度分配（保留现有键盘），而非偷偷只显示一页、缩到无下限或另开一种分页。具体最小值由实验记录确定，不预填虚假通过。
6. 普通 measure 只在 measure boundary 换 system；cross-measure explicit beam 的连通组不可切。
7. 超宽 measure/group：独占 system，以 `min(1, availableWidth / completeInkWidth)` 对该 system 均匀缩放，包含 header 与全部 glyph/beam；记录所得 scale。支持显式放大查看，不能以“轻微超宽”裁掉乐谱。超高 system 同样独占 page并按完整二维 bounds fit，不能溢出覆盖下一行。不新增递归 fallback 树。
8. 超宽/超高样例必须实测，记录最小 ink spacing 与放大后的可读结果；若实际不可读且不能通过宿主/放大解决，停止 T3 并记录具体失败样例/约束，不标为设计已成立。停止依据是证据，不是无限微调。

### 固定的数据规则（无需实验猜测）

- Pages 顺序从 0，spread=`[page 2n, page 2n+1]`；首 spread 左为第一页，奇数末页右为空，无音乐/历史语义。
- 音符/rest onset 与 navigation 采用 `[startTick,endTick)`；恰好小节起点属于后一个 measure/system/page。完整 score 终点归最后页；域外 tick query 返回 nil，不用无声 clamp 掩盖无效 session。
- 小节末的 ending stop/backward repeat/final barline 属于前小节右边缘，不能按 onset 规则被后一个 system 吞掉；起始 repeat 属于后小节左边缘。两侧普通边线可为版式重述，源结构事实不重复。
- 每个 measure occurrence 恰好属于一个 system/page；别用 printed number token 作为唯一 ID。sourceMeasureID 只用于历史来源关联。
- 每个 system start context 是 local part/staff 的 timeline 查询（含 tick==start 的 changes）；同一 source attribute 在 header 已重述时不再重复 inline；中途 changes 仍原样出现。
- 大小/颜色/overlay、hand、范围、当前 tick/history/animation 均不改变 page plan。

### Gate / 证据位置

在本节追加实验输入、实际 host 尺寸、canonical 参数、像素/放大结果与未解决样例；不要改 `docs/testing.md` 写未经运行的通过。
T3 必须等待本实验成立；本 task 没有永久代码，因此无强制 Git 提交，feature 文档按忽略规则不入库。

### T2 实测结论

- 使用正式 preparation `.practice` 与 T1 renderer：四首 bundled（Bohemian Rhapsody、Despacito、Awesome、Under Pressure）与七个 fixture，共十一谱。实验源码留在本目录 `geometry-experiment.swift`，已从测试 target 删除。
- 冻结 canonical 参数：page 52×73.5 staff-spaces，margin 3，system 可用宽 46/高 61.5，system gap 3，spread gutter 2。系统数按完整墨迹贪心装箱，不固定三行；source beam 连通组不切开，超宽/超高 system 二维 fit 并独占页。
- 四首真实谱为 45/30/9/34 页，首页各三系统；fixture 含纯休止、双 part、7 升/降、极端音高、跨小节显式 beam、40 层 nested tuplets。1180px 双页最小 staff spacing 为 5.87px（40 音 beam）；放大同一页到 1180px 后 11.96px，实际 PNG 音头/beam 完整、未裁剪。40 层高系统二维 fit 后 9.54px/放大 19.44px。不存在任意大输入的有限像素可读性保证，放大阅读保留完整系统并可调整宿主尺寸。
- 普通 spread 等比缩放，显式放大把同一 spread 的两页纵向排列并纵向阅读；不是重新分页/单页产品模式。控制文字用系统语义字体，谱字没有旧 8…22 clamp。
- 实际 AVP 现有设备窗口 `1240×1160`（已读取 native bounds），1180px 谱面与原 88 键同时可见。Practice min 1240×1160；Library preview min 1240×1000（无需键盘）。截图 `/tmp/happy-p2-t2-native-normal-captured.png`、`/tmp/happy-p2-t2-native-enlarged-captured.png` 已查看；放大截图保留键盘，谱面纵向阅读。
- 实际测试：首轮 1/1 passed `.build/TestResults/ScoreGeometry-P2-T2-1790785854.xcresult`；native geometry 1/1 passed `.build/TestResults/ScoreGeometry-P2-T2-native-1790787027.xcresult`。补采截图轮 `.build/TestResults/ScoreGeometry-P2-T2-capture-1790787169.xcresult` 在截图导出后进程 signal kill，不能称该轮通过；前两轮与实际尺寸/两模式截图构成几何证据。临时 UIKit root/size 操作只用于实验，不进入生产。

---

## P2-T3 交付多 system 双页谱并当场替换 Practice 旧路径

**Goal:** 从 full prepared score 到 Practice 中真实可见的 Book Spread，一次形成可独立验证的结果。分页服务、Page/Spread 和 consumer 同 task 接入，不等待 T5。

### Files / 接入链

Notation：
- Add: `GrandStaffNotationPaginationService.swift`、`GrandStaffNotationPagePlan.swift`、必要的小型 `GrandStaffNotationContextResolver.swift`。
- Add: `GrandStaffNotationSystemView.swift`、`GrandStaffNotationPageView.swift`、`GrandStaffNotationSpreadView.swift`。
- Rename/refactor: `GrandStaffNotationViewportLayoutService.swift` → `GrandStaffNotationSystemCanvasLayoutService.swift`，同步 tests/callers，不留 alias。
- Update: score/presentation owner、`GrandStaffNotationModels.swift`、`GrandStaffNotationRenderer.swift`。
- Delete: `GrandStaffNotationView.swift`（含旧居中/滚动 scaffolding），所有 package/AVP caller/tests 迁移。

Host：
- Update: `HappyPianistAVP/Views/Practice/Step/PracticeStepView.swift`。
- Update: `HappyPianistAVP/ViewModels/ARGuideViewModel.swift` 中 applyPreparedPractice、`ViewModels/Practice/Session/PracticeSessionViewModelCommands.swift` 的 install/clear。
- Update: `PracticeSessionViewModelPlayback.swift`、`PracticeSessionHostState.swift`、`Services/Practice/Playback/PracticePlaybackControlService.swift`。
- 必要的中性源码映射放在现有 `Packages/HappyPianistCore/Sources/Practice/Runtime/PracticeSessionRuntimeState.swift` 的 score facts，不迁入 UI 或 progress JSON。
- `Runtime/Autoplay/AutoplayTimelineTimeCursor.swift`、`AutoplayPerformanceTimeline.swift` 及直接 caller/tests 如需补 measure-boundary position 一并迁移。
- Tests: 现有 Notation tests、AVP visual tests、`ManualAdvanceStrategyTests`、`PracticeSessionViewModelTests`、`PracticeResumeLifecycleTests`、autoplay cursor/schedule tests。
- Docs: `docs/data-flow.md`。

### A. 唯一 pagination / geometry owner

1. 基于 T2 实测 canonical geometry，一次生成 score→systems→pages→spreads；只在 score identity/显式 canonical 参数变更时重建。构建在非主 Actor，Swift 6 value isolation 与 T1 一致。
2. system packing 使用真实 ink extents + 当前 header；纵向 packing 使用 renderer 同一 canonical bounds，包括 notes/chord、ledger/stem/beam、rests、fingering/articulations、全部 spanner/nested tuplet、marks、clef/key/meter。禁止固定 8-beam padding 冒充实际高度。
3. 所有 active-range 内容保留 geometry，只变淡/显示范围框；不能按当前高亮重新计算 staff bounds。删掉 canvas 无效参数、旧 8…22 像素 clamp、fixed header、旧 requiredHeight/scroll anchors，仅保留实际 rendering 非零尺寸等边界。
4. PagePlan 保留 occurrence IDs、每 measure 的局部 rect（包括空休止小节）、每 system context/bounds 与 page identity。header 实际 extents和 renderer 一致；7 升/降调号、C clef/换谱号不得碰撞第一音。
5. Context resolver 按 original part/staff 解析后映射显示 staff；每 staff 分别有 clef/key/meter。tone/accidental、页首 signature 位置与 inline facts 不能采用不同 clef 基准。
6. Tie/slur/nested tuplets/ending 按 slice 增加 local continuation，开始/结束/边界标记遵守 T2 归属；explicit beams 不拆来源组，fallback beam 仍按 meter、rest 和 measure 分组。未支持记谱依旧明确 placeholder，不默默丢弃。
7. Query 按 tick / occurrence 查询 system/page/spread，history sourceMeasure 查询通过 measureSpans；完成态终点和空页按 T2 固定规则处理。

### B. 动态 renderer / 纸面 / 放大阅读

- SystemView 只 slice 已有 score layout、应用瞬态 overlay、调用现有 renderer；PageView 垂直排真实 systems；SpreadView 同时显示两页和窄 gutter。不复制旧 viewport两份，不嵌套水平 ScrollView。
- Host 只按可用空间等比缩放 canonical pages；显式放大阅读按 T2 同一 plan 实现。
- 纸面使用低干扰浅象牙色与固定可读深墨色，不能让深色环境下 `.primary` 变白而消失；增加对比度/无色辨别仍有明确轮廓/标签。
- 页码/总页数、休止、unsupported、高亮/范围可读；annotations 与翻页 control 不仅靠色彩。

### C. Practice：传全谱与正式 source facts

- `applyPreparedPractice → installPreparedSteps → runtime → PracticeStepView` 传递 formal logicalInstrument/structuralPart mapping；无需保存整个 PreparedPractice 巨大副本。clear/install 同步清/换映射。
- 分页收到完整 `session.measureSpans` / projection/timeline，不用 `notationMeasureSpans` 的范围子集；删除该旧属性及仅为它服务的 tests/callers。
- Practice hand 只控制符号淡化，active range 只 dim/bounds/navigation，不重分页。
- Page plan 未 ready 时显示明确 loading/failure；不调用旧 renderer 当 fallback，也不让导航拿空 plan 猜页码。
- 保留键盘、反馈、toolbar/settings、prepared/practice 退出与保存、immersive 生命周期；仅按 T2 调整曲谱可读布局。

### D. 离散 navigation：复用唯一 transport

- 新 `notationNavigationTick() -> Int?`，当前有效步/范围完成态取最后有效步；invalid range/no score 返回 nil。manual next、resume/seek/retry 同步该导航事实。
- Autoplay 不“优先 currentGuide”：guide 会在休止期间停留。离散 position 由现有 transport schedule/cursor 发布，消费现有 scheduled tick，并覆盖完整 measure 起点以穿过无新 guide/step 的休止/长 tie。
- 现有 cursor 返回 event 而不带 tick，需调整为暴露 scheduled tick 的事实，直接 caller/tests 同 task 更新。若补 measure-position event，它属于现有 transport timeline；复用相同 tempo、lead-in、pauseSeconds/fermata 与 active-range/seek 规则，不另建 clock/polling/连续插值。
- 同 tick 事件全部处理后只发布最终位置，避免 guide 与 step 来回切页。Pause 保持位置；stop/error/clear/reset/换 session清理旧 generation；restart/seek 装新 schedule。
- P2 已能按 tick 直接切到正确 spread；P3 只把这种变化动画化，不能等 P3 才能浏览练习整首曲。

### Must-delete（在本 task，不是 T5 / P3）

- `GrandStaffNotationView`、`scrollTickProvider`、`DefaultScrollAnchorID`、`centeredForFirstOccurrenceID`、`defaultScrollAnchorY`、vertical ScrollViewReader/Task.yield 的自动居中。
- `currentGrandStaffNotationContext` 与仅其使用的 host clef/key helper。
- `PracticeSessionNotationGuideScrollPoint`、全部 `notationGuideScrollSchedule*`、`smoothNotationScrollTick`、`ensureNotationGuideScrollSchedule`、`notationViewportTick`。
- `autoplayTimingBaseTick` 当前只为旧 scroll 使用；改为必要的启动局部事实或新 position 初始值后删旧字段/reset/tests。
- 旧 API 的 wrappers、typealias、legacy flags 和已失效 tests。
- **不删** `autoplayTimeSchedule`、`playbackPositionSeconds/CapturedAt`、contact timeline/transport generation、`pianoDemonstrationTransportTiming`：它们仍驱动 Companion/demo hands，与 notation scroll 无关。

### 验证 / Gate

- 所有 measure occurrence 唯一覆盖；short/long、3/4/4/4/6/8、奇数末页、空休止、超宽/超高、起点/末点/域外 tick。
- 单/双 part + staff-scoped clef/key/meter；tick==system start 只重述一次；ending/repeat 右边缘不丢/重复。
- Cross-system tie/slur/nested tuplets、跨 staff/source beam、unsupported、完整 ink bounds。
- Library-sized/Practice-sized display 保持页界、overlay/range 不重建，唯一 score/page build 次数回归。
- AVP ImageRenderer：多系统页/双页、light/dark、header/continuation。
- 实际 Practice consumer 的完整 measureSpans 测试，而不仅测 paginator synthetic 输入。
- Autoplay long rest/tie、same-tick step/guide、pause/seek/error/end，证明正确 tick→实际目标 spread，不只检查事件 emit。
- `make build:simulator` 与 Simulator 当前 highlight/manual/autoplay/resume；a11y/可读性未执行不得报通过。
- 全仓旧符号清理 scan；test filter 用 discovered 函数/suite IDs，不用文件名假冒 suite（visual tests 是顶层函数）。

**原子提交:** `feat: P2-T3 - 接入动态双页谱并删除旧滚谱路径`

### T3 本轮取证

- 唯一 PagePlan/异步 owner 已接入 PracticeStepView；整谱覆盖、逐 staff header、inline signature 真实墨迹、source beam 不切、曲线原音高 anchors、nested tuplets/ending continuation、空休止 rect 与 tick/occurrence location 查询形成同一管线。动态范围、hand、宿主尺寸不改页界；二维缩放系统独占页（含前页已有普通系统的边界回归）。
- 删除旧 View、viewport service/owner、当前上下文 helper、连续 guide-scroll 字段/函数/导航入口和 overscan；测试只保留显式 system slice，不保留旧 scroll/viewport 参数或别名。
- 完整 preparation→install→PagePlan 的 128 小节实测：手动跨 spread/末步完成、休止期间 guide 停留而 navigation 前进、pause/resume/stop、同一 input 只构建一次。额外复现并修复：暂停后迟到的 transport sample 不能推进页码；取消代的构建失败不能停掉新代。分别有可控 in-flight clock 和 late failure 回归。
- transport position 沿既有 schedule 发布，不加 clock；native MIDI 使用 MusicTrack 的正式 track-length 属性保留静音尾段，AVAudioSequencer.load 后验证真实 track length，不插入 dummy 音符。
- package 全量 252/252（6 targets：96/65/10/17/43/21），`/tmp/happy-t3-full-package-commit.log`。AVP 最终定向 71/71、0 skipped，`.build/TestResults/BookPagination-T3-pause-gate-1790798465.xcresult`，`/tmp/happy-t3-pause-gate.log`；仍明确排除 T1 已复现的先存示范手失败，未修 rig/clip。build passed `/tmp/happy-t3-build-commit.log`。
- 清理前 Native 显示测试 1/1 passed，`.build/TestResults/BookPagination-T3-native-final-1790797879.xcresult`。共享 Spread 的 ImageRenderer 证明 normal light/dark 页内像素一致；放大 ScrollView 不以 ImageRenderer 黑色结果声称通过，改在既有窗口实测。
- 真实设备截图 `/tmp/happy-t3-real-0.png`、`/tmp/happy-t3-real-1.png` 已查看：双页完整、放大纵向阅读完整。UIGraphics.drawHierarchy 单独出现的黑矩形未在实际 simctl 截图出现，属于 capture 边界，没有为它修改生产 renderer。补采轮 `.build/TestResults/BookPagination-T3-real-capture-1790797285.xcresult` 1/1 passed；导出/等待截图临时代码已删除。
- 正式 App 现有 debug route 打开 bundled Awesome 谱，截图 `/tmp/happy-t3-production-practice-ready.png` 已查看：23 页、右页多 system，当前高亮、键盘与底部控制保留；T2 实验页数不是 T3 实际 header/fit 下的页数。没有冒称自动 GUI 点击；Practice 深入生命周期与可见导航回归归 T5。
- 原有 source/glyph/layout golden 不变；geometry 仅更新共享 native signature extent 带来的 x-spacing，visual golden 改为完整 canonical system 尺寸（旧 800×320 会截放大系统），导出图片检查后更新；临时导出代码删除。`git diff --check` 和旧生产符号 scan 为零。

---

## P2-T4 Library 打开动态预览并替换旧历史 UI

### 已核对的真实链路

`HappyPianistAVPApp → LibraryWindowRootView → LibraryContentView → SongLibraryView`；owner 从 `LiveAppGraph` 注入。
谱面：`SongLibraryEntryResolver.resolve(songID:) → PracticePreparationService.prepare → PreparedPractice`。
历史：`SongLibraryViewModel.scheduleSnapshotLoad → repository.history 一次 → SongPracticeLibrarySnapshotBuilder`。

不复用 `PracticeLaunchViewModel`：它有 applicator/recorder/progress restore/write 副作用。Preview 只重用 resolver/preparation protocol，不新增 parser、repository 或通用架构。

### Files

- Add: `HappyPianistAVP/ViewModels/Library/LibraryScorePreviewViewModel.swift`。
- Add: `HappyPianistAVP/Views/Library/LibraryScorePreviewView.swift`；本 task 挂在 SongLibraryView 的内容区域。
- Update: `LiveAppGraph.swift`、`Views/HappyPianistAVPApp.swift`（含 debug capture）、`LibraryWindowView.swift`（Root/Content/init/previews）、`SongLibraryView.swift`、`LibraryBookFlow.swift`/actions。
- Update: `Models/Library/SongPracticeLibraryPresentation.swift`、`Services/Library/SongPracticeLibrarySnapshotBuilder.swift` 及其 focus/helper 中必要共享分类。
- Update: Notation 最小中性 measure-annotation API/renderer（如果 T3 尚无 overlay entry）。
- Tests: preview VM、composition/入口、snapshot builder、Book Flow confirm、历史恢复 UI；复用 `SongLibraryViewModelTestHarness` 的 fake 体系。
- Delete: `LibraryPracticeProgressOrnamentView.swift`、`LibraryPracticeEmptyAnimationView.swift` 与仅其使用的测量/私有 helpers。
- Update: `docs/data-flow.md`。

### Preview owner 与生命周期

1. 状态仅 idle/loading/ready/failure，身份复用 `SongPracticeLibrarySelectionIdentity(songID,scoreFileVersionID)`；generation 是异步请求隔离，不造第二 selectedSong。
2. resolver 返回最新 entry，因此 prepare **之前**核对 resolved entry ID/fileVersion 等于 requested identity；prepare **之后**再核对当前 selection+version/generation。只做后一层不能阻止错文件被标成旧 preview。
3. ImportedMusicXMLFile 三字段沿 `PracticeLaunchViewModel` 同样映射；准备 options `.practice`，written order、both hands。不用 reference/performed order，不增加两份非平凡转换 helper。
4. 最多保留当前一个 prepared/score layout。close/Library disappear/非 active scene 取消请求、清准备结果和 page target，重新打开重新准备；无永久 preview cache。active scene 继续复用现有 snapshot refresh，不静默重开 detail。
5. Library outer root/SongLibraryView 及 toolbar/importers 不因 Flow/detail 切换消失；只替换其内容。否则现有 onDisappear 会停试听/取消导入。detail 关闭回同一 selected folio，Book Flow 在 detail 下不接受滚动 selection。
6. 任何导入事务开始即关闭并取消 preview，直到既有事务 settled 后才允许重开，避免读取正在原子替换的路径；不通过暂停事务或新 file snapshot 机制“保护”预览。selection change/entry deletion/version replacement都失效，观察 entry identity而不是仅 songID。
7. score prepare 失败明确 retry/close；history 失败是另一个 attached 状态，不能隐藏谱面或伪造空白 score。Preview 不能 bind recorder/applicator 或生成一次练习事实。

### 单次 snapshot 的逐小节标记

- 当前 snapshot builder 的 `uniqueRealFacts` 与 existing hand merge 为唯一派生源：both stable 或 left+right stable = stable；其他真实 attempted = learning。
- 逐 sourceMeasure state 与 aggregate 从同一分类派生；不再 read progress repository，缺少 **已确认当前 revision 的** source state 才是 unpracticed。
- 现有 `.metadataUnavailable` / 不匹配 score revision 表示进度未知/待建立，不可绘制成所有小节“未练习”或错误；snapshot identity/fileVersion 加 prepared scoreRevision 校核。overview 不带 revision 时本 task 添加最小 revision 关联事实。
- no sessions invitation 维持当前语义，不因 metadata 有条目强行生成已练习标记。
- Notation 接收中性 measure occurrence annotation，host 从 `MusicXMLMeasureSpan.sourceMeasureID` 映射状态/resume/focus；没有原始 JSON/host model 依赖。rect 来自 T3，空休止小节也能标注，annotation 不改分页。
- stable/learning 底层状态可与 resume/focus叠加；轮廓/图标/a11y 提供无色辨别，不用整页卡片或旁边 dashboard。Annotation 未命中当前谱面时不 clamp 到另一个小节。

### 交互与旧 UI 的同任务删除

- 非选中 folio confirm = select；已选中央 confirm = open score，不再 toggle audition。
- `LibraryNowPlayingBar` 继续独立播放/暂停/seek；翻页/打开关闭 detail 不改变音频业务状态。Library 真正 disappear 的原 stop policy不变。
- 迁移 loading、invitation、overview、temporarilyUnavailable retry、corrupted retry+**明确 backup-and-reset confirmation** 到 detail。摘要 duration/session/streak不升级成新 dashboard；现有有用信息为紧凑文本，谱面为主体。
- reset 仍调用既有 `recoverSelectedPracticeSnapshot` 路径，经确认→backup/reset→reload；不能把新 UI Button 当作已备份的证明。
- 删除旧 selected-confirm playback action/enum/tests、trailing Ornament 挂载、两个旧 View、`libraryViewHeight`/仅其使用的 onGeometryChange、旧 reset-dialog 的重复 owner；无新旧 feature flag。

### 验证 / Gate

- 确认中央打开真实谱面，production composition 所有入口/previews编译，不只测独立 VM。
- resolver 返回同 ID 新 version 时拒绝旧请求；异步关闭后 late completion、导入开始/取消/替换/删除、rapid open/close/selection、scene inactive。
- written order/both hands、最多一个 prepared、failure/retry、close/reopen 无悬挂 task/旧页码。
- 分类与汇总一致、left+right合并、zero real attempts、missing metadata/revision mismatch unknown、resume/focus/空休止几何正确、不额外 repository.history。
- loading/invitation/unavailable 在 detail；corrupted 明确确认并验证 backup 文件/新 history，取消不写、备份失败不 reset。
- audition 独立、preview 不调用 launch/record/attempt/progress 写入；保持既有 repository.history 自身的 interruption recovery 语义，不为 preview额外触发路径。
- `make build:simulator`；Simulator Flow→选中→真实 Spread→关闭回同一 folio；清理 scan。

**原子提交:** `feat: P2-T4 - 接入曲库双页预览并移除旧历史面板`

### P2-T4 实施与验证证据（2026-10-01）

- `LiveAppGraph` 注入独立 preview owner 到唯一 `SongLibraryViewModel`，Graph/Root/Content/debug/previews 继续复用原入口，不增加窗口或 launch 副作用。中央确认由 Library owner 决策；外层试听条和 importer 不卸载，detail 只替换 Book Flow 内容。
- 预览以 `.practice` written order 通过正式 resolver/preparation 与共享 PagePlan；resolve 后、prepare 后、pagination 后核对 identity/generation。selection/index/bundled-entry 的事实变更在同一失效方法收敛，已完成预览也会因版本变化立即清除；曲谱导入前、删除前、close/disappear/non-active scene 同步取消。无永久缓存、recorder、applicator 或第二次 history read。
- snapshot 同一真实 fact 分类派生 source states 与汇总，保留 score revision；host VM 执行 revision/selection 校核，再映射中性 occurrence annotations。学习状态、继续/重点图标共存，rest rect 也可标注，无色可辨且不改变布局；缺 metadata 或 revision 不匹配不假称未练习。
- 旧 playback-confirm action/enum/test、历史 trailing ornament、height 测量、两份旧历史 View 与其私有 helpers 全部删除；历史紧凑迁移至 detail。备份确认绑定原 identity，实际调用 File repository 验证备份原字节与新空 history；未确认/过期确认不写，备份替换失败保留损坏原文件。预览错误日志只写 safe error summary，不导出原 XML/路径。
- 真正 native Root 的 scene inactive→close、active 不自动重开、显式 reopen→同一完整 PagePlan 已覆盖。新 native 测试起初暴露浮点边界差异：相同 input/projection/absolute score，system ink height 因 Dictionary 顺序的多次 CGRect.union 出现 `17.66` vs `17.659999999999997`。在唯一 InkBoundsService 直接聚合 min/max 边界再构造 CGRect，消除遍历顺序依赖；不加 epsilon、舍入或缓存补丁。保留 native 完整计划相等回归与 dense ledger 重建检查。
- 初始两次 Xcode selection 缺完整函数 ID，实际 0 tests，明确不作为通过证据；修正为枚举中的完整 `function()`/`function(argument:)` 后 Gate 42/42，最终扩大到 50/50（0 failed/skip）。证据：`.build/TestResults/LibraryPreview-T4-final-1790801386.xcresult`、`/tmp/happy-t4-final.log`；discovery `/tmp/happy-t4-enum.txt`、选择 `/tmp/happy-t4-final-ids.txt`。
- native 初次 0/1 失败是上述真实边界差异；诊断轮打印完整对象过大导致测试收尾停滞，仅终止本任务的 xcodebuild PID，未重启/删除模拟器。修复后 native 1/1：`.build/TestResults/LibraryPreview-T4-native-fixed-1790801255.xcresult`；移除临时 capture cue/等待后的最终 1/1：`.build/TestResults/LibraryPreview-T4-native-final-1790801473.xcresult`、`/tmp/happy-t4-native-final.log`。
- 唯一现有 AVP 的实际 simctl 截图 `/tmp/happy-t4-production-preview-fixed.png` 已逐页目视检查：23 页真实谱、完整双页、详情返回、历史邀请及外层试听条均正常。Native 测试恢复原 root/窗口尺寸，不新建设备或窗口；不将此证据冒称人工点击通过。
- package 253/253，6 targets（96/66/10/17/43/21），`/tmp/happy-t4-package-fixed.log`；最终 build 结果记在 `/tmp/happy-t4-build-final.log`。旧符号 scan 与 `git diff --check` 为零。长期文档同步 `docs/data-flow.md`。

---

## P2-T5 验证 Practice 分页导航和生命周期边界

**Goal:** 回归整个新 consumer 的实际行为；T3 已接入并删旧路径。本 task 不再重复搭建另一套 navigation/renderer，不接受延期清旧。

### Files / 针对性验证

- `HappyPianistAVPTests/Practice/PracticeSessionViewModelTests.swift`、`PracticeResumeLifecycleTests.swift`、`ManualAdvanceStrategyTests.swift`。
- Package `PracticeSessionRuntimeStateTests`、round configuration/active range、autoplay cursor/schedule tests。
- 实测暴露的本 feature 缺陷只在拥有不变量的已接入实现上修复。

场景必须从 prepared install 走到 page query/可见 spread：
1. 全曲→局部 passage→另一 passage，measure coverage/page IDs不变，target/highlight更新。
2. invalid range、clear/reset/换谱、返回保存失败/取消返回，不能展示旧 score/page/state；不删除既有保存失败提示。
3. 手动按 step/measure、恢复到范围末步、completed.last有效步、backward retry、seek大跳页。
4. Autoplay rest/no-guide、long tie、pause/resume/tempo-scale/fermata、same tick 多事件、start/stop/restart/error/end；不在 pause 期间自动跳页。
5. 新 session 与旧迟到 task/transition不串；布局只因 formal score identity改变。
6. demo hands transport/contact timeline 的既有测试仍通过，不能把共用时间字段当旧滚谱一起删。
7. Practice 宿主的键盘、cue、settings、Immersive open/close和数据保存不被 Spread 生命周期重建。
8. 旧符号 scan 为零；在 T3发现残留就回修 T3，不能在这里声称“按计划最后清理”。

**Gate:** 运行以上 targeted tests、Notation regressions、`make build:simulator` 和 Simulator manual/autoplay/resume；有先存失败记录具体 test ID 与本轮证据，不修无关问题。

**原子提交:** `test: P2-T5 - 验证分页练习导航与生命周期`（仅实际新增/修改的回归检查；无代码变化不制造空提交）

---

## P2 Phase completion checklist

### P2-T5 实施与验证证据（2026-10-01）

- PreparedBookPaginationTests 新增 step/measure 参数覆盖全曲→两段 passage→全曲、末步 completed、向后重练、非法范围、reset/换谱；真实 File repository 覆盖 saved/failed/cancelled 返回与末步恢复，检查最终持久化 resume 与保存失败不覆盖旧文件。保持唯一 PagePlan/buildCount，不搭第二导航路径。
- 定向 6/6：`.build/TestResults/BookLifecycle-T5-specific-1790802036.xcresult`；扩大集 125/125：`.build/TestResults/BookLifecycle-T5-wide-1790802363.xcresult`。参数子项均从 xcresult 确认通过。已知先存示范手 timing 失败不计入 Gate，保留 baseline 失败证据，不修无关 rig。
- 现有唯一 AVP 实际 native production Book View：手动从 1/2 到 3/4、恢复停留 3/4、autoplay 跨至无 guide 的休止页、pause 保持、clear 移除旧谱；截图 `/tmp/happy-t5-start-START.png`、`/tmp/happy-t5-start-REST.png`、`/tmp/happy-t5-MANUAL.png`、`/tmp/happy-t5-RESUME.png`、`/tmp/happy-t5-CLEAR.png` 已目视检查。capture 两轮各 1/1，临时 capture wait/打印已删除；最终 native 1/1 结果路径见 `/tmp/happy-t5-native-final-path.txt`，日志 `/tmp/happy-t5-native-final.log`。
- Native 测试挂载共享生产 GrandStaffNotationBookView 而非重建 renderer；不启动 isolated PracticeStepView 的 Immersive 副作用。完整 Practice 宿主/键盘证据复用本阶段实际应用截图，不能将 isolated native 测试称为 Immersive 端到端。
- package 253/253：`/tmp/happy-p2-final-package.log`；最终 build 通过：`/tmp/happy-p2-final-build.log`。旧符号 scan 与 diff check 零；长期验证边界同步 docs/testing.md。

独立核对：唯一 engraving/page owner；完整 score 输入；逐 staff/context；边界/continuation；同一 canonical geometry；Library/Practice 共用动态 Spread；无练习预览副作用/第二 history 路径；无旧 tap/Ornament/View/context/scroll runtime；不丢音乐事实或可访问性；文档与真实调用一致。
这不是最后清理机会，任何旧路径应已在所属替换 task 消失。

## 验证命令规则

- 测试证据遵守仓库 `docs/testing.md` 与根/AVP `AGENTS.md`：Apple 集成必须真实 `xcodebuild test`；build-for-testing 或 macOS package 通过不是同一证据。只记录本轮实际执行结果，不复用旧 audit/旧计划里的通过声明。
- 本机 package：`swift test --package-path Packages/HappyPianistCore --triple arm64-apple-macosx26.0`。换机器核对架构/系统后选有效 triple，不硬编码进 Package platforms。
- 先 `swift test list` / Xcode test enumeration 再筛实际函数/suite；文件名不一定是 suite。确保实际运行非零个期望测试。
- 用户于本轮明确要求仅使用现有 Apple Vision Pro `28DABA38-C30B-44B1-9C2B-65D50F7FCC55`，不新建设备。直接 `xcodebuild test`，保留唯一 result bundle 路径、超时和 discovered IDs；不要使用会 shutdown device / 删除旧报告的默认 Make test 收尾。
- ImageRenderer golden 的 font registration、OS/SDK与实际 pixel哈希必须核对；变更说明源于分页事实，不盲刷 golden。
