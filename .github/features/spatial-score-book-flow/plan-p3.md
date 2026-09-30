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
- generation/transition identity if needed to discard stale completion。

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

本 task 同时接入 Reduce Motion 与基础 a11y：Reduce Motion 直接替换、不旋转；被翻动的前后面/源页仅为视觉层，不重复暴露 note/rest VoiceOver 内容，语义层始终对应正式 target。T4 只补验收，不能把这些基础能力留到最后。

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
- forward/back front/back 页码与文字朝向；奇数末页空白；Reduce Motion；动画前后 a11y 不重复；score reset 时旧 completion 被拒绝。

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

命中区用带可访问标签的 Button，点击/凝视+pinch 不是 onTapGesture 的别名；页缘大小与窗口缩放/Dynamic Type 保持可点。关闭控件贴近乐谱，返回当前 selection；不为 preview 新开窗口或重建外层 SongLibraryView。VoiceOver adjustable navigation 在本 task 接通，而非等待 T4。

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

**Gate:** preview/annotation/history late-response 与 page-turn targeted tests、`make build:simulator`，实际 Simulator 页缘/VoiceOver/关闭回同一 selection 验收。

---

## P3-T3 Practice navigation tick 驱动自动翻页

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

## P3-T4 Reduce Motion / VoiceOver / final real validation

**Goal:** 完成翻页体验的可访问性和真实验收，不承担 P1/P2 遗留清理。

### Reduce Motion

When enabled:
- no 3D page rotation；
- directly replace spread or use short opacity transition；
- same navigation state/API；
- no second layout path。

### VoiceOver

Library preview:
- expose current page range / total page count；
- `accessibilityAdjustableAction` next/previous spread；
- page edge visual affordance is not the only navigation method。

Practice:
- announce current page range when focus lands on score；
- automatic page turn does not forcibly steal VoiceOver focus；
- note/rest accessibility order remains page -> system -> element。
- 转页的视觉 source/front/back 不进入第二套 VoiceOver tree；target 变化不强行移焦。必要手动播报与自动变化区分，不能每个高亮 tick 连续播报。

### Differentiate Without Color

Book/page navigation and current focus cannot rely only on:
- green/amber；
- opacity。

Keep geometric/textual/a11y state.

### Real validation

Run:

1. Book Flow scroll/selection；
2. open real dynamic score；
3. manual Library page turn；
4. close/reopen；
5. Practice manual progression；
6. autoplay crossing page；
7. backward/retry；
8. Reduce Motion；
9. VoiceOver adjustable navigation。

### Tests / build

- targeted Notation + Library + Practice；
- package tests；
- `make build:simulator`；
- full simulator test target when practical；
- if full target has pre-existing failures, record exact failing tests and do not misattribute them to this feature。

命令与报告隔离遵守 P2 的“验证命令规则”：用实际 discovered IDs，确认非零测试；package macOS 通过不是 Simulator 通过；不覆盖旧 result bundle、不关掉用户已有 Simulator。最终验收不能拿本轮审查的 238 个现有 package tests 当新功能通过证据。

### Cleanup rule

P3-T4 may clean only code introduced by P3 itself.

It must **not** be the place where we finally notice:
- Vinyl old code；
- old scroll schedule；
- old viewport view；
- old context helper。

Those must already have been deleted in P1/P2.

### Docs

Update `docs/testing.md` only with actual evidence from this execution.

### Phase Audit

Verify:

- page-turn layer is presentation only；
- Library and Practice share it；
- no timers/scroll runtime reintroduced；
- Reduce Motion and VoiceOver use same page plan；
- no feature flags / compatibility aliases remain；
- no debug/preview code leaked into production path。

**Atomic commit:** `test: P3-T4 - 收口 Book Spread 翻页验收`
