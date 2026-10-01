# Plan P4 - Spatial Library：把 Book Flow / Book Spread 放进现实空间

**Goal:** 把 P1–P3 已经稳定的 Book Flow、Book Spread 和翻页能力从普通 Window 中提升为真正的 visionOS mixed-reality 核心选曲体验。

用户最终看到：

```text
现实环境
   +
Spatial Book Flow
   ↓ confirm
Spatial Book Spread
```

**Visual acceptance references:**
- `.github/features/spatial-2026-09-30/设计稿/images/01-Book-Flow曲库.png`
- `.github/features/spatial-2026-09-30/设计稿/images/02-双页Book-Spread曲目详情.png`

P4 的验收重点是把前两张图从“Window 中的视觉模拟”变成真正处于 passthrough 世界坐标中的 Spatial Book Flow / Spatial Book Spread；不复制图中的房间背景。

**Non-goals:**
- 本 phase 不把乐谱定位到现实钢琴；那是 P5。
- 不做 A0/C8 校准；复用现有校准系统。
- 不做琴键 AR Guide / Companion Hands；那是 P6。
- 不给每一本 folio 建独立 WorldAnchor。
- 不持久化“曲库在房间里的永久位置”。
- 不把整个 SwiftUI Library Window 作为一张平面截图贴进 RealityView。
- 不保留 Window Book Flow 与 Spatial Book Flow 两套核心选曲路径。

**Approach:** 先用一个共享 ImmersiveSpace presentation/runtime owner 替换旧 Practice 专属 open/close/recover 状态机，并让 mode 切换显式迁移 mode-owned runtime + 增量重配 AR providers；再建立 session-scoped world placement，最后用有界 RealityView Attachments 承载 Book Flow/Spread，并让 Window 收敛为辅助管理入口。

**Rules:**
- SwiftUI 负责 folio / Book Spread 内容与页内交互；RealityKit 负责 3D transform/depth/placement；ARKit 只提供 tracking facts。
- 同一 ImmersiveSpace 内切 `.library/.calibration/.practice` 不依赖新的 `onAppear/onDisappear`；旧 mode tasks 必须退出，新 mode tasks 必须显式进入。
- Spatial Library 第一版只保存 session-scoped world placement，不给每本 folio 建永久 WorldAnchor。
- Spatial Library 接管核心选曲后不保留 Window Book Flow 第二条核心路径。

**Phase acceptance:** Spatial Book Flow 在 head movement 后保持 world-fixed；大曲库可浏览；Library/Calibration/Practice 在同一 scene 内可靠切 mode；旧 `.inTransition/yield/recover` workaround 与重复 close coordinator 均已删除。

---

## P4-T1 替换旧 ImmersiveSpace 状态机并增加 library mode

**Goal:** Library 与现有 calibration/practice 共用一套 ImmersiveSpace 打开/关闭状态机，不复制当前 Practice 专属实现。

### Current source facts

当前：
- `HappyPianistAVPApp` 已有唯一 `.mixed` `ImmersiveSpace`。
- `AppState.ImmersiveMode` 只有 `.calibration / .practice`。
- `AppState` 已拥有 `immersiveSpaceState`；当前 `.inTransition` 只服务旧 open/close workaround，没有独立产品语义。
- 打开/关闭状态机实现在 `ARGuidePracticeViewModel.openImmersiveForStep / closeImmersiveForStep / recoverImmersiveStateIfStuck`；其中 `.inTransition` 分支通过最多 40 次 `Task.yield()` + recursive retry / force-closed 修补状态。`PracticeWindowRootView` 又叠了一层 `PracticeImmersiveCloseCoordinator` 来串行化 `close + recover`。这两层都是同一个旧 workaround，P4-T1 必须一起删除，而不是把其中任何一层抽进新 coordinator。
- `HappyPianistAVPApp` 目前还在 ImmersiveSpace 外层 `.onAppear/.onDisappear` 直接写 `appState.immersiveSpaceState`，同时 `ImmersiveView -> ARGuideViewModel` 已拥有真实 scene lifecycle 回调；P4-T1 必须收成单一 mounted-fact writer，不能保留双写。
- 同一个 ImmersiveSpace 已打开时切 `.library/.calibration/.practice` 不会再次触发 `ImmersiveView.onAppear/onDisappear`。因此只重配 AR providers 不够：进入/离开 calibration 时还要启动/停止 `CalibrationGuideViewModel` 的 polling/capture，离开 Practice/Virtual Piano 时还要取消 localization/guidance/hand consumer 等 mode-specific runtime。P4-T1 必须显式迁移这些 runtime side effects，不能等 scene lifecycle 偶然补触发。
- Library 目前没有 `openImmersiveSpace` 路径。
- `ARTrackingService.deviceWorldTransform(...)` 已能从 WorldTrackingProvider 查询当前设备 pose。

### Files

