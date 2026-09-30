# Plan P5 - Spatial Score Placement：把 Book Spread 放到现实钢琴上方

**Goal:** 当用户从 Spatial Library 进入真实钢琴练习时，同一份 Book Spread 不消失、不重新创建成另一套 UI，而是从曲库位置自然迁移到已校准现实钢琴的 keyboard-relative 位置。

**Visual acceptance references:**
- `.github/features/spatial-2026-09-30/设计稿/images/03-现实钢琴-MIDI准备.png`
- `.github/features/spatial-2026-09-30/设计稿/images/04-正常练习.png`

03 用于约束“用户自己的现实琴 + 现有校准/准备链”的产品关系；P5 不重做校准 UI。04 用于验收双页 Book Spread 相对现实钢琴的位置、朝向、阅读距离和 handoff 结果。

**Primary product modes:**
- Real Audio piano；
- Bluetooth MIDI piano。

两者已经共用真实钢琴校准，所以本 phase 不新增 Bluetooth 空间坐标模型。

**Non-goals:**
- 不重新做 A0/C8 calibration。
- 不检测现实中的物理谱架。
- 不做 scene understanding 自动识别“这里是谱架”。
- 不给 score 创建独立 persistent WorldAnchor。
- 不做 Companion Hands / Piano Guide 整体整合；那是 P6。
- Virtual Piano 不作为本 phase 产品验收目标；若它因同一 `PianoKeyboardGeometry` 自然兼容，不额外禁止，也不增加专用分支。

**Core transform model:**

```text
worldFromScore
  =
worldFromKeyboard
  ×
keyboardLocalScoreTransform
```

ARKit/Calibration owns `worldFromKeyboard`.

Spatial Score placement owns only `keyboardLocalScoreTransform`.

---

## P5-T1 建立 canonical keyboard-relative score placement model / resolver

**Goal:** 给现实钢琴定义一套稳定、可测试的“乐谱应该放在哪里”的本地坐标规则。

### Current source facts

Current `KeyboardFrame`:
- origin = A0 front-edge line；
- +X = A0 -> C8；
- +Y = world up；
- +Z = right-handed convention，源码明确说明“不保证朝向用户”。

Current `PianoCalibration.frontEdgeToKeyCenterLocalZ`:
- already resolves which side of keyboard is the instrument interior using the device pose during runtime calibration；
- sign therefore carries the stable playing-side relationship for the current calibrated keyboard。

Current `PianoKeyboardGeometry`:
- contains `frame`；
- contains all key local centers/sizes；
- can derive actual keyboard horizontal center / top surface。

### Files

Expected:
- Add: `HappyPianistAVP/Models/SpatialScore/SpatialScorePlacement.swift`
- Add: `HappyPianistAVP/Services/SpatialScore/SpatialScorePlacementResolver.swift`
- Update: `HappyPianistAVP/ViewModels/AppState.swift` runtime calibration side-resolution semantics
- Update: `HappyPianistAVP/ViewModels/Practice/Launch/PracticeLocalizationViewModel.swift` + `ARGuidePracticeViewModel.swift` presentation mapping for the new typed recoverable failure
- Add: direct AppState/calibration-side tests plus focused `HappyPianistAVPTests/SpatialScore/` placement tests
- Update: `PracticeLocalizationPolicyTests.swift` / localization VM tests

### Model

Define a pure keyboard-local placement value.

Keep the first implementation intentionally constrained:

- local X translation；
- local Y translation；
- local Z translation；
- optional fixed/readability pitch profile owned by product defaults；
- use the fixed `SpatialScore` physical display metrics established in P4；uniform **user-adjustable** display scale is added only if actual physical-AVP validation proves that fixed product size is insufficient。

Do not expose arbitrary roll.

Do not persist a world transform.

### Player/interior side

Resolver input:
- `PianoKeyboardGeometry`；
- `PianoCalibration`；
- optional persisted user offset。

Use `frontEdgeToKeyCenterLocalZ` sign as the formal calibrated interior-side fact.

Fix its source invariant in this task: `AppState.resolveRuntimeCalibrationFromTrackedAnchors()` must no longer return `.resolved` with `frontEdgeToKeyCenterLocalZ == 0` when the current device pose cannot establish the player/interior side. Compute the signed device separation along `KeyboardFrame.zAxisWorld`; a clearly positive/negative side yields ±key-depth/2, while a non-finite/near-zero ambiguous side returns a new typed recoverable calibration-resolution result (for example `playerSideAmbiguous`) instead of writing zero and claiming success. The minimum side-separation threshold is one named calibration/localization constant validated by geometry tests/device evidence, not a scattered epsilon.

