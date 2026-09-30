# Plan P6 - Spatial Practice：把乐谱、Guide、Companion、反馈与控制收成一个现实增强练习体验

**Goal:** 完成当前 Reality-first 产品主线的空间练习闭环。

最终核心画面只包含：

```text
用户真实环境 / 真实钢琴 / 真实双手
        +
keyboard-relative Book Spread
        +
局部 Piano Guide
        +
唯一一双 Companion Hands
        +
直接附着的反馈 / 少量空间控制
```

**Visual acceptance references:**
- `.github/features/spatial-2026-09-30/设计稿/images/04-正常练习.png`
- `.github/features/spatial-2026-09-30/设计稿/images/05-Companion教学.png`
- `.github/features/spatial-2026-09-30/设计稿/images/06-Companion陪弹.png`
- `.github/features/spatial-2026-09-30/设计稿/images/07-实时反馈与空间控制.png`
- `.github/features/spatial-2026-09-30/设计稿/images/08-练习结果与重练.png`

P6 负责把这五张图收成同一条 Reality-first Practice 主流程：真实钢琴/真实双手、同一双 Companion Hands、空间反馈/控制，以及结果/重点小节/重练/返回曲库。图片中的视觉关系是验收参考，AI 生成的具体房间、文字和示意细节不是硬编码资产。

**Product invariants:**
- 用户真实手保持 passthrough，不再额外画一双“霓虹用户手”。
- Teaching 与 AI Duet 使用同一双 Companion Hands。
- Companion Hands 的本 phase 正式产品入口只服务已校准的现实钢琴路径（Real Audio / Bluetooth MIDI）；它永远落在用户自己的现实钢琴上，不生成第二台 AI 钢琴。
- `listen / support / sparse / respond / yield` 通过动作表现，不显示模型 action 标签。
- Piano Guide 与反馈继续使用现有 Practice 事实，不创建第二套练习状态。
- 高频控制可以空间化；复杂配置、后端选择、录音库等仍可放普通 Window。
- 核心 Practice Window 不再重复画二维钢琴、二维谱面和永久底部 Toolbar。

**Non-goals:**
- 不把 Virtual Piano 扩成新的 Companion Hands 产品路径；Virtual Piano 保持实验输入模式，现有基础练习可继续工作，但本 phase 不为它增加 Companion Teaching/Duet 控制、特殊 placement 或旧 performer fallback。
- 不重新设计 Companion 手材质/UV/皮肤。
- 不恢复小程完整角色。
- 不做第二台 AI piano。
- 不重做 Qwen/Aria 决策或生成算法。
- 不重做练习评分/进度模型。
- 不重做 Piano Guide 的音乐判断。
- 不让 spatial UI 显示 Qwen / Aria / RTT / token 等调试信息。

---

## P6-T1 把 CompanionDecision / AI playback timing 变成正式可渲染运行期状态

**Goal:** Companion Hands 只消费正式播放事实，不能根据“schedule 刚更新了”自行猜声音何时开始，也不能猜当前是 support 还是 respond。

### Current source facts

Current `CompanionDecision` already owns:
- `.listen`
- `.support`
- `.sparse`
- `.respond`
- `.yield`

Current `AIPerformanceService.State` only exposes:
- active/generating/playing；
- latest schedule；
- status text。

It does **not** expose the current validated CompanionAction.

Current `DuetAIPlaybackQueue` knows:
- requestGeneration；
- preparing/playing transitions；
- the exact point after `service.play()` succeeds；

but its callback exposes only a phase, not playback identity/start time.

### Files

Expected:
- Update: `HappyPianistAVP/Services/Practice/AI/Playback/DuetAIPlaybackQueue.swift`
- Update: `HappyPianistAVP/Services/Practice/AI/AIPerformanceService.swift`
- Update: `HappyPianistAVP/ViewModels/Practice/AI/ARGuideAIPerformanceViewModel.swift`
- Update: `HappyPianistAVP/ViewModels/ARGuideViewModel.swift` including `shouldResumeVirtualPerformer` and every old VirtualPerformer product-state name
- Update corresponding AI playback/state tests

### Playback presentation identity

Replace the phase-only callback with a bounded playback event/state that can identify the actual active window.

It must expose enough to build one immutable presentation fact:

```text
CompanionPlaybackPresentation
- requestGeneration / window identity
- CompanionAction
- shifted schedule
- playbackStartedAtUptimeSeconds
```

The queue should publish the actual start timestamp only after the playback service crosses the successful `play()` boundary.

Do not use submit time as playback start.

Do not add a visual timer independent of audio playback.