Expected:
- Add: `HappyPianistAVP/ViewModels/Shared/ImmersiveSpacePresentationCoordinator.swift`
- Add: `HappyPianistAVP/Models/Immersive/ImmersiveSpacePresentationContracts.swift` (or an equivalently neutral shared location)
- Update: `HappyPianistAVP/Services/Practice/Session/PracticeSessionContracts.swift` to remove the misplaced Practice-prefixed immersive action enum/typealiases
- Update: `HappyPianistAVP/ViewModels/AppState.swift`
- Update: `HappyPianistAVP/Services/ARSession/ARTrackingService.swift` (incremental provider reconciliation；retain world provider across mode switches)
- Update: `HappyPianistAVP/Services/ARSession/ARTrackingServiceProtocol.swift`: add the one production lifecycle fact `worldTrackingGeneration` and **remove protocol-only leaks with no production consumer** (`activeRequirements`, `authorizationStatusByType`)；the concrete service may keep private desired-requirement/authorization bookkeeping internally
- Update: `HappyPianistAVP/Models/Immersive/ImmersiveModels.swift` to represent the real `.paused` provider state
- Update provider-state consumers: `PracticeLocalizationViewModel.swift` / `ARGuidePracticeViewModel.swift`, `VirtualPianoPlacementViewModel.swift`, `CalibrationGuideViewModel.swift`
- Update: `HappyPianistAVP/ViewModels/Practice/Launch/ARGuidePracticeViewModel.swift`
- Update: `HappyPianistAVP/ViewModels/Practice/Launch/PracticeLocalizationViewModel.swift`
- Update: `HappyPianistAVP/ViewModels/ARGuideViewModel.swift`
- Update: `HappyPianistAVP/ViewModels/LiveAppGraph.swift`
- Update: `HappyPianistAVP/Views/Shared/ImmersiveActionAdapters.swift`
- Update: `HappyPianistAVP/Views/HappyPianistAVPApp.swift`
- Update: `HappyPianistAVP/Views/PianoChoose/RealPiano/CalibrationStepView.swift`
- Update: `HappyPianistAVP/Views/PianoChoose/VirtualPiano/VirtualPianoPreparationView.swift`
- Update: `HappyPianistAVP/Views/PianoChoose/PreparationWindowRootView.swift`
- Update: `HappyPianistAVP/Views/Practice/Step/PracticeStepView.swift`
- Update: `HappyPianistAVP/Views/Practice/PracticeWindowRootView.swift`
- Update: `HappyPianistAVPTests/Tracking/ARTrackingServiceLifecycleTests.swift` and `ARGuideImmersiveLifecycleTests.swift`
- Update protocol test doubles in `PracticeLocalizationViewModelTests.swift`, `CalibrationFlowViewModelTests.swift`, `ARGuideImmersiveLifecycleTests.swift` with the real `worldTrackingGeneration` fact；do not give the protocol a default implementation that hides missing lifecycle behavior
- Update relevant Calibration/VirtualPiano/Practice provider-state/lifecycle tests
- Update: `docs/architecture.md` in this same task with the new single mixed ImmersiveSpace presentation owner, mounted-scene fact ownership, explicit mode-transition runtime hook, and incremental AR provider lifecycle；do not defer these owner changes to P4-T3
- Add focused coordinator tests

### Implementation

1. Add `.library` to `AppState.ImmersiveMode`.

2. Replace—not copy—the old open/close/recover workaround with one shared `@MainActor` coordinator.

The coordinator owns no SwiftUI Environment action permanently. Calls receive the existing open/dismiss handlers and serialize exactly one in-flight scene operation.

Mode publication rules are explicit:
- **already mounted/open**: switching `.library/.calibration/.practice` captures `oldMode`, publishes the target mode once, then explicitly reconciles both mode-specific runtime ownership and AR requirements；no new `openImmersiveSpace` call and no expectation that `onAppear/onDisappear` will run again；
- **closed -> open(targetMode)**: save the previous mode, set/publish `targetMode` **before** invoking the open action so `ImmersiveView.onAppear` starts the correct runtime on its first lifecycle callback；if the action returns `.userCancelled/.error` and the scene did not mount, restore the previous mode；
- if `sceneDidAppear` has already established the scene despite an unusual action-result ordering, mounted lifecycle fact wins；do not roll back a live scene；
- close never changes the product mode just to manufacture a state transition；`sceneDidDisappear` owns the mounted `.closed` fact。

Calls:

- `open(mode:using:)`
- `close(using:)`
- `sceneDidAppear()` / `sceneDidDisappear()` reconciliation from the real `ImmersiveView` lifecycle。

The installed visionOS 27.0 SDK exposes `OpenImmersiveSpaceAction.Result` as `.opened / .userCancelled / .error` and `dismissImmersiveSpace()` as async. Treat those action completions as **request outcomes**, while the actual `ImmersiveView.onAppear/onDisappear` callbacks are the mounted facts. Do not infer mounted state by polling or by assuming `.opened` is itself the View lifecycle callback.

`AppState.ImmersiveSpaceState` is reduced to mounted facts (`closed/open`) or an equivalent minimal representation. Transition-in-progress lives only in the coordinator's private task, not as a second public state machine. Concurrent callers await/serialize through that task. There is no `recoverIfStuck()`, recursive retry, arbitrary yield count or forced reset-to-closed branch。

Delete the existing `HappyPianistAVPApp` outer `.onAppear/.onDisappear -> appState.immersiveSpaceState` writes in this same task. The existing `ImmersiveView.onAppear/onDisappear -> ARGuideViewModel` chain becomes the only mounted-scene adapter and forwards the fact to the shared coordinator exactly once.

3. Practice/calibration/virtual-piano placement and every current View caller migrate to this coordinator in the **same task**.

Route scene actions through one ARGuideViewModel runtime façade backed by the coordinator so Library/Calibration/Practice do not each manipulate `AppState` directly. Reuse the existing `ImmersiveView.onAppear/onDisappear -> ARGuideViewModel.onImmersiveAppear/onImmersiveDisappear` chain as the **only** mounted-scene adapter: those ViewModel lifecycle methods notify `sceneDidAppear/sceneDidDisappear` and then perform full-scene start/teardown work. Do not add a second scene observer or let `ImmersiveView`/App root write `AppState` directly. Delete the old duplicated methods from `ARGuidePracticeViewModel` and change callers directly; no forwarding wrappers for `openImmersiveForStep / closeImmersiveForStep / recoverImmersiveStateIfStuck` remain。

For **mode changes while the scene remains mounted**, add one neutral `ARGuideViewModel` mode-transition entry point (exact name may follow the implementation) receiving `oldMode/newMode`. It owns the current runtime side effects instead of scattering them across Views:
- leaving `.calibration` cancels calibration support polling/capture through the existing calibration shutdown/stop APIs；entering `.calibration` starts the existing calibration guide lifecycle after provider reconciliation is requested；
- leaving `.practice` cancels Practice localization, virtual-piano guidance/input consumers, recording/AI runtime that is practice-owned, without stopping the retained world provider merely to enter Library；
- entering `.practice` starts only the runtime required by the selected piano mode and existing Practice lifecycle；
- entering `.library` owns no calibration/practice/virtual-piano task and reconciles to world-only tracking；
- no mode-specific task is allowed to survive after its mode loses ownership, and no mode switch waits for a future scene `onAppear` that will not happen。

This is not a second state machine: `AppState.immersiveMode` remains the one product mode fact, while the transition entry point only performs deterministic exit/enter side effects for the old/new values.