Score default belongs:
- centered horizontally over the keyboard；
- above key top surface；
- toward keyboard interior, away from the player；
- facing the player。

`SpatialScorePlacementResolver` accepts only a formally resolved nonzero interior-side sign. A zero/ambiguous value is rejected as an invariant violation/unresolved placement, but ordinary production localization should now surface the typed `playerSideAmbiguous` result **before** publishing such a calibration.

The pure resolver performs **no AR query itself**. Practice Localization owns recovery. Thread the new fact all the way through the existing localization contract:
- add `playerSideAmbiguous` (or final equivalent name) to `AppState.PracticeCalibrationResolutionResult`；
- add the corresponding `PracticeLocalizationFailure` presentation case rather than collapsing it into `providerNotRunning`；
- `runPracticeLocalization` treats it as a recoverable localization result and keeps polling inside the existing bounded localization window；
- `practiceLocalizationTimeoutFailure(...)` maps the last ambiguous-side result to the dedicated failure case；
- `ARGuidePracticeViewModel.canRetryPracticeLocalization` returns true for it；
- status/action text tells the user to return to the playing side / face the keyboard and retry；
- retry uses the existing `retryPracticeLocalization(...)` path, with no new retry coordinator。

Do not add a score-placement-specific pose query or ±Z fallback.

Do not add an arbitrary +/-Z fallback.

### Canonical defaults

Default height/depth/pitch are named product constants in this resolver.

They are tuned by Simulator/device acceptance, not scattered literals in RealityView.

The resolver returns:
- keyboard-local score transform；
- facing orientation；
- any normalized metadata needed for manipulation constraints。

### Tests

- center uses actual key geometry, not hardcoded 88-key width；
- +interior / -interior sign；
- score faces player for either raw KeyboardFrame Z convention；
- finite orthonormal transform；
- user offset applied in keyboard-local space；
- AppState positive/negative signed side -> matching ± key-center offset；
- AppState near-zero/ambiguous side -> typed recoverable failure, never `.resolved` with zero；
- Practice Localization retries that failure within its existing bounded window and maps timeout to an actionable message；
- direct resolver zero/ambiguous input -> explicit unresolved/invariant failure；
- changing world keyboard transform does not change local placement result。

### Gate

- pure placement tests；
- `make build:simulator`。

**Atomic commit:** `feat: P5-T1 - 建立钢琴相对乐谱定位`

---

## P5-T2 建立统一 SpatialScore owner，并持久化 keyboard-local 位置偏好

**Goal:** 不创建孤立 preference store；在本 task 就把 P4 的 selected Book Spread 迁到统一 `SpatialScoreSceneController / SpatialScorePlacementViewModel`，并让这个正式 production owner 读取 keyboard-local 用户偏好。Library 模式视觉行为保持不变，T3 再把同一个 owner handoff 到 KeyboardScoreRoot。

### Storage decision

Do not add fields to `StoredWorldAnchorCalibration` and do **not** create a Documents JSON business store for three UI placement offsets.

This is a user preference, so follow root `AGENTS.md`: use `UserDefaults`.

Reason:
- calibration anchor identity and UI placement preference are different facts；
- X/Y/Z offset is tiny UI preference state, not a business document；
- a JSON file + protocol + quarantine/recovery UI would be unnecessary persistence infrastructure。

### Files

Expected:
- Add: `HappyPianistAVP/Models/SpatialScore/SpatialScorePlacementPreference.swift`
- Add: one small concrete `HappyPianistAVP/Services/SpatialScore/SpatialScorePlacementPreferenceStore.swift` backed by injected `UserDefaults`
- Add: `HappyPianistAVP/Services/SpatialScore/SpatialScoreSceneController.swift`
- Add: `HappyPianistAVP/ViewModels/SpatialScore/SpatialScorePlacementViewModel.swift`
- Update: P4 `SpatialLibrarySceneController` so it no longer owns the selected Spread entity；it owns folios/library root only
- Update: `ImmersiveView.swift` / `HappyPianistAVPApp.swift` composition so the selected Spread is rendered through SpatialScore owner even in Library mode
- Update: `LiveAppGraph.swift` to compose the concrete store + placement owner；do not add a protocol/factory for one implementation
- Update: `docs/architecture.md` in this task with the new permanent ownership split
- Add focused store/owner tests with an isolated UserDefaults suite