### Action ownership

`AIPerformanceService` retains the validated `CompanionDecision.action` associated with each accepted request generation until:
- that window starts；
- it is replaced while still pending；
- it is invalidated/yielded；
- service disables/resets。

Keep only bounded current/pending identities; no unbounded history dictionary.

Expose in State:
- current validated companion action for idle/listen/yield behavior；
- current playing presentation when actual playback is active。

### Rename product state

Current names `isVirtualPerformerEnabled / setVirtualPerformerEnabled` describe the old Xiaocheng renderer, not the product capability.

Rename the behavior flag across production/tests to:
- `isCompanionDuetEnabled`
- `setCompanionDuetEnabled`

This task changes state/API naming only; the old visual controller may temporarily consume the renamed flag until P6-T3 replaces it.

Do not keep old property aliases. Rename/remove `shouldResumeVirtualPerformer`, `virtualPerformerEnabled` bindings and related test/debug labels in this task；renderer class names remain only until P6-T3 replaces the visual path.

### User-facing diagnostics boundary

Backend/status text may remain in the advanced settings Window.

Spatial practice must consume only semantic states:
- companion enabled；
- action；
- playback timing；
- schedule。

Do not pass raw backend/model strings into spatial attachments.

### Tests

- validated action appears in state；
- listen -> no playback presentation；
- support/sparse/respond accepted window retains correct action；
- playing event has correct request generation；
- start timestamp is published only after play boundary；
- pending replacement cannot make wrong action drive the playing window；
- yield clears current playing presentation；
- disable/reset clears action/playback state；
- old virtual-performer property names absent after migration。

### Cleanup in this task

Delete:
- old phase-only presentation glue that becomes redundant；
- old virtual-performer state property/method names。

Keep:
- backend decision algorithms；
- playback queue audio semantics；
- generation cancellation rules。

### Gate

- AI/queue targeted tests；
- `make build:simulator`。

**Atomic commit:** `refactor: P6-T1 - 暴露 Companion 正式播放状态`

---

## P6-T2 复用现有 Fingering / MotionClip 管线生成 AI Companion Hands 动作

**Goal:** AI 音频 schedule 通过和 Demonstration 相同的钢琴手动作管线，生成真正对齐现实琴键的左右手 motion clips。

### Current source facts

Existing reusable pipeline:

```text
PianoKeyContactTimeline
  -> PianoFingeringPlanner
  -> PianoHandMotionClipBuilder
  -> PianoHandMotionClip
  -> PianoHandMotionPlayer
```

This pipeline:
- has no RealityKit dependency in the heavy builder；
- can build off-main；
- validates contact error / collision / joint velocity；
- already produces exact keyboard-local hand root/joint motion。

Current AI schedule is `[PracticeSequencerMIDIEvent]` and contains note-on/note-off timing but no staff/hand/finger metadata.

### Files

Expected:
- Add/Move reusable pure motion kernel under one neutral `HappyPianistAVP/Services/Practice/PianoHandMotion/` directory (exact filenames may retain `PianoHand...` names): move/refactor current `PianoHandMotionClipBuilder.swift`, `PianoHandMotionPlayer.swift`, reusable skeleton/root-planner code, and their tests here；do not leave forwarding files in `DemonstrationHands/`
- Move/rename `HappyPianistAVP/Models/Immersive/PianoDemonstrationPlanning.swift` to a neutral `PianoHandMotion...` model file containing the shared plan/clip-set/source identity types
- Add: `HappyPianistAVP/Services/Practice/CompanionHands/CompanionAIScheduleContactBuilder.swift`
- Add: `HappyPianistAVP/Services/Practice/CompanionHands/CompanionAIHandMotionPlanner.swift`
- Refactor/Rename: `PianoDemonstrationFingeringPlan` / `PianoDemonstrationMotionClipSet` to neutral `PianoHand...` plan/clip-set types used by both Demonstration and AI
- Refactor/Rename: `PianoDemonstrationTransportTiming` -> `PianoHandTransportTiming`
- Remove: `PianoDemonstrationHandsTiming` wrapper；its `.manual/.transportPending` cases do not drive samples and should not survive as a compatibility shell
- Refactor: `PianoHandMotionPlayer` so its core sampler accepts neutral clip set + contact timeline + playback seconds
- Rename: `PracticePlaybackControlService.pianoDemonstrationTransportTiming()` / `onPianoDemonstrationContactTimelineChange` to neutral hand-motion transport/contact names
- Rename Session fields/tasks/accessors such as `pianoDemonstrationFingeringPlan*` / `pianoDemonstrationMotionClipSet*` to neutral hand-motion names in this task；update tests directly
- Rename reusable geometry helpers `PianoDemonstrationHandRootPlanner` / `PianoDemonstrationHandSkeleton` to neutral `PianoHand...` names and move them with the pure motion kernel in this task because AI motion planning consumes the same geometry；do not defer these core files/aliases to renderer cleanup
- Update: Demonstration playback path to the same generic types in this task
- Add AI motion-planning tests

