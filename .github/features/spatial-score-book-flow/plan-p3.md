# Plan P3 — 直接用于 3D 的真实双页谱与翻页

**Goal:** 在既有空间书册中显示真实 MusicXML，多系统单页/双页、详情历史与空间翻页；原 2D 滚谱不变。
**Non-goals:** 不先实现 Window Book Spread，不删 GrandStaffNotationView/viewport API，不新建 parser、不用整谱 bitmap/PDF。
**Approach:** 抽取共用 engraving 内核并由原 2D 当场消费，随后在 3D 真详情接分页与动态页表面，最后加原生 sheet 翻动。
**Acceptance:** D03/D04 对真实谱成立；3D 同谱分页稳定、原 2D 记谱/滚动保持；Detail 操作/历史/取消真实。
**Rules:** 页码由谱事实+canonical page geometry 决定，不由当前 overlay/tick/window size/range 决定；Notation→Practice→MusicXML 依赖不能倒置。

依赖：P2 正式 folio 与打开意图；物理表面/尺度由 P1 验证。不使用 archive 的 Window 几何实验或未在当前树存在的分页 API。

## P3-T1 抽取共享记谱内核并保持原滚谱行为

**真实执行路径：**
`GrandStaffNotationView → GrandStaffNotationPresentationViewModel.makePresentation → GrandStaffNotationLayoutService.makeLayout → spacing/chord/spanners → GrandStaffNotationRenderer`。
当前 makeLayout 从 source/performed facts 构造 chord/beam/rest/marks，同时按 scrollTick/viewport/overlay 裁剪和着色；直接把旧 View 缩成两份不能排多系统，也会在高亮时重复全谱工作。

**Files：**
- Modify: `Packages/HappyPianistCore/Sources/Notation/GrandStaffNotationLayoutService.swift`、`GrandStaffNotationPresentationViewModel.swift`、`GrandStaffNotationRenderer.swift`，必要 models/spacing 的最小共享拆分。
- Add: 同目录 `GrandStaffNotationScoreLayout.swift`、`GrandStaffNotationScoreLayoutService.swift`、`GrandStaffNotationSystemLayoutService.swift`；单实现不新建协议。
- 保留: `GrandStaffNotationView.swift`、`GrandStaffNotationViewportLayoutService.swift`、原 public initializer 与 legacy consumer。
- Tests: 原 Notation layout/viewport/golden/note-type 测试，`HappyPianistAVPTests/Notation/GrandStaffNotationVisualTests.swift`、`Piano/PianoHighlightViewConsistencyTests.swift`。
- Docs: `docs/data-flow.md`。

**实施与不变量：**
1. 将完整谱事实和绝对 staff-space 排版与 viewport/system slice 分开，共享一套解析后的 chord/stem/beam/rest/spanner/marks/attributes 构造；不是复制另一份 makeLayout。
2. 原 makeLayout 成为仍有业务职责的 2D viewport 投影，内部当场用共享内核；保留原 scrollTick/context/overlay 语义。它不是为删除而留的兼容 alias，而是明确保留产品的真实 consumer。
3. 保留 source/performed/occurrence identity 与 original part/staff→displayed staff 事实，来自现 PreparedPractice.scoreContext/notationProjection；不从首音猜，不用 parser 再读一遍 XML。
4. absolute layout 不含 active tint/range/scroll/window 像素；system slice 用真实 measure boundaries、局部 clef/key/meter/context，把 spanner 跨系统端点正确续接。beam 源组/provenance 和已支持记谱完整保留。
5. ink extents 包含 note/chord/ledger/stem/beam/rest/fingering/marks/tie/slur/tuplet/header。renderer 与 packing 共用同一边界，不用 magic padding 或只测音符头。
6. score 构建是纯值 Sendable、非主 Actor 可运行；不为此添加全局 cache/unsafe isolation。3D 当前谱 cache/异步 owner 在 T2 真 consumer 内实现，T1 不加无人使用的状态。
7. 不删除原 2D scroll/context/API/tests；只删除被抽取内核替代的重复内部算法。原 golden 不随便更新来盖回归。