### Ownership split becomes real in this task

After T2:

```text
SpatialLibrarySceneController
  owns folios + session Library root

SpatialScoreSceneController
  owns the one selected Book Spread attachment/entity

SpatialScorePlacementViewModel
  owns score placement mode + canonical resolver input + keyboard-local preference
```

In `.library` mode, SpatialScoreSceneController parents/places the spread relative to P4's valid Library root, so the user sees no behavior regression. It does **not** need keyboard geometry yet.

The placement ViewModel loads the preference once from the concrete store and exposes one in-memory value. There is no second copy in SwiftUI/RealityView. T3 consumes that same owner when keyboard geometry becomes available.

This migration removes P4's temporary selected-Spread ownership in the same task；do not leave both controllers able to attach/render the score.

### Persisted fact

Persist only the approved user-adjustable keyboard-local offset.

First version should prefer:
- translation X/Y/Z；
- only add tilt/scale if P5-T4 interaction actually exposes them。

Do not persist:
- world transform；
- WorldAnchor ID；
- song ID；
- current page；
- practice progress。

Current app stores one real keyboard calibration at a time, so first version stores one current real-keyboard placement preference rather than inventing multi-piano profiles.

### Preference behavior

Store only finite X/Y/Z values under versioned/namespaced UserDefaults keys (or one compact Codable Data value if that is demonstrably simpler).

- no stored value -> canonical default placement；
- missing/partial/non-finite value -> remove/reset the preference and use canonical default；
- reset action -> remove the keys；
- no quarantine file, migration framework, user-facing corruption recovery flow or diagnostic spam for this noncritical preference。

Do not invent a recoverable persistence error state around `UserDefaults.set`; this preference needs only value validation and reset semantics.

### Write cadence

Do not write on every drag frame.

Only persist:
- gesture end / explicit placement commit；
- reset-to-default action。

### Tests

- Library mode selected Spread is owned/rendered by SpatialScore controller after migration, not both controllers；
- closing/opening Library detail keeps the same selection/page facts while entity ownership is singular；
- missing keys -> no preference/default；
- round trip X/Y/Z；
- partial/non-finite value -> reset/default；
- reset removes keys；
- isolated UserDefaults suite does not leak test state；
- no world-coordinate/WorldAnchor/song/page persistence。

### Gate

- store + SpatialScore ownership tests；
- P4 Spatial Library regression tests；
- `make build:simulator`；
- Simulator Library Book Spread still opens/closes correctly through the new owner。

**Atomic commit:** `refactor: P5-T2 - 建立统一 SpatialScore owner 与位置偏好`

---

## P5-T3 从 Spatial Book Spread 直接开始练习，并 handoff 到 KeyboardScoreRoot

**Goal:** 复用 P5-T2 已经唯一拥有 selected Spread 的 SpatialScore owner；用户在空间乐谱上开始练习后，同一逻辑 attachment 从 Library placement 切到 keyboard-relative placement。

### Current source facts

- `PracticeSessionViewModel.keyboardGeometry` is the current runtime piano geometry。
- `keyboardGeometry.frame.worldFromKeyboard` is already used by:
  - Piano Guide；
  - Demonstration Hands；
  - Virtual Piano/performer placement。
- Real Audio and Bluetooth MIDI both require completed real-piano calibration。
- P4 owns the Spatial Library root/folios；P5-T2 has already moved the selected Book Spread to the one `SpatialScoreSceneController` owner。

### Files

Expected:
- Reuse/Update: P5-T2 `SpatialScoreSceneController.swift` / `SpatialScorePlacementViewModel.swift`
- Add: `HappyPianistAVP/ViewModels/SpatialScore/SpatialPracticeLaunchCoordinator.swift` or an equivalently narrow navigation coordinator
- Update: `ImmersiveView.swift`
- Update: `HappyPianistAVPApp.swift`
- Update: `LibraryWindowView.swift` / spatial Book Spread attachment actions
- Update: `PreparationWindowRootView.swift`
- Update: `PracticeWindowRootView.swift`
- Update: `LiveAppGraph.swift` only for the launch coordinator/handoff dependencies；do not recreate owners already composed in T2
- Update: `docs/architecture.md` in this same task with Library→KeyboardScore handoff/lifecycle；SpatialScore ownership itself was already documented in T2
- Update Practice/Library integration tests

### Existing ownership from T2

T2 already guarantees:

```text
SpatialLibrarySceneController -> folios / library root
SpatialScoreSceneController   -> selected Book Spread attachment
```