### AI contact timeline

Convert one accepted playback presentation schedule into deterministic contacts.

Rules:
1. pair noteOn/noteOff by MIDI/event order；
2. use the **shifted schedule that audio actually plays**；
3. create stable occurrence IDs scoped to playback request generation；
4. control changes are ignored for finger contact generation but remain audio facts；
5. unmatched/invalid note timing is rejected explicitly and diagnosed, not fabricated。

### Hand assignment

Do not reuse Xiaocheng's visual arm animation.

Add one pure `CompanionScheduleHandAssignmentService` or equivalent inside this planning layer.

KISS policy:
- derive note distribution from the current AI schedule；
- if schedule clearly spans low/high registers, split around a deterministic median/register boundary；
- if effectively one-sided, assign one hand according to the played register relative to keyboard center；
- assign explicit left/right hand to each synthetic contact before `PianoFingeringPlanner`；
- then let the existing planner choose fingers。

Do not alternate hands merely for visual activity.

The algorithm must be deterministic and unit-tested; it is presentation planning, not new AI music generation.

### Generic motion identity

Current `PianoHandMotionClip.Metadata.scoreRevision` assumes all clips come from a score.

Rename the metadata concept to a neutral source revision/identity in this task if AI schedule reuse requires it.

Likewise, replace demonstration-only clip-set/plan/transport/contact-callback/session-field naming with neutral hand-motion names.

The old `PianoDemonstrationHandsTiming` wrapper is deleted, not aliased. For Demonstration, the presentation layer obtains the current neutral transport timing when autoplay/replay is actually active, resolves `playbackSeconds`, then calls the shared sampler. `manual/transportPending` simply means there is no active sampled motion yet；do not preserve empty enum cases solely for old call shape.

Do not leave deprecated demonstration aliases.

### Timing

Demonstration:
- continues using its actual autoplay transport playback position。

AI:
- playback seconds = current monotonic time - P6-T1 `playbackStartedAtUptimeSeconds`；
- sampled against the same shifted contact timeline used to build the clips。

No second timer task is needed; controller samples from current monotonic time during RealityView updates just as the current Demonstration path does.

### Failure behavior

If AI contacts cannot get safe hand motion:
- preserve the existing `PianoHandMotionClipBuilder` safety invariant: one hand clip is atomic; a motion-constraint failure rejects that hand's clip rather than publishing a partial pose sequence whose coverage is false；
- audio playback remains unchanged；
- publish only successfully built hand clips；
- never claim rejected/unrendered contacts as active rendered fingers；
- structured diagnostics record rejected coverage/reason counts；
- if one or both hand clips are unavailable, the missing hand stays resting/hidden for that window rather than rendering a second fake performer as fallback。

For Demonstration, preserve the current invariant:
- rejected hand coverage does not suppress the corresponding Piano Guide cue。

### Tests

- noteOn/off pairing；
- one-sided high register -> right hand；
- one-sided low register -> left hand；
- two-register schedule -> deterministic split；
- same schedule -> same hand/fingering plan；
- build cancellation/generation；
- AI playback seconds align with actual playback start；
- rejected contacts do not appear in clip coverage；
- existing Demonstration motion/transport tests migrate to the neutral names and still pass；
- full symbol scan has no reusable-core `PianoDemonstrationFingeringPlan`, `PianoDemonstrationMotionClipSet`, `PianoDemonstrationTransportTiming`, `PianoDemonstrationHandsTiming`, `PianoDemonstrationHandRootPlanner`, `PianoDemonstrationHandSkeleton`, `pianoDemonstrationTransportTiming`, or `onPianoDemonstrationContactTimelineChange` references after T2；renderer/rig/settings/asset identity names intentionally remain only until T3/T4。

### Gate

- planner/motion tests；
- existing demonstration hand quality tests；
- `make build:simulator`。

**Atomic commit:** `feat: P6-T2 - 让 AI 复用真实钢琴手动作管线`

---

## P6-T3 建立唯一 CompanionHandsOverlayController，并删除 NeonHand / VirtualPerformer / 旧 Demonstration renderer

