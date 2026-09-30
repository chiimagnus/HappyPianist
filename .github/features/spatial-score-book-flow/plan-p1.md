# Plan P1 - Book Flow 替换唱片曲库

**Goal:** 在不重写曲库业务状态的前提下，把现有 Vinyl Carousel 替换成 Cover-Flow-style Book Flow，并在替换任务内彻底移除唱片/唱臂/Record/Crate 的旧 UI 语义。

**Visual acceptance reference:**
- `.github/features/spatial-2026-09-30/设计稿/images/01-Book-Flow曲库.png`

本图约束 Book Flow 的中心 folio、两侧倾斜/后退、信息层级和整体书册隐喻；P1 只实现 Window 中可验证的基础，不要求此阶段已经 world-lock。

**Important scope:** P1 仍运行在当前 Library Window。这里实现的是未来空间 Book Flow 可复用的 SwiftUI 视觉/交互基础，**不是最终 world-locked RealityKit 深度对象**。不要为了“看起来更 3D”提前引入 RealityKit。

**Non-goals:**
- 不做 Book Spread；
- 不解析 MusicXML；
- 不把 Library 搬进 ImmersiveSpace；
- 不改导入事务、selection persistence、播放服务；
- 不删除 destructive delete / import transaction 等真实数据安全边界。

**Approach:** 只替换当前 Library Window 的视觉/交互呈现：先把当前 carousel 的纯值几何替换成 Book Flow 模型并立即接入，再用 folio UI 接管当前生产 caller；不新增第二个曲库状态 owner。

**Rules:** 新实现接管当前 caller 的同一 task 就删除被替代的 Vinyl/Record/Crate presentation；导入、删除、试听、selection persistence 仍由现有业务 owner 决策，UI 不复制 gate。

**Phase acceptance:** Window 中核心曲库已经是 Book Flow；导入/删除/试听/选择仍正常；production 不再依赖 Vinyl/Turntable/Record/Crate 核心视觉语义。

---

## P1-T1 建立 Book Flow 纯值呈现模型

**Files:**
- Add: `HappyPianistAVP/Views/Library/LibraryBookFlowPresentation.swift`
- Add: `HappyPianistAVPTests/Library/LibraryBookFlowPresentationTests.swift`
- Update: `HappyPianistAVP/Views/Library/LibraryRecordCarousel.swift` 的现有 item 呈现；本 task 当场使用新值模型，不等 T2。
- Delete in this task: current `LibraryRecordScrollPresentation` definition/tests after the new presentation model takes its only production consumer

### Current behavior / root cause

当前 `LibraryRecordScrollPresentation` 只有：

- scale；
- opacity；
- saturation。

所有 item 仍然正面朝向用户，所以不是 Cover Flow。

原型要求的是：

- 中间 folio 正面；
- 左右 item 相反方向 Y-axis rotation；
- 越远越弱；
- 明确前后视觉层级。

### Implementation

建立纯值 `LibraryBookFlowPresentation`。

输入：
- item 相对 viewport center 的 signed distance；
- item extent；
- Reduce Motion。

输出至少包括：
- `rotationDegrees`；
- `scale`；
- `opacity`；
- `horizontalOffset` 或等价压缩；
- `depthPriority` / 可映射的 zIndex。

`item extent` 是本布局提供的正有限值；signed distance 来自当前 viewport 的几何测量。不要让未完成测量的零尺寸变成除数，再声称这是“不可能输入”。尺寸尚未 ready 时由宿主正常延后测量；不新增异常数值 fallback 树。

### 当场接入与平台 API

本 task 立即替换现有 carousel 中 `LibraryRecordScrollPresentation` 的消费点，使旋转/缩放/层级在真实曲库出现；T2 再换乐谱册形态与命名，不创建临时 parallel carousel。

本机 visionOS SDK 已核对：带 `perspective` 的旧 `rotation3DEffect` overload 已 deprecated；窗口中的克制透视使用 `perspectiveRotationEffect`，不要把真正三维 rotation 与二维透视混为一谈。

`visualEffect` closure 只返回 VisualEffect，`zIndex` 是 View modifier，不能在 closure 内套普通 View API。需要重叠层级时使用 item 内的几何呈现值（例如 `onGeometryChange` 得到的 signed distance）统一驱动 View modifiers；它不是第二 selected index。纯测量不写 selection、不回推 layout 尺寸、不触发每项业务 task。scrollTargetID 是平台滚动绑定，必须保留，不能误删为重复业务状态。