T3 changes **placement + navigation/content authority during Practice**, not entity ownership architecture.

Library mode:
- score controller places spread near library root。

Practice mode:
- the same **logical Spatial Score presentation identity** moves to `KeyboardScoreRoot`。

While the same ImmersiveSpace/world generation stays alive, reuse the same attachment/entity instead of destroying and recreating it.

If the system itself closes/recreates the immersive scene, reconstruct the attachment from the same selected song / score revision facts. The invariant is “one logical score state”, not “one Entity instance survives every system teardown”.

Do not create a second notation/navigation owner on mode transition.

### KeyboardScoreRoot

Create one RealityKit root entity whose transform is:

`keyboardGeometry.frame.worldFromKeyboard`

The score attachment is its child and uses P5-T1 local transform while preserving the same named physical Book Spread size from P4；Library→Practice handoff changes placement, not score size.

No score WorldAnchor.

When calibration/localization updates `keyboardGeometry.frame`:
- update KeyboardScoreRoot world transform；
- child local preference stays unchanged。

### Spatial “开始练习” route

The final product must not require the user to return to the ordinary Library Window just to start the selected spatial score.

Add one score-attached “开始练习” action.

The narrow `SpatialPracticeLaunchCoordinator` owns only a pending launch identity/lifecycle:

- selected song ID；
- score file/version identity；
- whether the launch came from Spatial Library；
- one minimal presentation stage: `awaitingPreparation` or `awaitingPracticeActivation`。

Do **not** use a generic `consumed` boolean: Preparation dismissal and successful Practice activation are different facts. Successful spatial handoff clears the coordinator entirely；cancel/return/identity invalidation also clears it after restoring Library presentation.

It does **not** own:
- Library selection；
- Practice session；
- calibration；
- immersive open/closed state。

#### Setup already ready

1. validate the currently open spatial preview still matches the selected song/version；
2. call the existing `SongLibraryViewModel.startPractice(entryID:perform:)` gate so import-active and missing-entry protection stay centralized；inside its `perform`, register the pending spatial launch and call the existing `PracticeLaunchViewModel.request(songID:)`；
3. open/push the existing Practice auxiliary Window because it still owns alerts, save/return lifecycle and advanced tools；
4. keep the current ImmersiveSpace alive；
5. once Practice activation publishes matching prepared state + keyboard geometry, switch shared immersive mode to `.practice` and perform score handoff。

#### Setup not ready

1. retain the pending spatial launch identity；
2. open/push the existing Preparation Window；
3. reuse the existing PianoTypePicker / Bluetooth MIDI / A0-C8 calibration flow；
4. while calibration mode is active, hide/park the selected score rather than inventing score-only calibration；
5. on successful “完成设置”, if a pending spatial launch still matches the selected song/version:
   - dismiss Preparation；
   - request the existing Practice launch；
   - open/push the Practice auxiliary Window；
   - transition the **already-open shared ImmersiveSpace** from calibration to practice instead of unconditionally tearing it down first。

If preparation was opened independently from the auxiliary Window and there is no pending spatial launch, preserve its existing standalone completion behavior.

For a pending spatial launch, `PreparationWindowRootView` also handles system/user dismissal:
- successful `finishSetup` changes the coordinator from `awaitingPreparation` -> `awaitingPracticeActivation` **before** dismissing the Preparation Window, then requests/opens Practice；
- `onDisappear` treats only a still-`awaitingPreparation` launch as cancelled, invalidates it, unparks/restores the selected score, switches the still-open ImmersiveSpace back to `.library`, and reconciles world-only tracking；
- `awaitingPracticeActivation` means Preparation completed successfully, so that same `onDisappear` is not a cancellation signal；
- no pending spatial launch -> existing standalone window disappearance behavior remains unchanged。

If the selected score/file version changes while preparation is in progress:
- invalidate the pending launch；
- return/keep the spatial presentation in Library mode；
- do not start the stale song automatically。

### Remove the old Window start-practice path in this task

P4 kept the Library Window start-practice button only as a temporary bridge. Once the spatial score-attached action above is working, delete the old core launch chain in the **same task**:

- `SongLibraryView` bottom “开始练习” button；
- `onStartPractice` closure plumbing through `LibraryWindowView` / roots/previews；
- Window-side `pushWindow(id: WindowID.practice)` launch action and tests that exist only for that button。

Keep and reuse `SongLibraryViewModel.startPractice(entryID:perform:)` because its import-active/existing-entry guard is still the one business gate；it is no longer a Window-specific helper.