**Goal:** RealityView 中只存在一双虚拟 Companion Hands；用户手保持 passthrough。

### Files

Expected:
- Add: `HappyPianistAVP/Services/Practice/CompanionHands/CompanionHandsOverlayController.swift`
- Rename/move only the RealityKit presentation identity from the old `DemonstrationHands` folder into `CompanionHands`: current `PianoDemonstrationHand.swift` enum, `PianoDemonstrationHandRig.swift` rig/loader, and associated renderer-facing tests；the skeleton/root-planner/motion builder/player were already moved to neutral `PianoHandMotion/` in T2
- Update: `ImmersiveView.swift`
- Update: guide suppression integration
- Update: `HappyPianistAVP/AGENTS.md` in this same task so the documented spatial-hand architecture matches the new source (`passthrough user hands + CompanionHandsOverlayController`)
- Update: `docs/data-flow.md` in this same task；remove the current “荧光手套 + 示范手骨骼” production-flow description and replace it with passthrough user hands + one Companion motion/render path
- Update: `docs/architecture.md` in this same task with `CompanionHandsOverlayController` as the sole virtual-hand renderer and remove any old renderer ownership that no longer exists
- Delete after migration:
  - `NeonHandOverlayController.swift`
  - `NeonHandSurface.swift`
  - `PianoDemonstrationHandsOverlayController.swift`
  - `VirtualPerformerOverlayController.swift`
  - `XiaochengRig.swift`
  - `Packages/RealityKitContent/.../xiaocheng.usdz`
  - tests serving only those deleted renderers
- Rename the packaged hand assets + generator to the final Companion identity in this task (for example `CompanionHandLeft/Right.usdc` and a neutral/Companion generator script), update the loader/tests, and delete the old `PianoDemonstrationHand*` asset names；do not ship duplicate old/new assets
- Keep `PianoDemonstrationHandsSettings.swift` temporarily in this task only as the existing Demonstration trigger source; P6-T4 removes it in the same task that replaces the persistent toggle with the one-shot spatial Demonstration action
- By the end of T3, `HappyPianistAVP/Services/Practice/DemonstrationHands/` has no production files and the directory is removed；there are no forwarding wrappers/import shims from old paths

### One-pair architecture

`CompanionHandsOverlayController` loads exactly one left rig and one right rig.

Root:
- anchored to current `keyboardGeometry.frame.worldFromKeyboard`；
- same real keyboard as Piano Guide；
- never creates a performer piano。

It accepts one mutually-exclusive presentation state, for example:

```text
hidden
resting/listen
demonstrating(motion)
duet(action, motion)
yielding
```

Exact enum naming may be refined; there must still be one source state, not multiple booleans that can make two hand systems render simultaneously.

### Precedence

At any instant, choose one motion source:

1. actual AI playing window -> AI motion；
2. explicit one-shot Companion Demonstration request -> Demonstration motion；
3. Companion action listen -> waiting/rest pose；
4. yield -> withdraw pose；
5. no Companion feature active -> hidden。

P6-T3 may temporarily consume the existing persistent Demonstration setting only to keep this intermediate commit functional while the renderer is replaced. It must not create a new setting or compatibility alias. P6-T4 removes that persistent toggle in the same task that introduces the explicit one-shot spatial Demonstration action.

If product logic can produce an ambiguous state, resolve it in one pure presentation resolver and test it; do not let RealityView layer decide ad hoc.

### Behavior mapping

- `listen`: hands wait above/behind keys, no key contact；
- `support`: play accepted support motion；
- `sparse`: same identity, sparse motion only；
- `respond`: play accepted response motion；
- `yield`: hands visibly withdraw from the keys；
- Demonstrate: play current score demonstration motion。

No action-specific recoloring.

No user-visible text labels.

### Guide suppression

Controller returns the set of MIDI notes currently contacted by **rendered Companion Hands**.

`PianoGuideOverlayController` suppresses only those notes.

Do not suppress:
- rejected/unrendered Companion motion；
- user's own target guide just because AI audio exists。

### Reduce Motion

Reduce Motion:
- no animated approach/withdraw transition；
- direct rest/play/hidden pose transition；
- core key-to-finger playback remains because it is instructional/musical content; disable decorative approach/withdraw/flying transitions and other nonessential motion.

### Delete Neon user-hand rendering

Current NeonHand exists only for visualizing tracked user hands.

Target product requires natural passthrough hands.

Delete the production renderer and its exclusive simulator/surface tests.

Hand tracking for input stays completely intact in `ARTrackingService`; this task deletes only the duplicate visual mesh.

### Delete old Virtual Performer