The platform action contracts are shared infrastructure, not Practice contracts. In the same task rename/move:
- `PracticeImmersiveOpenResult` -> `ImmersiveSpaceOpenResult`；
- `PracticeImmersiveOpenHandler` -> `ImmersiveSpaceOpenHandler`；
- `PracticeImmersiveDismissHandler` -> `ImmersiveSpaceDismissHandler`；
- `makePracticeImmersiveOpenHandler / makePracticeImmersiveDismissHandler` -> neutral shared adapter names。

Remove the old definitions from `PracticeSessionContracts.swift` and update every caller directly；no compatibility typealiases.

4. Wire the shared coordinator through `LiveAppGraph` so Library can consume it later, but **do not expose a production Library button that opens `.library` yet**. P4-T1/T2 must not create a user-reachable blank ImmersiveSpace. P4-T3 exposes the action in the same task that installs real Spatial Book Flow/Spread content.

When P4-T3 exposes that Library action, it is **not** allowed to bypass an active Preparation/Practice lifecycle. Reuse the existing `PracticeLaunchViewModel.state/requestedSongID` plus existing return/preparation lifecycle facts to decide whether Library can summon/switch directly. If Practice is active/returning or a setup flow owns the current mode, the auxiliary Library surface must route the user to the existing finish/return/cancel action instead of calling `.practice/.calibration → .library` itself. Do not add a second `isPracticeActiveForLibrary` flag. P5/P6 own the sanctioned calibration/practice handoffs.

5. Every exhaustive `ARGuideViewModel` immersive-mode switch gains the real `.library` semantics, not a compile-only default:
- `onImmersiveAppear(.library)` -> `startTrackingIfNeeded()` only, no calibration guide；
- `trackingRequirementsForCurrentContext(.library)` -> world tracking only；
- no hand tracking / hand consumer；
- `handleHandTrackingUpdate(.library)` -> explicit no-op (normally unreachable because no hand provider is requested)；
- no calibration capture；
- no virtual-piano plane requirement。

**Mode switching while the same ImmersiveSpace stays open is a runtime event.** Every successful `.library ↔ .calibration ↔ .practice` mode change immediately runs the explicit old/new mode exit/enter hook above **and** reconciles the existing AR runtime (`startTrackingIfNeeded()` or its refactored equivalent); do not wait for another `onImmersiveAppear()` that will never happen.

Refactor `ARTrackingService.start(requirements:)` away from its current whole-`Runtime` restart on every requirements change. All current immersive modes continuously require `.world`, and current ARKit semantics allow an already-running session to `run(newProviders)` while keeping providers that are present in both the old and new arrays running. Also stop treating provider state as a value we can infer only from our own `run/stop` calls: one session-event task must reconcile actual ARKit provider/authorization changes.

The current single `sessionGeneration` cannot continue doing both jobs. Split the lifecycle conceptually into:
- **runtime identity/generation**: changes only on full ARKitSession/world-provider replacement；stable world/event/update tasks bind to this；
- **provider-reconcile request identity**: changes when desired requirements change；only the latest request may publish optional-provider ownership/state。

There is exactly one serialized reconcile task per runtime；never overlap `session.run(...)` calls on the same session. A newer requirements request may coalesce/cancel **pending intent that has not started mutating the session**, but once a `session.run(...)` mutation has begun it is awaited to settlement before the next reconcile. Request identity prevents stale completion from publishing superseded optional-provider ownership/state；do not treat task cancellation as rollback of an ARKit session mutation. `start(requirements:)` remains idempotent when desired requirements already match **and the required providers are actually healthy**；it must not early-return merely because a private desired value matches after an unexpected provider stop.

`Runtime` should own one stable `session + worldTrackingProvider`, plus replaceable optional hand/plane provider slots/tasks；do not create a second Runtime merely to re-enable an optional provider.

Therefore:
- keep one `ARKitSession` + the current `WorldTrackingProvider` alive across ordinary Library/Calibration/Practice mode changes；
- before each incremental run, compute authorizations required by **newly desired** supported providers；request/query them through the existing ARKit session, update private authorization bookkeeping, and omit/mark only denied providers as `.unauthorized`；Library→Calibration may therefore request Hand Tracking for the first time, and Virtual Piano plane enable may request world-sensing；do not restart the retained world provider just to request an optional-provider permission；
- call `session.run(desiredProviders)` to add/remove authorized optional providers while retaining that same world provider；
- when hand/plane is removed, cancel its update task and clear only its provider-derived state；
- because a stopped provider instance cannot be run again, re-enabling hand/plane creates a **fresh provider instance** and a fresh update task；
- do not cancel/recreate the world-anchor update task or clear `worldAnchorsByID` when world remains continuously active；
- one `sessionEventsTask` lives with the current Runtime and consumes `ARKitSession.events`；`authorizationChanged` updates `authorizationStatusByType`, and `dataProviderStateChanged` reconciles only provider instances that are still owned by this Runtime；cancel this task on full Runtime replacement/stop；
- add `.paused` to `ARTrackingProviderState` rather than collapsing Apple's distinct paused state into stopped；paused is non-ready but not a new provider generation；
- on **hand paused/stopped/removed**, immediately publish empty `fingerTipsSnapshot` + `handSkeletonSnapshot` through the existing relays so Calibration/Practice cannot consume stale user-hand facts；resume/new provider repopulates them from fresh updates；
- on **plane paused/stopped/removed**, make current placement UI non-ready and stop exposing stale confirmation geometry；clear the transient `detectedPlanes` presentation projection when it can otherwise keep an old disk visible, while provider-owned anchor cache may remain only if the same paused provider will resume and callers are gated on `.running`；
- on **world paused**, `deviceWorldTransform`/world-anchor mutation remain unavailable because state is not `.running`, but do not bump `worldTrackingGeneration` or erase the retained world-anchor cache solely for pause；
- Practice Localization treats `.paused` as recoverable/non-ready and keeps waiting inside its existing bounded startup/localization window；
- Calibration shows a temporary “追踪已暂停/等待恢复” state, clears any reticle-confirm readiness derived from stale hand data, and does not raise a permanent error；
- Virtual Piano hides/disables its plane confirmation interaction while required hand/plane provider is paused and shows a temporary waiting status；
- `ARGuidePracticeViewModel` status text distinguishes paused/stopped/disabled instead of routing them through a generic “初始化中”；
- update every exhaustive provider-state switch directly；do not hide `.paused` behind an unrelated `default`；
- unexpected `.stopped` for a provider that is still required makes that provider unavailable immediately；a stopped optional provider is discarded so the next enable creates a fresh instance；unexpected world stop/error invalidates the current world runtime and prevents `start(requirements:)` from early-returning as though tracking were healthy；
- do not keep a parallel hand-written provider-state truth: initialization/unsupported/authorization decisions may seed state before `run`, but once a provider belongs to the live session its `state`/session events are authoritative for running/paused/stopped；
- a true immersive-runtime suspend/stop or a `session.run` failure rebuilds the whole Runtime and clears all provider-derived caches before the next start；whenever the WorldTrackingProvider instance is replaced, increment `worldTrackingGeneration` exactly once；ordinary optional-provider reconcile leaves it unchanged；
- avoid one global generation bump that would accidentally kill the retained world update/event task when only hand/plane changes；use the runtime identity plus serialized reconcile/request identity and affected-provider task ownership as above。