No “2D start vs spatial start” feature flag remains.

### Practice lifecycle change required for seamless handoff

Current code closes ImmersiveSpace in:
- `PreparationWindowRootView.finishSetup()`；
- `PracticeWindowRootView.activateCurrentRequest()` before activation。

For a valid pending spatial launch, refactor these unconditional closes so the P4 shared immersive coordinator can switch `.library → .calibration → .practice` within the same open mixed ImmersiveSpace.

Do not duplicate the open/close state machine.

The existing non-spatial/system-disappear/save-failure paths may still close the immersive space when that is their correct lifecycle outcome.

### Score handoff

When `PracticeLaunchViewModel.state` publishes `.ready(preparedIdentity)` for the pending spatial song/version and:
- selected song / score revision matches the spatial preview；
- `keyboardGeometry` is ready；

then:
1. capture the current Library spread index as the transition start presentation；
2. only after matching Practice activation succeeds, explicitly close/cancel the `LibraryScorePreviewViewModel` prepared/navigation lifecycle for that opened detail so late preview prepare/history/navigation updates cannot continue driving the shared attachment；
3. bind the same logical Spatial Score attachment to Practice's P3 page plan/navigation facts and let Practice become the sole authoritative spread owner；
4. compute current world transform of score；
5. compute target world transform from KeyboardScoreRoot + local placement；
6. animate one controlled transition if Reduce Motion is off；
7. reparent/settle under KeyboardScoreRoot without visual jump；
8. hide Spatial Book Flow folios for Practice。

If Practice activation publishes `.failure`, keep the coordinator in `awaitingPracticeActivation` so the **existing Practice retry action** can still succeed into the same spatial handoff；do not invent a second retry path. While not `.ready`, Library preview remains the content/page owner and the score stays parked/hidden according to the setup transition, never driven by Practice navigation.

If the user chooses the existing Return action, the Practice Window is dismissed before readiness, the selected song/version becomes invalid, or launch identity is superseded, cancel the pending spatial launch and restore the Spatial Library score/Book Flow. There is never a period where both preview and Practice navigation are authoritative.

After matching `.ready` + keyboard geometry completes the handoff, clear the launch coordinator；subsequent Practice retries/resume are ordinary Practice lifecycle, not a forever-retained spatial-launch flag.

Exact RealityKit move/reparent API must be verified against the installed visionOS 27.0 SDK / current Apple docs before implementation.

Reduce Motion:
- no flying animation；
- score directly appears at target placement。

### Setup / preparation invariant

If calibration / keyboard geometry is not ready:
- do not guess a score target；
- follow the spatial “开始练习” route above；
- once current official Practice localization publishes geometry, perform handoff。

Do not create a parallel “score-only calibration”.

### Return to library

When leaving Practice back to Library after save/finalization succeeds:
- if P4's stored `worldTrackingGeneration` still matches, move the Practice-owned Spatial Book Spread back toward that preserved `worldFromSpatialLibrary` placement (directly if Reduce Motion is on)；
- if the world generation changed during suspend/restart, **do not animate toward the stale transform**；first let P4 resolve a fresh Spatial Library placement from the current world provider/device pose, then settle/close the score at the newly selected folio；
- close it into the still-selected folio and return to Book Flow；
- keep `SongLibraryViewModel.selectedEntryID` unchanged；
- keep `LibraryScorePreviewViewModel` closed after the successful Practice handoff rather than resurrecting a second page owner just for return；the user can confirm the selected folio to open detail again；
- release Practice navigation/content binding and remove `KeyboardScoreRoot`；
- P6 owns the final save/order/window-dismiss details, but this presentation target is fixed here。

### Tests

- spatial Start Practice goes through `SongLibraryViewModel.startPractice` and requests the existing Practice flow without a Library Window click；
- import-active/missing-entry still blocks spatial start through that same gate；
- old Window start-practice button/closure/push action has no production references；
- setup-not-ready creates one pending launch and routes through existing Preparation；
- successful pending setup advances `awaitingPreparation → awaitingPracticeActivation` before window dismissal and does not unconditionally tear down the shared ImmersiveSpace before Practice；
- user/system closing Preparation while still `awaitingPreparation` cancels it and returns the same ImmersiveSpace/score to Spatial Library；
- independent/non-spatial Preparation still follows its valid standalone completion behavior；
- score/file-version change invalidates stale pending launch；
- one logical spatial score presentation survives library -> practice, with entity reuse while the same immersive session stays alive；
- `.failure` keeps `awaitingPracticeActivation` so existing retry remains valid；matching `.ready` + geometry performs handoff and then clears the launch coordinator；Return/dismiss/identity invalidation cancels and restores Library；
- successful activation releases Library preview ownership before Practice navigation drives the attachment；failed/cancelled activation leaves Library preview authoritative；
- realAudio geometry -> target；
- bluetoothMIDI geometry -> same target pipeline；
- missing geometry -> no guessed target；
- keyboard frame update moves root but preserves local offset；
- Reduce Motion skips flight；
- return to library tears down keyboard root；
- no WorldAnchor add/remove calls for score。