Remove:
- Xiaocheng character；
- its own piano；
- gait/head nod/arm pulse/lateral walking code；
- old virtual-performer lifecycle tests。

The future “full Companion character” is a separate future feature, not a reason to retain dead current code.

### Cleanup naming

Rename renderer/product-facing/runtime asset strings that are owned by this task:
- “虚拟演奏家” -> Companion 陪弹；
- `PianoDemonstrationHand` rig/loader/asset identity -> final Companion hand identity；
- diagnostic/entity names such as `pianoDemonstrationHands.loadAsset` / `pianoDemonstrationHand.*` -> Companion equivalents。

The product action “Demonstration / 示范” remains a valid **mode/action name**；only reusable hand infrastructure stops pretending it belongs exclusively to the old persistent Demonstration renderer.

The old persistent “演示手” setting label/key remains only until P6-T4 replaces that whole control with one-shot Companion Demonstration. Do not add aliases or new persistent keys.

`HappyPianistAVP/AGENTS.md` must be rewritten with the new source reality, not just one renamed class:
- remove the old `HandVisualization + LowLevelMesh` Neon rendering rule；
- remove the `PianoDemonstrationHandsOverlayController`-specific rule；
- remove/update the Simulator synthetic-pose rule that names deleted `HandVisualization`；do not move synthetic user-hand rendering into ARKit/input code；
- document that user hands are passthrough and ARKit hand tracking is input-only；
- document that `CompanionHandsOverlayController` is the sole virtual-hand renderer and asynchronously loads/reuses the packaged two-hand rig/motion pipeline；
- keep existing RealityView/update/concurrency and permission boundaries that remain true。

### Tests

- one pair loaded；
- demonstrate and AI never render simultaneously as two pairs；
- listen/rest；
- yield withdraw；
- AI active note suppression；
- rejected motion does not suppress Guide；
- keyboard frame update；
- reset/suspend cancels load and prevents late reattach；
- Reduce Motion；
- no Neon/VirtualPerformer/Xiaocheng production refs；
- no old `PianoDemonstrationHand*` rig/asset/generator/entity/diagnostic identity remains after migration, except the still-temporary `PianoDemonstrationHandsSettings` trigger that T4 deletes。

### Gate

- Companion overlay tests；
- Guide suppression tests；
- `make build:simulator`；
- Simulator/device visual validation。

**Atomic commit:** `refactor: P6-T3 - 统一 Companion Hands 并删除旧空间角色`

---

## P6-T4 把高频 Practice UI 变成空间反馈/控制，收掉核心二维练习界面

**Goal:** Practice Window 不再是“真正练习发生的地方”；真正练习发生在现实钢琴 + Spatial Score 周围。

### Current Window UI to migrate

Current `PracticeStepView` core contains:
- `GrandStaffNotationView/Spread`；
- `PianoKeyboard88View`；
- top `PracticeFeedbackCueView`；
- bottom ornament:
  - Next；
  - Replay；
  - Autoplay；
  - Settings；
  - progress；
- trailing `PracticeSettingsView`。

P5 already puts Book Spread in space.

Piano Guide already renders in RealityKit on real keys.

Therefore keeping the first two in Window would be duplicate core UI.

### Files

Expected:
- Add: `HappyPianistAVP/Views/Practice/Spatial/SpatialPracticeControlsAttachmentView.swift`
- Add: `HappyPianistAVP/Views/Practice/Spatial/SpatialPracticeFeedbackAttachmentView.swift`
- Update: `ImmersiveView.swift` attachments
- Reshape/Rename: `PracticeStepView.swift` to an auxiliary practice surface if its role is no longer a core step renderer
- Update: `PracticeLaunchContainerView.swift`
- Update: `PracticeSettingsView.swift`
- Keep `PianoKeyboard88View` for calibration/other legitimate callers
- Update Practice UI tests/previews

### Spatial high-frequency controls

Attach one compact contextual control cluster to the score/keyboard area.

Only include high-frequency actions backed by the existing Practice transport/session capabilities. The spatial attachment reads the **existing Session state** (including `PracticeSessionViewModel.autoplayState`) instead of introducing a new View-local `@State isAutoplayEnabled` source of truth:

- Next / advance；
- Replay current unit audio；
- **Companion 示范当前片段**：one-shot action that starts the existing current-unit replay/transport with an explicit Demonstration presentation intent；
- Autoplay toggle；
- Companion duet enable/disable；
- Recording start/stop + tiny status；
- **结束练习 / 返回曲库**：调用现有 Practice return lifecycle，最终进入当前 `PracticeWindowReturnCoordinator` 的保存/失败重试/明确放弃流程。