This incremental reconcile is the basis for keeping `worldFromSpatialLibrary` stable across `.library/.calibration/.practice` mode switches. The same reconcile starts/stops the hand consumer and virtual-piano plane guidance exactly once. Do not create a Library-specific tracking owner or shadow `immersiveMode`.

### Failure behavior

- user cancelled -> Library auxiliary window stays available with retry and closed-open target mode rolls back when the scene never mounted；
- open error/unknown -> explicit retry state and the same no-mount rollback；
- no silent fallback to the old Window Book Flow；
- no recursive retry loop or `Task.yield()` transition recovery；a new user action may explicitly retry after a returned cancel/error。

### Tests

- open from closed -> transition/open result；
- user cancelled/error before mount restores the prior mode and leaves mounted state closed；
- sceneDidAppear-before-action-result ordering keeps the mounted scene/mode rather than rolling it back；
- sanctioned coordinator-driven `.library → .calibration → .practice` mode switches work without reopening the scene；
- mounted mode switches explicitly enter/exit calibration/practice/virtual-piano runtime even though `ImmersiveView.onAppear/onDisappear` do not fire again；leaving calibration leaves no polling/capture task, and entering calibration starts the guide without reopening the scene；
- Library summon action cannot directly hijack an active Preparation/Practice session or bypass save/cancel/return gates；
- each mode switch immediately reconciles provider requirements and hand-consumer ownership；
- real `ARKitSession.events` changes `providerStateByName` for initialized/running/paused/stopped and authorization changes；no stale hand-written `.running` survives a system/provider stop；
- hand pause/stop publishes empty finger/skeleton snapshots；plane pause makes confirmation UI non-ready；world pause preserves generation but rejects device-pose/world-anchor mutation until running again；
- `.world` provider/session identity remains continuous across ordinary mode switches；world anchors/device-space placement are not invalidated merely because hand/plane requirements changed；
- removed hand/plane provider state is cleared, and re-enable uses a fresh provider instance；
- rapid desired-requirements changes never overlap authorization/reconcile `session.run(...)` work and stale reconcile completions cannot restore superseded provider state；
- Library→Calibration first-use hand authorization and later plane authorization are requested when those providers enter desired requirements；denial affects only that provider's state and preserves healthy world tracking；
- full runtime stop/failure clears all caches and later localization waits for fresh world/anchor facts；
- concurrent open/close calls serialize through one transition task；
- `ImmersiveView.onAppear/onDisappear` are the only mounted-state writers and reconcile open/closed without polling；
- close；
- Practice existing lifecycle parity after replacement；
- `.library` requests world tracking without hand/plane requirements；
- full old-symbol scan for `recoverImmersiveStateIfStuck`, `PracticeImmersiveCloseCoordinator`, `.inTransition`, and direct App-root mounted-state writes is zero。

### Cleanup in this task

Delete:
- old Practice-only immersive state machine implementation；
- `ImmersiveSpaceState.inTransition`；全仓已确认它只服务被替换的旧 transition workaround；
- `recoverImmersiveStateIfStuck()`；
- `PracticeImmersiveCloseCoordinator`；它只串行化旧 `close + recover`，共享 coordinator 接管 close 串行化后没有独立职责；
- `HappyPianistAVPApp` 对 `immersiveSpaceState` 的外层 `.onAppear/.onDisappear` 直接写入；mounted fact 只保留 `ImmersiveView -> ARGuideViewModel -> shared coordinator` 一条路径；
- old open/close/recover closure plumbing in `PracticeLocalizationViewModel`；
- old `PracticeImmersive*` result/handler typealiases and `makePracticeImmersive*` adapter names after all callers migrate；
- `ARTrackingServiceProtocol.activeRequirements` and `.authorizationStatusByType` plus fake-only implementations；neither has a production consumer；
- stale tests that only encode the deleted yield/recover behavior。

Do not add:
- a second `immersiveSpaceState`；
- a Library-only open coordinator；
- compatibility flags。

### Gate

- targeted coordinator + Practice flow tests；
- ARTracking lifecycle tests prove same world provider/runtime remains while optional hand/plane requirements change, removed provider state clears, and full suspend/stop rebuilds cleanly；add focused tests for the production DataProviderState→`ARTrackingProviderState` mapping (`initialized/idle`, running, paused, stopped) and authorization-event mapping；where real ARKit events cannot be synthesized, keep the mapping as a small pure production helper and device-validate the event stream rather than inventing a mock-only session abstraction；
- `make build:simulator`。

**Atomic commit:** `refactor: P4-T1 - 共享 ImmersiveSpace 生命周期`

---

## P4-T2 建立 session-scoped Spatial Library world placement

**Goal:** Spatial Library 第一次出现时根据当前头部/设备 pose 放在用户面前，然后固定在那个世界位置，不继续 head-lock。

### Current source facts

现有 `ARTrackingServiceProtocol` 已提供：

`deviceWorldTransform(atTimestamp:)`

并且项目已经使用：