### Gate

- targeted scene/view-model tests；
- existing Practice localization tests；
- `make build:simulator`；
- Simulator/device handoff walkthrough。

**Atomic commit:** `feat: P5-T3 - 乐谱从曲库迁移到现实钢琴`

---

## P5-T4 增加 RealityKit 直接微调、重置与真实设备验收

**Goal:** 自动 placement 给出合理默认值，但用户可以按自己的身高、钢琴结构和阅读习惯调整乐谱的位置。

### Pre-implementation SDK check

Before implementing 3D manipulation:
- verify the installed visionOS 27.0 entity-targeted `DragGesture` conversion APIs with current Apple docs；
- follow `HappyPianistAVP/AGENTS.md`：
  - draggable entity/proxy has `CollisionComponent`；
  - `InputTargetComponent`；
  - no raw gaze coordinates。

### Interaction boundary

First version adjusts **position**, not a full 6-DOF CAD transform.

Allow:
- horizontal X；
- vertical Y；
- near/far Z within safe/readable bounds。

Keep orientation facing the player using P5-T1 resolver.

Only add a dedicated pitch/scale interaction if device validation proves fixed orientation/size materially blocks usability; do not pre-build knobs for hypothetical needs.

### Manipulation entity

Use a focused grab proxy/handle associated with the score attachment.

Do not make every notation mark collide or receive 3D input.

During drag:
1. convert gesture world position into keyboard-local coordinates using `keyboardFrame.keyboardFromWorld`；
2. clamp to product readability/safety bounds；
3. update in-memory preference；
4. never write disk per frame。

On end:
- commit to P5-T2 store once。

### Reset

Provide one small score-attached “重置位置” affordance.

Reset:
- restores canonical resolver placement；
- writes/removes the persisted offset；
- does not recalibrate the piano。

### Lifecycle

- recalibration changes KeyboardScoreRoot, not user local offset；
- app/immersive suspend cancels active gesture state；
- late gesture completion after mode/song change is ignored by generation/identity；
- score manipulation never mutates Practice progress。

### Device acceptance

Simulator can prove transforms/lifecycle, but comfort requires real AVP.

Real-device checks:
- seated at real keyboard；
- page does not occlude hands/keys；
- readable without exaggerated neck pitch；
- near/far drag feels natural；
- offset survives close/reopen；
- recalibrating same piano preserves relative preference；
- Bluetooth MIDI and Real Audio placement look identical for same physical piano；
- score remains stable when head moves。

Record actual chosen default placement constants after this evidence; do not claim comfort from Simulator alone.

### Cleanup

If P4/P5 introduced any temporary fixed-position score offsets, remove them in this task once the resolver/user preference owns placement.

Do not leave:
- magic RealityView translations；
- debug placement sliders；
- separate realAudio/MIDI placement constants。

### Gate

- targeted manipulation/store tests；
- `make build:simulator`；
- Simulator manipulation flow；
- physical AVP acceptance for comfort/stability when hardware is available; if unavailable, mark only the physical comfort evidence blocked, not unit/simulator claims。

**Atomic commit:** `feat: P5-T4 - 支持用户微调空间乐谱位置`

---

## P5 Phase Audit

Before P6:

1. Real Audio and Bluetooth MIDI use the same calibrated keyboard placement pipeline.
2. Score has no independent persistent WorldAnchor.
3. Persisted preference is keyboard-local, never world-space.
4. Same Book Spread identity survives Library -> Practice.
5. Missing keyboard geometry never causes guessed placement.
6. Calibration/localization remains the only source of keyboard world pose.
7. User drag writes only on commit, not every frame.
8. Recalibration updates root while preserving local preference.
9. Virtual Piano has no new special-case product branch.
10. P5 does not yet claim Guide / Companion / spatial controls are integrated.