The Demonstration action must not create a second playback engine. It reuses the existing Practice replay/autoplay transport facts that already feed `PianoKeyContactTimeline`; only the presentation intent is new and ephemeral. When that transport stops/resets/replaces, Demonstration intent clears automatically.

### Transport-mode exclusivity

Define one explicit product transition rule instead of piling up `.disabled` modifiers:

- enabling **Companion Duet** first turns Practice Autoplay off and clears any one-shot Demonstration intent, then enables the existing AI service；
- starting **Autoplay** or **Companion Demonstration** first disables Companion Duet / stops its current+pending AI playback, then starts the existing Practice transport；
- Companion Duet **off** remains actionable even while AI is generating/playing so the user can stop it immediately；
- Next/Replay/configuration changes that already conflict with active AI remain unavailable until Companion playback/generation is inactive；
- recording keeps the existing `canRecord && !isAIPerformanceActive && !takePlayback.isPlaying` gate。

Put these transitions in an existing ViewModel/session action owner, not in the SwiftUI Attachment as ad-hoc toggle side effects.

Do **not** invent a metronome service in this feature merely because a concept image mentioned one.

Controls:
- are collapsed/low-weight by default；
- expand on gaze/interaction when appropriate；
- are attached to score/keyboard context；
- are not a persistent horizontal toolbar。

### Advanced 2D Window remains valid

Keep complex/low-frequency controls in the auxiliary Practice Window:

- round configuration；
- tempo/loop/success threshold；
- audio routing/output；
- AI generation backend；
- Companion decision backend；
- recording library / take management, but **not** duplicate recording start/stop controls；
- virtual-piano debug/setup controls；
- diagnostics/debug-only controls。

Refactor labels/state in this same task:
- remove the persistent `PianoDemonstrationHandsSettings` toggle and its AppStorage key；
- delete `PianoDemonstrationHandsSettings.swift` after all callers migrate；
- expose the one-shot “Companion 示范当前片段” action in spatial controls instead；
- remove “AI 即兴演奏（虚拟演奏家）” wording；
- use Companion duet behavior terminology。

Do not expose backend selection in spatial controls.

### Round completion / results on the Book Spread

The 08 design reference must not fall back to the old `PracticeStepView` round-completion Alert.

Reuse the existing `PracticeRoundSummaryViewModel`, `PracticeNextAction`, `PracticeHotspot` and `currentCoachingDecision` as the only result/action facts. `PracticeRoundSummaryViewModel` is already a pure derived value；do not create a new observable result store.

Its current six-input construction lives only in `PracticeStepView.roundSummary`. In this task, move that construction behind one shared pure entry point (for example `PracticeRoundSummaryViewModel.init?(session:)` or an equivalently small factory) and make both any remaining auxiliary Window presentation and the spatial Book Spread consume that same projection. Delete the duplicated View-local constructor once the spatial path takes over.

When a round completes:

- the same Spatial Book Spread becomes the result surface；
- current-passage measure annotations show stable/learning/current outcome without repagination；
- `PracticeHotspot.sourceMeasureID` maps to the existing PagePlan measure rect and gets the shallow focus affordance；
- if that hotspot is on another spread, drive the **existing P3 spread navigation owner** directly to the containing spread when entering result mode；do not create a separate result-page index；
- while round result mode is visible, autoplay/practice tick updates no longer override that result target；after applying/continuing a next action and resuming Practice, normal `notationNavigationTick` ownership resumes；
- the existing `nextAction` is exposed next to/on the relevant score context (`重练这个小节 / 放慢一点再练 / 保持速度 / 扩大片段 / 继续`)；
- when `coachingPresentation != nil`, preserve the existing “跳过建议并继续” action and call `skipCoachingDecisionAndContinue()`; when there is no coaching presentation, do not show it.
- “返回曲库” calls the existing return lifecycle described below。

Delete `isRoundCompletionAlertPresented` and the core round-summary Alert from `PracticeStepView` in this task after the spatial result surface is active. Keep system/error alerts (audio unavailable, save failure, destructive discard) in the auxiliary Window where appropriate；do not turn those into decorative spatial UI.

No second result reducer or focus-measure calculation is added.

### Spatial feedback

Reuse existing facts:
- `PracticeFeedbackViewModel.cue`
- `coachingPresentation`
- `latestFeedbackEvent`
- current notation overlay。

Move the immediate cue from Window top overlay to a small attachment near the relevant Book Spread / keyboard area.

Where feedback already belongs directly to score or keys:
- leave it there；
- do not duplicate a floating toast。