`ProcessInfo.processInfo.systemUptime`

作为 query timestamp。

当前 `KeyboardFrame` / virtual piano 代码已经证明世界 transform 采用同一 RealityKit / ARKit 坐标体系。

### Files

Expected:
- Add: `HappyPianistAVP/Models/SpatialLibrary/SpatialLibraryPlacement.swift`
- Add: `HappyPianistAVP/Services/SpatialLibrary/SpatialLibraryPlacementResolver.swift`
- Add: `HappyPianistAVP/ViewModels/Library/SpatialLibraryViewModel.swift`
- Update: `HappyPianistAVP/ViewModels/LiveAppGraph.swift`
- Add resolver/view-model tests

### Placement model

Store one session-scoped placement identity:

`(worldFromSpatialLibrary, worldTrackingGeneration)`

It is not a persistent WorldAnchor ID. The raw transform may be reused only while `ARTrackingService.worldTrackingGeneration` still matches and world tracking is running.

Pure resolver input:
- current device world transform；
- product placement parameters。

Output:
- level world transform for `SpatialLibraryRoot`；
- forward direction based on device yaw, not full head pitch/roll；
- root faces the user at placement time。

### Placement rules

Initial placement should:
- appear at comfortable reading/reach distance in front of the user；
- stay approximately level with world up；
- preserve enough horizontal width for 5–7 folios；
- never use raw gaze coordinates；
- never continuously follow the device after placement。

Exact distance/height values are product-tuning constants owned by the resolver, not scattered magic numbers in RealityView.

Simulator/device tuning may adjust the constants, but it must not change the ownership model.

### Lifecycle

`SpatialLibraryViewModel` owns:

- `.inactive`
- `.awaitingDevicePose`
- `.placed(worldFromSpatialLibrary)`
- `.placementFailed`

On entering library mode:
1. P4-T1 has already reconciled `.library` to world tracking；
2. run one cancellable, **time-bounded** placement task that checks the real world-provider state and queries a tracked device pose with explicit named local policy values **5 s timeout / 250 ms interval**（private/static constants on the Spatial Library placement owner or one tiny pure value type）；do not import/copy the Practice Localization state machine and do not add a generic readiness protocol；
3. provider `unsupported/unauthorized/failed` ends immediately with a typed placement failure；
4. first valid tracked pose resolves one root transform and publishes `.placed` once；
5. timeout produces explicit `placementFailed` + user retry。

This bounded hardware-readiness wait is load-bearing AR state, unlike the deleted ImmersiveSpace `Task.yield()` workaround. Do not add a generic readiness protocol, infinite polling or hidden identity/head-lock fallback just for this feature。

After placement:
- ordinary head motion does not recompute the root；
- ordinary `.library ↔ .calibration ↔ .practice` mode changes reuse the exact session root because P4-T1 keeps the same WorldTrackingProvider continuously active while reconciling optional hand/plane providers；
- before reuse, require matching `worldTrackingGeneration` and running world provider；
- `suspendImmersiveRuntime()` / app background, true ImmersiveSpace close, app reset, or any full world-runtime rebuild invalidates the stored placement generation；
- resume/re-entry or generation mismatch resolves a fresh device pose and places a new session root；do not assume raw world coordinates survive a WorldTrackingProvider replacement。

### No WorldAnchor in P4

Do not call `addWorldAnchor` for the library root.

Reason:
- Book Flow is summoned UI, not calibrated furniture；
- current RealityView world coordinates are enough for one immersive session；
- persistent anchor management would add lifecycle/storage cost without current product value。

### Failure behavior

If world/device pose is unavailable:
- show one explicit “无法定位空间曲库 / 重试” attached or auxiliary state；
- do not place at identity；
- do not head-lock as a hidden fallback；
- retry queries a fresh device pose。

### Tests

- yaw-only facing transform；
- ignores device pitch/roll for level placement；
- finite normalized basis；
- root remains unchanged after later device pose changes while worldTrackingGeneration is unchanged；
- same generation reuses placement across ordinary Library/Calibration/Practice mode switches；
- generation mismatch/full runtime replacement invalidates and re-places；
- retry after unavailable pose；
- reset on AR runtime suspend/background and full immersive close；
- ordinary mode switch without runtime suspension preserves placement；
- no persistent world-anchor calls。

### Gate

- pure placement tests；
- view-model lifecycle tests；
- `make build:simulator`；
- P4-T2 不暴露空白 Library route，因此本任务只验证 world transform / generation 生命周期；真实 summoned root 的 Simulator/device 可视验收在 P4-T3 接入 Spatial Library 实体后执行。

**Atomic commit:** `feat: P4-T2 - 建立空间曲库世界定位`

---

## P4-T3 用 RealityView Attachments 实现真正的 Spatial Book Flow / Book Spread

**Goal:** 每一本 folio 是独立空间对象；选中后，同一首曲谱在空间中展开为 Book Spread。

### Pre-implementation SDK check

Before touching Attachment API, follow `HappyPianistAVP/AGENTS.md` and verify the exact installed visionOS 27.0 `RealityView attachments` API with Apple docs.

Do not rely on remembered beta-era signatures.

### Files

Expected:
- Add: `HappyPianistAVP/Views/Library/SpatialLibraryAttachmentContent.swift`
- Add: one pure `SpatialBookDisplayMetrics.swift` (exact folder may follow existing Models/SpatialLibrary/SpatialScore ownership) for folio + open-Spread physical meter targets；do not duplicate separate P4/P5 scale constants
- Update: `HappyPianistAVP/Views/Library/LibraryWindowView.swift` to expose the production “进入空间曲库” action now that the spatial content exists；reuse the P4-T1 shared coordinator and lifecycle guard, do not create a Library-only opener
- Add: `HappyPianistAVP/Services/SpatialLibrary/SpatialLibrarySceneController.swift`
- Update: `HappyPianistAVP/Views/Shared/ImmersiveView.swift`
- Update: `HappyPianistAVP/Views/HappyPianistAVPApp.swift`
- Update: `HappyPianistAVP/ViewModels/LiveAppGraph.swift` only as needed to expose the already-created owners
- Update: `docs/architecture.md` in this same task only to extend the P4-T1 architecture with `SpatialLibrarySceneController` / Attachment ownership；the shared ImmersiveSpace coordinator and AR runtime lifecycle must already be documented by P4-T1
- Reuse: `LibraryBookFlowPresentation.swift`
- Reuse: `LibraryScoreFolioView.swift`
- Reuse: `GrandStaffNotationSpreadView.swift`
- Reuse: `SongLibraryViewModel` as the Library list/selection owner
- Reuse: P2/P3 `LibraryScorePreviewViewModel` as the prepared-score/page-navigation owner
- Reuse: P4-T2 `SpatialLibraryViewModel` as placement/lifecycle owner only
- Add scene/presentation integration tests where pure logic is testable, including physical-metrics/aspect/uniform-scale mapping