**针对性验证：**
- 原 viewport/golden 在相同输入输出 parity；原 continuous notation view 与 highlight 真消费通过。
- full score 首末/纯休止/跨 staff、clef/key/meter change、source vs meter beam、tie/slur/nested tuplet、反复 occurrence；split-part grand staff 事实不变。
- overlay/range/tick 改变绝对 layout 不变；system 边界完整且 continuation 正确；布局不依赖宿主 size。
- `swift test --package-path Packages/HappyPianistCore --filter Notation`；Apple target 现 notation/glyph consistency 的真正 xcodebuild test + build。package 成功不能代替 Apple consumer。

**Gate / 原子提交：** 新内核已被原 2D 消费且 parity 成立；`refactor: P3-T1 - 共享记谱内核并保留二维滚谱`。

## P3-T2 在空间书册接入真分页、详情与历史

**现有复用链：**
`SongLibraryEntryResolver → PracticePreparationService → PreparedPractice` 已验证 steps/measureSpans、identity/revision。
`SongLibraryViewModel.practiceSnapshotState` 与 `SongPracticeLibrarySnapshotBuilder` 已提供小节事实/历史。详情只读准备，不调用 PracticeLaunchViewModel.beginVisit 创建练习 session。

**Files：**
- Add: `Packages/HappyPianistCore/Sources/Notation/GrandStaffNotationPagePlan.swift`、`GrandStaffNotationPaginationService.swift`、`GrandStaffNotationPageView.swift`，同 task 从 3D Detail 正式消费。
- Add: `HappyPianistAVP/ViewModels/Spatial/SpatialScoreBookViewModel.swift`、`Services/Spatial/SpatialScoreBookSceneController.swift`、`Views/Spatial/SpatialBookPageContentView.swift`。
- Modify: `HappyPianistAVP/ViewModels/LiveAppGraph.swift`、`ViewModels/Spatial/SpatialExperienceViewModel.swift`、`Views/Spatial/SpatialExperienceView.swift`、现 flow controller 的打开/合拢消费点。
- Reuse: `HappyPianistAVP/Services/Library/SongPracticeLibrarySnapshotBuilder.swift`、`SongPracticeFocusMeasureBuilder.swift`。
- Tests: 新 `Packages/HappyPianistCore/Tests/NotationTests/GrandStaffNotationPaginationTests.swift`、`HappyPianistAVPTests/Spatial/SpatialScoreBookTests.swift`、`SpatialScoreBookEntityTests.swift`。
- Docs: `docs/data-flow.md`。

**实施：**
1. 按 P1 实测阅读规格设置 canonical page geometry，用真实 ink bounds 选系统边界并纵向 packing；不得在无法正确续接的 explicit beam 源组内部断 system，tie/slur/tuplet 的跨系统 continuation 保留身份。拥挤内容优先合法分页/放大，不丢音符、不硬压每页四行。空、奇数末页、不能安全容纳的 system 有明确结果，不假 successful fallback。
2. PagePlan 保持 measure occurrence→system/page/spread 的确定映射；相同 identity/geometry 只有一个当前 plan。active range 只改表现，不裁事实/改分页。written/performed occurrence 语义与反复谱注明一致，不能以 source 小节号冒充当前 occurrence。
3. SpatialScoreBookViewModel 只持当前 prepared read-only 内容/plan/navigation，异步解析/构建不在主 Actor；load/cancel/publish 均检 selected entry/file revision 与当前请求。新曲/关闭/suspend 清旧状态，迟到失败不盖新曲。
4. 原选中 folio 打开同一 OpenBookRoot；轻书脊与独立左右页 entity，用局部动态 page attachments 绘制真实 systems、overlay/历史/当前小节。不是把完整 GrandStaffNotationView 挂一次或把 MusicXML 转全谱图。
5. resume/focus 使用 matching identity/revision 与真实 measure occurrence；无匹配从首 spread 开始。late history 可以更新标记，不能抢用户已手动浏览的页。历史不可用提供现有恢复语义，不把 unknown 画 learning/error。
6. Detail 手动下一/上一页、合法 resume/focus 定位、关闭回原 folio；此 task 先直接切页功能完整，T3 仅加空间 sheet 动作。试听独立且换页不影响音频。
7. 原 2D consumer 不改为 PageView；唯一共享的是事实/engraving，不强迫旧滚谱同页码。跨模块所需 PagePlan/page renderer 使用明确的 public 边界；Notation/Core 不引用 App/RealityKit 或空间 entity。新文件全部在 LiveAppGraph、SpatialExperienceView、flow consumer 当场接入。
8. Library/Practice 后续共用此 book owner，不另外新建 LibraryPagePlan/PracticePagePlan。PracticeLaunch 仍是正式音乐 launch，详情 read-only prepared 不能绕过后续进度/身份验证。