`PracticeRestorationEffectRenderer` remains the existing key-level RealityKit effect.

### Remove duplicate Window core UI

After spatial controls/feedback work:

Remove from production Practice core window:
- duplicate Book Spread/notation renderer；
- round-completion result Alert now replaced by the spatial Book Spread result surface；
- practice-only `PianoKeyboard88View` rendering；
- top floating feedback overlay；
- bottom permanent core toolbar。

If `PracticeStepView` becomes purely auxiliary lifecycle/settings host, rename it accordingly in the same task.

Do not delete `PianoKeyboard88View` globally because Calibration still uses it.

### Lifecycle ownership

The auxiliary Window may still own:
- alerts requiring system modal presentation；
- Take Library sheet；
- advanced settings；
- lifecycle/return coordination。

It must not own a second spatial practice state.

Spatial controls call existing `ARGuideViewModel/PracticeSessionViewModel` actions directly through injected closures/state; no duplicate control model.

“结束练习 / 返回曲库”不得自己关闭 scene 或直接 dismiss window。它只触发现有 `onPracticeFinished` / `PracticeWindowRootView.beginReturnToLibrary()` 语义，使 progress flush、save failure retry、explicit discard 和 final teardown 仍由现有 return coordinator 负责。

### Tests

- spatial Next/Replay/Autoplay call existing commands and render state from the Session owner, with no duplicate View-local autoplay truth；
- Companion Duet / Autoplay / one-shot Demonstration transitions enforce the explicit exclusivity rule and Companion Off stays available while AI is active；
- spatial Finish/Return enters the existing `PracticeWindowReturnCoordinator` path and preserves save failure / retry / discard semantics；
- one-shot Companion Demonstration starts the existing replay transport and clears its presentation intent on stop/reset/replacement；
- Companion toggle uses `isCompanionDuetEnabled`；
- recording state/action；
- `PracticeSettingsView` no longer duplicates recording start/stop after the spatial control takes ownership；
- completed round renders `PracticeRoundSummaryViewModel`/hotspot/nextAction on the Spatial Book Spread and old round Alert is absent；
- hotspot on another spread moves the existing spread navigator to that result target and Practice navigation resumes cleanly after next action/continue；
- retry/lower-tempo/keep-tempo/expand/continue/skip-coaching actions call the existing session APIs；
- feedback attachment follows existing cue state；
- Window no longer renders duplicate keyboard/score/core toolbar；
- advanced settings still reachable；
- backend/debug status not exposed in spatial UI；
- accessibility labels for all icon controls。

### Gate

- Practice UI/action tests；
- `make build:simulator`；
- Simulator walkthrough。

**Atomic commit:** `refactor: P6-T4 - 将核心练习控制与反馈空间化`

---

## P6-T5 收口 Reality-first Practice 生命周期、返回路径与真实设备验收

**Goal:** 把 P4–P6 串成一条完整产品路径，并只清理 P6 本阶段产生的临时实现。

### End-to-end target

```text
Auxiliary Library Window
  -> Spatial Book Flow
  -> Spatial Book Spread
  -> existing piano setup/calibration when needed
  -> score handoff to calibrated keyboard
  -> Reality-first Practice
     - real hands
     - Piano Guide
     - one Companion Hands pair
     - spatial feedback / controls
  -> finish
  -> progress saved
  -> score/book returns to Spatial Library
```

### Lifecycle

Verify/complete:

- opening Library -> world tracking；
- entering calibration -> existing calibration requirements；
- entering Practice -> existing selected-mode tracking requirements；
- leaving Practice -> flush progress before any spatial ownership change, preserving current save/abort/discard semantics；
- **successful spatial return does not call the old unconditional `closeImmersive` path**: after save/finalize succeeds, switch the already-open shared ImmersiveSpace to `.library`, reconcile world-only tracking, tear down Guide/Companion/KeyboardScoreRoot, restore Spatial Library root, then dismiss the Practice Window；
- refactor `PracticeWindowReturnCoordinator`'s hard-coded `closeImmersive` step into one presentation-completion closure that can either switch-to-library (spatial return) or close (true system/non-spatial exit) without changing save ordering；
- `PracticeWindowRootView.onDisappear` / `PracticeSystemCloseCoordinator` must recognize a completed spatial return and **must not close the ImmersiveSpace a second time**；
- save failure/abort keeps Practice active and does not switch to Library；
- immersive close/background -> cancel spatial/hand tasks and reject late results；
- selected song remains consistent across return；the score closes into that selected folio and Library returns to Book Flow；`LibraryScorePreviewViewModel` stays closed after the successful Practice handoff/return until the user explicitly opens the folio again。