先在当前 consumer 编译并验证 scroll/hover/垂直导入删除不会与倾斜 hit target 冲突，再进入 T2；默认保留系统 Button/hover affordance，不用定时器或手写渲染循环。

规则：

1. center distance == 0：
   - rotation = 0；
   - scale 最大；
   - depth priority 最大。

2. 左右第一邻居：
   - rotation 方向相反；
   - 角度约 50–65° 的视觉目标由 Simulator 调参，但纯值函数先有 deterministic clamp；
   - 不能依赖 item index，只依赖 signed distance。

3. 更远 item：
   - rotation 不继续无限增加；
   - scale / opacity 单调降低；
   - 不需要模拟真实三维米制 Z 坐标；当前 Window 只做 perspective/depth presentation。

4. Reduce Motion：
   - 取消强 3D rotation / 大位移；
   - 保留 center emphasis、selection 和层级；
   - 不额外维护第二套 layout。

### Cleanup in this task

- `LibraryRecordScrollPresentation` 被新 presentation 替换后立即删除；
- 对应旧测试立即删除/迁移；
- 不留 typealias、deprecated wrapper 或 compatibility alias。

### Tests

覆盖：

- center；
- left/right first neighbor；
- far neighbor；
- symmetry；
- monotonic scale/opacity；
- distance clamp；
- Reduce Motion；
- NaN/inf 不作为公开输入契约，不为“不可能输入”增加额外 runtime fallback；测试只覆盖实际 GeometryProxy 可产生的有限值。

### Gate

- Library presentation targeted tests；
- 当前 production carousel 已消费该模型，旧模型引用为零；
- `make build:simulator`。

**Atomic commit:** `feat: P1-T1 - 建立 Book Flow 呈现模型`

---

## P1-T2 用 Book Flow 替换 Vinyl UI，并当场清掉旧唱片语义

**Files:**
- Replace/Rename: `HappyPianistAVP/Views/Library/LibraryRecordCarousel.swift` → `LibraryBookFlow.swift`
- Replace/Rename: `HappyPianistAVP/Views/Library/LibraryRecordCarouselActions.swift` → `LibraryBookFlowActions.swift`
- Add: `HappyPianistAVP/Views/Library/LibraryScoreFolioView.swift`
- Update: `HappyPianistAVP/Views/Library/SongLibraryView.swift`
- Update: `HappyPianistAVP/Views/Library/LibraryNowPlayingBar.swift`
- Update: `HappyPianistAVP/Views/Library/SongLibraryTrackPresentation.swift`
- Delete: `HappyPianistAVP/Views/Library/VinylRecordView.swift`
- Delete: `HappyPianistAVP/Views/Library/TurntableTonearmView.swift`
- Rename/Update: `HappyPianistAVPTests/Library/LibraryRecordScrollSelectionTests.swift` → Book Flow equivalent
- Update: `HappyPianistAVPTests/Library/LibraryDeletionHoldPolicyTests.swift`
- Update any previews/accessibility strings that still say 唱片 / 唱片架 / record / crate

### Current behavior / root cause

唱片语义目前不只在两个 View：

- `VinylRecordView`；
- `TurntableTonearmView`；
- `LibraryRecordLayout`；
- `LibraryRecordScrollItemView`；
- `LibraryRecordScrollSelectionDecision`；
- `LibraryCrateDragConfiguration`；
- “唱片架，左右滚动选曲”；
- “上拽唱片导入乐谱”；
- “下拽唱片删除”；
- `LibraryNowPlayingBar` 的 `record.circle`；
- 空曲库的 `record.circle` 与“黑胶唱片形式”文案；
- `SongLibraryTrackPresentation.labelColor`。

只删 Vinyl/Tonearm 会留下大量半旧状态，不允许。

### Implementation

#### A. Book Flow container

继续复用已经可靠的：

- `ScrollView(.horizontal)`；
- `LazyHStack`；
- `scrollTargetLayout()`；
- `scrollTargetBehavior(.viewAligned(anchor: .center))`；
- `scrollPosition(id:anchor:)`；
- `selectedEntryID`；
- scroll phase idle 后 commit selection；
- VoiceOver adjustable next/previous。