**验证：**
- fixture 真 prepare→engraving→packing→page entity，包括 dense、rests、split-part、已支持符号/连线；页覆盖全部合法小节且无重/漏，ink 不剪断。
- page plan 对不同 host 尺寸、highlight/tick/range 稳定；阅读放大同 plan；奇数末页/单页/页界。
- 换曲/关闭/文件 revision 变化/后台迟到，无旧谱回写；resume/focus/late history 与手动浏览。
- 打开/关闭保留选曲与试听，不创建 practice visit/写练习 progress；可重新读 repository 证明只读。
- package 分页测试、AVP 实体/视觉/异步 tests + build；实际 RealityView D03 与真机双页密集谱可读性。不以 Canvas snapshot 代替空间尺度。

**Gate / 原子提交：** 3D 真详情完整可用、原 2D 回归；`feat: P3-T2 - 在三维书册呈现真实双页谱与历史`。

## P3-T3 实现空间 sheet 翻页与最新目标收敛

**Files：**
- Modify: `HappyPianistAVP/Services/Spatial/SpatialScoreBookSceneController.swift`、`ViewModels/Spatial/SpatialScoreBookViewModel.swift`、`Views/Spatial/SpatialBookPageContentView.swift`。
- Add 必要最小纯值 presentation：`HappyPianistAVP/Models/Spatial/SpatialBookPageTurn.swift`，同 task 从 controller 消费。
- Tests: 新 `HappyPianistAVPTests/Spatial/SpatialBookPageTurnTests.swift`；当前 book entity tests。
- Docs: `docs/data-flow.md` 的 3D 导航边界。

**实施：**
1. navigation 的真值为目标 spread，page turn 只为 presentation；不拿 animation timer 修改音乐位置。
2. RealityKit page entity 围书脊翻动，正/背面关系按 spatial-design 第5节，文字正向；不使用 Window perspectiveRotationEffect 作为 3D 主实现，不做 deforming mesh/纸物理。
3. 相邻目标转单 sheet，大跨度直接最终页；翻动中 retarget 取消旧过渡直接最新合法页。same target 不重启，new score/plan/reset 清 animation。completion 校验当前 book/plan/transition，有限页层，不缓存历史页。
4. 页缘局部 Button 从第一次接入就可用。
5. 动画完成用平台原生完成/取消事实，不用 sleep 猜；controller teardown 停 native animations，detach/suspend/新曲迟到回调不能写回。

**验证：**
- forward/backward 正背面与页码、首末/奇数空面、same target、大跳、rapid retarget、旧 completion、reset/detach。
- page layers 上界；target 与当前书真实 identity。
- 实际 RealityView D04 短录屏观察前后面/文字/阴影，不只纯状态函数；定向 xcodebuild test + build。
- 原 GrandStaffNotationView/PracticeStepView 继续用原滚谱，没有新 page-turn runtime 被塞回 2D。

**Gate / 原子提交：** 空间翻页与 invariant 成立；`feat: P3-T3 - 增加原生空间单页翻动与导航`。

## Phase Audit

完成后创建新版 `audit-p3.md`，核对共享算法不是双 parser、分页不被范围/tick 重建、3D 真 consumer 和原 2D 都存在。P3 只证明详情/手翻，演奏自动页与安全 session 属于 P4。