### Production entry becomes live in this task

The auxiliary Library Window may now expose “进入空间曲库 / 重试空间曲库” because this same task installs the Spatial Library attachments/controller. Opening it uses the P4-T1 shared coordinator; cancel/error stays in the auxiliary Window. Before opening/switching, honor the P4-T1 rule that an active Preparation/Practice lifecycle cannot be hijacked.

Empty library is a formal state: when `SongLibraryViewModel.entries.isEmpty`, do not expose/enable the Spatial Library entry action and do not create a placeholder/fake folio；the auxiliary Window keeps the existing MusicXML import empty state. If an already-open Spatial Library becomes empty after a legitimate list mutation, remove the score/folio attachments and close `.library` through the shared coordinator, returning the user to the auxiliary import/management surface. A later first import does not auto-open ImmersiveSpace；the user explicitly enters again.

There is no earlier blank `.library` product route and no feature flag for an empty placeholder implementation.

### Attachment architecture

Do **not** create one giant flat attachment containing the whole carousel.

Use independent attachment identities, but **only for a bounded visible slice** around the selected entry:

```text
SpatialLibraryRoot (RealityKit entity)
  ├─ visible folio(selected-3 ... selected+3), max ~7 attachment entities
  └─ selected Book Spread attachment entity
```

Do not instantiate every song in a large library as an Attachment. A pure visible-slice projection derives visible entry IDs from ordered `entries + selectedEntryID`; it has no separate selection owner.

SwiftUI content:
- folio surface = existing `LibraryScoreFolioView`；
- open score = existing `GrandStaffNotationSpreadView`。

### Physical display metrics

Spatial UI needs one explicit physical-size contract；do not let arbitrary Attachment point size, entity scale, P5 placement and per-view magic numbers all affect readability independently.

Add one small pure/named spatial display metrics value (location/name may be refined) that defines:
- target folio physical height/aspect in meters；
- target open Book Spread physical width/height derived from the canonical P2 page aspect/gutter；
- any common minimum readable scale constraint。

The actual starting constants are measured/tuned in Simulator then validated on physical AVP；do not claim ergonomic proof from Simulator. Convert the rendered Attachment bounds to the target physical size with **one uniform entity scale** at the spatial presentation boundary；do not assume an undocumented point-to-meter ratio and do not scale notation/layout internally a second time.

P5 reuses the same `SpatialScore` display metrics when moving the selected Spread to the keyboard. Position handoff must not silently resize the score. Only P5-T4 may add user-adjustable scale if real-device evidence proves the fixed product size is insufficient。

RealityKit controller:
- creates/owns one root entity；
- parents attachment entities under it；
- applies Book Flow transform/visibility from presentation state and applies the one named physical-size mapping at the attachment/entity boundary；
- never parses MusicXML or owns selection business state。

### Existing state owners enter ImmersiveView explicitly

Current `ImmersiveView` only receives `ARGuideViewModel`. Spatial Library needs additional existing state, but it must not duplicate it.

Wire the existing owners explicitly from `LiveAppGraph` / app composition root:

- `SongLibraryViewModel` -> entries, selectedEntryID, import/delete/audition facts；
- `LibraryScorePreviewViewModel` -> selected score preparation + Library spread navigation；
- `SpatialLibraryViewModel` -> session world placement only；
- `ARGuideViewModel` -> shared immersive/tracking/practice facts。

The exact `ImmersiveView` initializer may group these inputs into a small immutable dependency bundle if that is genuinely clearer, but do **not** create a new SpatialLibrary store that mirrors entries/selection/preview state.

No ViewModel should start polling another ViewModel to keep a shadow copy in sync.

### Book Flow geometry reuse

P1 `LibraryBookFlowPresentation` remains the geometric source:

- center item -> front facing；
- signed neighbors -> opposite yaw；
- distance -> lateral offset / depth / scale / opacity。

P4 maps those values to **real entity transforms**, not a second hand-written Cover Flow formula.

If P1 presentation model currently encodes 2D-only offsets, refine it in this task into one neutral spatial presentation value that both the Window-era tests and RealityKit mapping can consume; remove obsolete 2D-only members in the same task.

### Selection ownership

`SongLibraryViewModel.selectedEntryID` remains the one selected song.

Spatial Book Flow:
- gaze/hover visual feedback does not create a second selected ID；
- confirm on an off-center folio -> calls existing `selectEntry` and recomputes the bounded visible slice；
- confirm on center folio -> opens existing Library Book Spread preview；
- closing spread -> returns to the same selected folio；
- import/delete/list reload removes stale attachment IDs and recomputes from the repaired `SongLibraryViewModel` selection。

No mirrored `spatialSelectedSongID`.

### Interaction

Folio and Book Spread content remain SwiftUI attachments, so ordinary confirm controls use SwiftUI interaction/hover.

Book Flow also needs a lightweight horizontal browse gesture so libraries larger than the visible 5–7 items are actually navigable. Use one dedicated Book Flow interaction entity/surface with `CollisionComponent + InputTargetComponent` and an entity-targeted horizontal `DragGesture` after verifying the installed visionOS 27.0 API. The gesture owns only transient drag/progress; on threshold/end it commits previous/next through the existing `SongLibraryViewModel.selectEntry` path. It never owns a second selected index.