用 P1-T1 presentation 驱动 item：

- Y rotation；
- scale；
- offset；
- opacity；
- center layering。

不要另建：
- 第二套 selected index；
- RealityKit mirror collection；
- duplicated scroll state。

#### B. Score folio

`LibraryScoreFolioView`：

- 薄乐谱册比例；
- title / subtitle；
- 窄书脊 / 少量 page edge；
- 简单 deterministic cover treatment；
- 不做厚书；
- 不引入封面资源商店或 texture pipeline。

曲名/来源取既有 entry；没有真实作者事实就不补假作者。参考图的插画不是授权要求导入的资源，不为模仿图建立封面 store。狭窄窗口/Dynamic Type 下标题与命中区域仍可用；5–7 本是常规尺寸视觉目标，不是以固定宽度裁掉控制的契约。

#### C. 试听行为

P1 阶段先保持现有“selected item 再确认可试听”的行为，保证阶段提交仍完整可用。

但：
- 所有类型名改为 Book Flow 中性命名；
- `LibraryNowPlayingBar` 是正式试听控制；
- P2-T4 当 Book Spread detail 可用时，selected-item confirm 将正式改为“打开乐谱”，并删除 toggle-playback tap 路径。

不要为了阶段过渡创建：
- legacy mode switch；
- compatibility flag；
- old/new tap runtime toggle。

#### D. 导入 / 删除

保留当前能力，但去掉唱片隐喻：

- `LibraryCrateDragConfiguration` → 中性 `LibraryBookFlowDragConfiguration` 或更贴职责的名称；
- “上拽唱片” → “上拽导入乐谱”；
- “下拽唱片删除” → “下拽删除乐谱”；
- preview / a11y 改成“乐谱库 / Book Flow”。

### Must-delete in this task

完成替换后，全仓 production path 中不得再有：

- `VinylRecordView`
- `TurntableTonearmView`
- `LibraryRecordLayout`
- `LibraryRecordScrollPresentation`
- `LibraryRecordScrollItemView`
- `LibraryCrate*`
- “唱片架”
- “黑胶唱片形式”
- `record.circle` 作为 Library 产品隐喻

如果 `SongLibraryTrackPresentation.labelColor` 仍只是 cover accent：
- rename 为 `accentColor`；
- 同 task 更新所有 caller/test；
- 不留旧 property alias。

### Real safety rails that remain

不要删：

- bundled entry deletion block；
- import active gating；
- destructive deletion hold；
- selection persistence debounce/generation；
- import transaction recovery。

这些不是“多余围栏”。

尤其删除手势要在 hold 完成和异步 mutation 时核对资格；Button disabled/第一次读取 importState 不能替代 service 检查。只删除已证明在同一无悬挂段冗余的纯表现守卫，不把 `.isBundled`、file/index validation、取消检查当成兼容代码。

### Tests

迁移/新增：

- presentation geometry tests；
- center/neighbor selection commit；
- external selectedEntryID → scroll target；
- selected item stage-P1 audition behavior；
- next/previous accessibility；
- delete eligibility；
- hold threshold；
- import/delete callbacks；
- bundled delete protection；
- Reduce Motion。

### Manual Simulator acceptance

- center folio 正面；
- 两侧明显倾斜；
- 同时可见约 5–7 本；
- scroll 时视觉稳定；
- 不像普通平面 LazyHStack；
- 没有唱片、唱臂、唱片文案。

### Gate

- targeted Library tests；
- `make build:simulator`；
- Simulator 真实滚动。

**Atomic commit:** `feat: P1-T2 - 将曲库重构为 Book Flow`

---

## P1 Phase completion checklist

执行完 P1 立即审：

1. `rg 'VinylRecord|TurntableTonearm|LibraryRecord|LibraryCrate|唱片|record.circle'`
   - production UI 不应再保留旧唱片隐喻；
   - 若第三方/历史文档无关，不机械删除。

2. Book Flow 是否仍只有一套 selection state。

3. 导入/删除是否真实可用。

4. 没有为了未来空间化提前加 RealityKit / protocol / feature flag。

5. P1 不声称完成原型 02/03/04。