Do not weaken the existing unsaved-progress confirmation or persistence gates when reducing the Practice Window.

### Spatial teardown ownership

By the end:

- SpatialLibrarySceneController owns only Library folios/root；
- SpatialScoreSceneController owns score attachment/keyboard handoff；
- PianoGuideOverlayController owns key Guide + restoration effect；
- CompanionHandsOverlayController owns the sole virtual hand pair；
- no NeonHand controller；
- no VirtualPerformer/Xiaocheng；
- no duplicate Window core score/keyboard renderer。

### Return animation

If Reduce Motion is off and P4's Spatial Library placement still belongs to the current `worldTrackingGeneration`:
- score may transition from keyboard placement back to library placement before closing to folio。

If that generation changed after AR runtime suspend/restart, wait for P4 to establish a fresh Library placement and do not animate through stale world coordinates。

If Reduce Motion is on:
- direct state transition。

Animation never gates progress save/return correctness.

### Accessibility

Validate:
- VoiceOver can reach spatial score controls；
- page navigation remains accessible；
- Companion semantic control is labeled, but internal action names are not announced as model jargon；
- Differentiate Without Color applies to Guide/feedback；
- Reduce Motion path avoids flying score/page/hand approach animations。

### Real-device acceptance

Physical AVP is required to prove:

1. Book Flow stays in world while head moves.
2. Book Spread is readable at keyboard.
3. Score does not block hands/keybed.
4. Piano Guide aligns with real keys.
5. Companion fingers align with the same physical keys.
6. User passthrough hands remain visually natural.
7. Companion support occupies sensible unused register.
8. yield visibly gets out of the user's way.
9. controls are reachable without becoming a dashboard.
10. return to Library leaves no stale spatial objects **and dismissing the Practice Window does not close the restored Spatial Library ImmersiveSpace**.

If physical AVP is unavailable:
- Simulator/unit/build evidence may pass；
- physical alignment/comfort Gate remains explicitly blocked；
- do not claim those checks passed。

### Docs

Final docs pass is only a consistency check; architecture docs must already have been updated in P4-T3 / P5-T3 / P6-T3 when each owner changed. In P6-T5 update only if the final lifecycle changes those already-recorded facts:
- `docs/architecture.md` for final spatial scene/controller lifecycle consistency；
- `docs/data-flow.md` should already have been corrected in P6-T3 when old hand renderers were deleted；P6-T5 only adjusts it again if the final lifecycle implementation materially changes the already-documented flow；
- `docs/testing.md` only with actually executed evidence。

Do not copy feature-plan prose wholesale into docs.

### Final cleanup scan

At this task, only verify earlier cleanups were already completed; do not postpone them here.

Expected no production refs to:
- `NeonHandOverlayController`
- `NeonHandSurface`
- `VirtualPerformerOverlayController`
- `XiaochengRig`
- `PianoDemonstrationHandsOverlayController`
- `PianoDemonstrationHandsSettings`
- `isVirtualPerformerEnabled`
- old Window core Book Flow
- old Window core Practice score/keyboard toolbar path

If any remain, trace ownership and fix in the task where they were supposed to be replaced; do not add compatibility aliases.

### Gate

- targeted return-lifecycle tests cover: save success -> switch to `.library` without scene close and return to selected folio/Book Flow with Library preview still closed；save failure -> stay in Practice；explicit discard -> switch after finalization；Practice Window `onDisappear` after spatial return does not dismiss ImmersiveSpace；true system/non-spatial close still dismisses it；
- targeted Library / Notation / Practice / AI / immersive tests；
- full `make build:simulator`；
- `make test:simulator` when practical；
- Simulator E2E；
- physical AVP alignment/comfort checks when available。

**Atomic commit:** `test: P6-T5 - 收口 Reality-first Spatial Practice`

---

## P6 Phase Audit

1. Only real passthrough user hands + one virtual Companion pair are visible.
2. AI hand motion uses actual playback timing, not schedule-update time.
3. CompanionAction is semantic runtime state, not user-visible debug text.
4. Demonstrate and AI share rig/controller/motion infrastructure.
5. Piano Guide remains the one key-guidance renderer.
6. Spatial controls call existing Practice actions; no second practice state machine.
7. Advanced backend/config UI remains auxiliary Window UI.
8. Core Window no longer duplicates score, piano, feedback, or permanent toolbar.
9. Progress save/return safety is unchanged.
10. P4/P5 spatial roots/controllers have clean ownership and teardown.