The drag interaction surface must sit behind/around the folio hit targets (or otherwise use verified gesture routing) so it **does not steal ordinary SwiftUI attachment hover/tap/pinch** from the books/page-edge controls. A tap with insignificant horizontal translation remains a folio/button confirm, not a browse commit. Add a targeted interaction test/manual check for tap-vs-drag arbitration rather than fixing conflicts with gesture delays.

Off-center confirm remains a complete non-drag navigation path.

Do not add raw gaze coordinate handling or per-folio drag state.

Book Spread page turn reuses P3:
- left/right page edge controls；
- no horizontal free-scroll。

### RealityView update discipline

`RealityView.update` may:
- apply already-computed transform/visibility；
- attach/detach known entities。

It must not:
- parse score；
- build page plans；
- start unbounded async work；
- allocate heavy assets each frame。

All long-lived async work stays outside update and is cancelled/reset on immersive suspend/disappear.

### Mode isolation

When `immersiveMode != .library`:
- hide/detach Book Flow folios and Library-only interaction entities, but preserve `worldFromSpatialLibrary` across ordinary mode switches **only while the same AR tracking runtime remains continuous**；
- the selected Book Spread may be handed to P5's SpatialScore owner；
- calibration/practice overlays remain current owners of their modes；
- no spatial-library folio/interactions leak into practice。

A true ImmersiveSpace close **or immersive-runtime suspend/background** clears the raw Library placement. Ordinary P5/P6 mode handoffs do not suspend tracking and therefore return to the same root. After an AR runtime restart, Library re-places from a fresh device pose rather than trusting stale coordinates.

### Tests / validation

Automated:
- bounded visible slice (normally max 7), stable IDs and no duplicate attachments；
- folio/Spread attachment bounds map to named physical metrics with one uniform spatial scale；Library open/close does not introduce a second score-size path；
- first/last-entry slicing has no phantom items；
- large-library browsing reveals entries beyond the initial slice by off-center confirm and targeted drag；
- import/delete/list replacement removes stale attachments and follows repaired selection；
- empty list produces no fake folio and no blank persistent Spatial Library；open library becoming empty closes through the shared coordinator；
- center/neighbor transform mapping；
- ImmersiveView consumes the existing Library/preview owners rather than copied state；
- selection uses `SongLibraryViewModel.selectedEntryID`；
- opening/closing preview keeps identity；
- mode change tears down root；
- no duplicate selection state。

Simulator/device:
- 5–7 folios show real depth；
- moving the head does not make the group follow the face；
- center confirm expands the dynamic Book Spread in place；
- page turn works in space；
- no giant rectangular “app window” appearance。

### Gate

- targeted Spatial Library tests；
- Library/Notation tests；
- `make build:simulator`；
- visual Simulator/device walkthrough。

**Atomic commit:** `feat: P4-T3 - 空间化 Book Flow 与 Book Spread`

---

## P4-T4 让 Spatial Library 成为核心选曲界面，收口 Window 辅助职责

**Goal:** P4 完成后不再同时维护 Window Book Flow 和 Spatial Book Flow 两套核心产品路径。

### Current product boundary

复杂工具允许继续存在于普通 Window：
- MusicXML import + existing conflict/cancel transaction UI；
- imported-song management / destructive delete；
- local audio binding/import for scores that have no `audioFileName` (`bindAudio`)；
- diagnostics；
- piano setup / troubleshooting；
- audition controls when useful。

核心选曲与看谱：
- Spatial Book Flow；
- Spatial Book Spread。

### Files

Expected:
- Update: `LibraryWindowView.swift`
- Update: `SongLibraryView.swift`
- Delete/reshape: Window-only `LibraryBookFlow.swift` container after its reusable folio/presentation pieces have moved to Spatial Library
- Update Library tests/previews
- Update `docs/architecture.md` only if actual scene ownership changes are not already represented
- Update `docs/data-flow.md` if Library presentation ownership materially changes

### Window role after migration

The Library Window becomes an **auxiliary launcher/management surface**, not a duplicate browser.

When Spatial Library is closed:
- offer explicit action to enter Spatial Library；
- offer MusicXML import / imported-song delete / local-audio binding / diagnostics / choose-piano management；
- management may use a compact ordinary list/rows, but destructive/audio-binding actions target the row entry ID directly；do **not** introduce a second management `selectedSongID` or turn this list into another core browser；
- management actions must not change `SongLibraryViewModel.selectedEntryID` merely to obtain a target；the existing spatial/core selection remains authoritative；
- show open-error/retry state if immersive presentation failed。

When Spatial Library is open:
- do not render a second Book Flow beneath it；
- 有效世界定位后关闭辅助 Window，不允许管理面板与空间书册持续叠加；空间小型管理按钮通过真实 scene close 回到管理 Window，定位失败恢复重试入口；
- selected song identity still comes from the same `SongLibraryViewModel`。

### Interim start-practice action

P4 is not yet responsible for keyboard-relative score placement.

Until P5 lands:
- starting Practice may still be invoked from the auxiliary window for the currently selected song；
- do not create a fake “score flies to piano” transition in P4；
- P5 will take over the spatial handoff。

This is a staged implementation dependency, not a permanent fallback path.

### Lifecycle

- immersive open -> Spatial Library is authoritative browser；
- system closes immersive -> auxiliary window can reopen/retry the spatial library；
- scene inactive/background -> shared immersive suspend stops AR tracking and invalidates raw Spatial Library placement；resume gets a fresh world/device pose before showing Book Flow；
- return from Practice before P5 -> selected song remains consistent。

### Cleanup in this task

Remove production use of:
- Window Book Flow container；
- duplicate center-selection behavior；
- duplicate selected-folio confirm flow；
- carousel-specific `LibraryBookFlowDragConfiguration` / `LibraryDeletionHoldPolicy` and their tests once the Window drag-delete UI is gone。

Before deleting that drag/hold path, move **imported-song deletion** into the auxiliary management surface with an ordinary destructive action + explicit system confirmation. It calls the existing `SongLibraryViewModel.deleteEntry()` so bundled protection, import-active gating, file/index/progress consistency and selection repair remain the one business safety boundary. Do not preserve long-hold or down-drag semantics merely for compatibility.

Retain only reusable:
- folio view；
- Book Flow pure presentation；
- preview/progress owners；
- import/playback/data services。

No feature flag for “2D vs Spatial Library”.

### Acceptance

- there is one core song-browsing path；
- Library Window no longer presents a full duplicate carousel；
- MusicXML import/conflict handling, imported-song delete, audio binding/import, audition, diagnostics and setup still reachable；
- bundled entries cannot be deleted and import-active deletion remains blocked by the existing ViewModel/service checks；
- opening immersive failure has a clear retry path；
- selected song survives spatial open/close；
- no new persistent storage introduced。

### Gate

- Library lifecycle tests；
- immersive coordinator tests；
- `make build:simulator`；
- manual flow: auxiliary window -> Spatial Library -> browse -> open spread -> close -> return；
- empty library keeps only auxiliary import UI；deleting/mutating to zero entries closes the open Spatial Library cleanly；
- manual failure path: cancel immersive open -> retry。

**Atomic commit:** `refactor: P4-T4 - Spatial Library 接管核心选曲`

## 本轮实际证据（2026-10-01）

- P4-T3 接手前次未提交实现，用户明确授权修改并提交；代码提交 `41ed9140c0eb675b8fdf663d4a6ce4a024db726a`。计划/状态未加入提交。
- 当前 Xcode 27.0 beta、visionOS 27.0，继续使用已有 AVP `28DABA38-C30B-44B1-9C2B-65D50F7FCC55`，不创建新设备；物理 AVP 当前 unavailable。
- Apple docs 核对 `RealityViewAttachments`、`entity(for:)`、`EntityTargetValue` 与坐标转换契约。命名 metrics 将实际 Attachment bounds 映射为唯一 uniform scale；folio 0.30m、spread 0.42m 高是 Simulator 起始常量，非真机舒适度结论。
- `make build:simulator` 通过。首轮 `.build/TestResults/P4-T3.xcresult` 为 7 个测试、12 次参数化执行；扩大 `.build/TestResults/P4-T3-Regressions.xcresult` 为 12 个测试、17 次执行（包含 5 个 serialized native 内容测试），全部通过。
- 扩大命令最初部分函数筛选未命中；未把它们计入结果。随后直接 `xcodebuild test` 用包含括号的正式标识补跑 `.build/TestResults/P4-T3-Boundaries-Actual.xcresult`：8 个测试、13 次执行全部通过，覆盖 placement/generation/retry、预览取消、失败保存/明确丢弃生命周期与 capture route。
- `rtk make` 对成功 Swift 编译输出显示误导性 error，后续直接原生 `make/xcodebuild`；`.xcresult` 是真实结果证据。Make 的 ONLY_TESTING 插入未转义括号会 shell syntax error，改为直接 xcodebuild 的独立带引号参数，不修改无关构建脚本。
- 已增加 DEBUG-only `--ui-capture spatial-library/spatial-spread` 复用生产 open/preview owners，未注入 synthetic tracking 或伪造曲谱。`/tmp/hp-p4-spatial-flow-loaded.png` 实际捕获世界空间双页与辅助管理 Window；不以截图证明点击/拖动已通过。
- Peekaboo 在本机 `--no-remote` 路径对新版 Device Hub 仍报稳定窗口代缺失，无法可靠操控。用户已同意安装完成后协助确认 folio 点击、横向拖动、页缘翻页与关闭重进；这些交互验收仍待实际确认。
- T4 与 T3 的实体内容依赖已满足，可在同一阶段先完成辅助管理迁移；P4 审计 Go 之前不进入 P5。
- P4-T4 代码提交 `0ab530210e4b5cae712dce6d7d8c31a5eba11aac`；旧 Window carousel、Window score preview、下拖长按删除与独占测试删除。`.build/TestResults/P4-T4-Actual.xcresult` 21 tests / 26 executions PASS，含 row ID 操作不改 selection、内置保护、真实 repository 清理与导入/scene gate；build PASS。
- 审计 F-01 先用实际 Observation 回归复现通知计数0，再在唯一 ARTrackingService 上修复 Observation，protocol existential consumer 同样覆盖；F-02 把 reconcile 任务/cleanup 固定到捕获的 runtime；F-03 用实际倾斜 folio 包围盒证明原后方 input plane 不够深，改为正式 metrics 推导；F-04 在 ImmersiveView 汇聚点收口 Library/Calibration/Practice renderer ownership，避免 retained Guide/anchors/异步演示手加载泄漏。
- 全量 `.build/TestResults/P4-Full.xcresult`：1090 tests，1078 PASS / 12 FAIL / 0 skipped。与 `.build/TestResults/Page-Curl-Full-Recovered-1790838585.xcresult` 的失败 ID 集合完全一致，新增/消失均为空；当前一个 motion 测试记录为 Swift Testing runner crash，不能把相同 ID 解释为所有失败机制已经查清。失败集中于既有 motion/rig、sampler 与标准谱面 golden，未修改 golden/弱化断言掩盖它们。
- Xcode 全量测试尾部自己的 `simctl diagnose --timeout=600` 停滞；核对 PPID 属于本轮 xcodebuild 后仅 TERM 该诊断子进程，保留真实全量结果。没有停止测试进程、重启设备或共享服务。
- 审计根因修复提交 `a2f66929d9eee5942ae520bfa7850a475cce6c8f`。最终 `.build/TestResults/P4-Final-Targeted.xcresult` 20 tests / 25 executions、0 failed/skipped；protocol existential Observation 与 Guide 实体 reset 通过，最终 build PASS。最新 App 已安装到原 AVP Simulator 并启动，等待用户实际交互反馈，未把该等待标记为完成。

---

## P4 Phase completion checklist

Before P5:

1. `.library` uses world tracking only.
2. There is one shared immersive open/close state machine.
3. Spatial Library root is session world-fixed, not head-locked.
4. No persistent WorldAnchor exists for Book Flow.
5. Every folio is an independent spatial attachment/entity, not one fake flat carousel.
6. Selection still has one owner: `SongLibraryViewModel.selectedEntryID`.
7. Spatial and Window Book Flow are not both production core paths.
8. Book Spread preview/page-turn reuses P2/P3 rather than duplicating notation.
9. RealityView update contains no parsing/I/O/heavy work.
10. P4 does not claim keyboard-relative placement or full spatial Practice.
