import Foundation
import MusicXML
import Practice
import simd

extension PracticeSessionViewModel {
    func pianoDemonstrationHandsTiming() -> PianoDemonstrationHandsTiming {
        guard autoplayState == .playing else { return .manual }
        guard let timing = playbackControlService?.pianoDemonstrationTransportTiming() else {
            return .transportPending
        }
        return .transport(timing)
    }

    func pianoDemonstrationMotionClipSet(
        for timing: PianoDemonstrationHandsTiming
    ) -> PianoDemonstrationMotionClipSet? {
        guard let clipSet = pianoDemonstrationMotionClipSet,
              clipSet.geometryCacheID == self.keyboardGeometry?.cacheID
        else {
            return nil
        }
        switch timing {
        case .manual:
            return clipSet.transportGeneration == nil ? clipSet : nil
        case .transportPending:
            return nil
        case let .transport(transport):
            return clipSet.transportGeneration == transport.generation ? clipSet : nil
        }
    }

    func startAutoplayTaskIfNeeded() {
        playbackControlService?.startAutoplayTaskIfNeeded()
    }

    func stopAutoplayTask() {
        playbackControlService?.stopAutoplayTask()
    }

    func pauseAutoplayPlayback() async {
        await playbackControlService?.pauseAutoplay()
    }

    func resumeAutoplayPlayback() async throws {
        try await playbackControlService?.resumeAutoplay()
    }

    func setAutoplayPlaybackRate(_ rate: Double) async throws {
        try await playbackControlService?.setAutoplayPlaybackRate(rate)
    }

    func notationViewportTick() -> Double? {
        guard stateStore.isActiveRangeInvalid == false else { return nil }
        if let autoplayTick = playbackControlService?.smoothNotationScrollTick() {
            return autoplayTick
        }

        let stepIndex: Int? = if self.state == .completed {
            self.activeRange?.stepRange.last ?? self.steps.indices.last
        } else {
            self.currentStepIndex
        }
        guard let stepIndex,
              self.steps.indices.contains(stepIndex),
              self.activeRange?.contains(stepIndex: stepIndex) ?? true
        else {
            return nil
        }
        return Double(self.steps[stepIndex].tick)
    }

    func rebuildAutoplayTimeline() {
        cancelAutoplayTimelineBuild()
        guard
            self.stateStore.isActiveRangeInvalid == false,
            let performancePlan = self.performancePlan
        else {
            self.autoplayTimeline = .empty
            return
        }

        self.autoplayTimeline = .empty
        let generation = autoplayTimelineBuildGeneration
        let guideProjection = self.highlightGuides
        let stepProjection = self.steps
        let tempoMap = self.tempoMap
        let handMode = self.practiceHandMode
        let activeRange = self.activeRange
        autoplayTimelineBuildTask = Task { @MainActor [weak self] in
            let timeline = await AutoplayPerformanceTimeline.buildOffMain(
                plan: performancePlan,
                guideProjection: guideProjection,
                stepProjection: stepProjection,
                tempoMap: tempoMap,
                practiceHandMode: handMode,
                activeRange: activeRange
            )
            guard let self,
                  Task.isCancelled == false,
                  self.autoplayTimelineBuildGeneration == generation
            else { return }
            self.autoplayTimeline = timeline
            self.autoplayTimelineBuildTask = nil
            self.startPianoDemonstrationFingeringPlanForAutoplayTimeline()
        }
    }

    func cancelAutoplayTimelineBuild() {
        autoplayTimelineBuildGeneration &+= 1
        autoplayTimelineBuildTask?.cancel()
        autoplayTimelineBuildTask = nil
        cancelPianoDemonstrationFingeringPlan()
    }

    func startPianoDemonstrationFingeringPlanForAutoplayTimeline() {
        guard let performancePlan = self.performancePlan, self.autoplayTimeline.events.isEmpty == false else {
            cancelPianoDemonstrationFingeringPlan()
            return
        }
        let timingBaseTick = self.activeRange?.tickRange.lowerBound ?? self.currentStep?.tick ?? 0
        let schedule = AutoplayTimelineTimeSchedule(
            timeline: self.autoplayTimeline,
            tickToSeconds: { self.tempoMap.timeSeconds(atTick: $0) },
            startTick: timingBaseTick,
            leadInSeconds: autoplayTimingLeadInSeconds
        )
        let contacts = PianoKeyContactTimeline(
            plan: performancePlan,
            timeline: self.autoplayTimeline,
            schedule: schedule,
            guideProjection: self.highlightGuides,
            stepProjection: self.steps
        )
        startPianoDemonstrationFingeringPlan(contacts: contacts, transportGeneration: nil)
    }

    func startPianoDemonstrationFingeringPlan(
        contacts: PianoKeyContactTimeline,
        transportGeneration: Int?
    ) {
        cancelPianoDemonstrationFingeringPlan()
        guard let keyboardGeometry = self.keyboardGeometry, let songIdentity = self.songIdentity else { return }
        let generation = self.pianoDemonstrationFingeringPlanGeneration
        let geometryCacheID = keyboardGeometry.cacheID
        let layout = PianoFingeringKeyboardLayout(keyboardGeometry: keyboardGeometry)
        let activeRange = self.activeRange
        let handMode = self.practiceHandMode
        let tempoScale = self.activeRoundConfiguration?.tempoScale ?? 1

        pianoDemonstrationFingeringPlanTask = Task { @MainActor [weak self] in
            defer {
                if let self, self.pianoDemonstrationFingeringPlanGeneration == generation {
                    self.pianoDemonstrationFingeringPlanTask = nil
                }
            }
            do {
                let plan = try await PianoFingeringPlanner().planOffMain(
                    contacts: contacts,
                    keyboardLayout: layout
                )
                guard let self,
                      Task.isCancelled == false,
                      self.pianoDemonstrationFingeringPlanGeneration == generation,
                      self.songIdentity == songIdentity,
                      self.activeRange == activeRange,
                      self.practiceHandMode == handMode,
                      (self.activeRoundConfiguration?.tempoScale ?? 1) == tempoScale,
                      self.keyboardGeometry?.cacheID == geometryCacheID
                else {
                    return
                }
                let fingeringPlan = PianoDemonstrationFingeringPlan(
                    transportGeneration: transportGeneration,
                    geometryCacheID: geometryCacheID,
                    contacts: contacts,
                    plan: plan
                )
                self.replacePianoDemonstrationFingeringPlan(fingeringPlan)
                self.startPianoHandMotionClipBuild(for: fingeringPlan)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    func cancelPianoDemonstrationFingeringPlan() {
        pianoDemonstrationFingeringPlanGeneration &+= 1
        pianoDemonstrationFingeringPlanTask?.cancel()
        pianoDemonstrationFingeringPlanTask = nil
        replacePianoDemonstrationFingeringPlan(nil)
        cancelPianoHandMotionClipBuild()
    }

    func startPianoHandMotionClipBuild(for fingeringPlan: PianoDemonstrationFingeringPlan) {
        cancelPianoHandMotionClipBuild()
        guard let keyboardGeometry = self.keyboardGeometry, let songIdentity = self.songIdentity else { return }
        let generation = pianoHandMotionClipBuildGeneration
        let fingeringPlanGeneration = pianoDemonstrationFingeringPlanGeneration
        let geometryCacheID = keyboardGeometry.cacheID
        let activeRange = self.activeRange
        let handMode = self.practiceHandMode
        let tempoScale = self.activeRoundConfiguration?.tempoScale ?? 1
        let input = PianoHandMotionClipBuilder.Input(
            contacts: fingeringPlan.contacts,
            fingeringPlan: fingeringPlan.plan,
            keyboardLayout: .init(keyboardGeometry: keyboardGeometry),
            scoreRevision: songIdentity.scoreRevision
        )

        pianoHandMotionClipBuildTask = Task { @MainActor [weak self] in
            defer {
                if let self, self.pianoHandMotionClipBuildGeneration == generation {
                    self.pianoHandMotionClipBuildTask = nil
                }
            }
            do {
                let result = try await PianoHandMotionClipBuilder().buildOffMain(input: input)
                guard let self,
                      Task.isCancelled == false,
                      self.pianoHandMotionClipBuildGeneration == generation,
                      self.pianoDemonstrationFingeringPlanGeneration == fingeringPlanGeneration,
                      self.pianoDemonstrationFingeringPlan == fingeringPlan,
                      self.songIdentity == songIdentity,
                      self.activeRange == activeRange,
                      self.practiceHandMode == handMode,
                      (self.activeRoundConfiguration?.tempoScale ?? 1) == tempoScale,
                      self.keyboardGeometry?.cacheID == geometryCacheID
                else {
                    return
                }
                self.replacePianoDemonstrationMotionClipSet(PianoDemonstrationMotionClipSet(
                    transportGeneration: fingeringPlan.transportGeneration,
                    geometryCacheID: geometryCacheID,
                    clips: result.clips,
                    rejectedOccurrenceIDs: result.rejectedOccurrenceIDs
                ))
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    func cancelPianoHandMotionClipBuild() {
        pianoHandMotionClipBuildGeneration &+= 1
        pianoHandMotionClipBuildTask?.cancel()
        pianoHandMotionClipBuildTask = nil
        replacePianoDemonstrationMotionClipSet(nil)
    }

    func startManualReplay(with plan: ManualReplayPlan) {
        stopVirtualPianoInput()
        manualReplayService?.startManualReplay(with: plan)
    }

    func stopManualReplayTask(restoreAudioRecognition: Bool = true) {
        manualReplayService?.stopManualReplayTask(restoreAudioRecognition: restoreAudioRecognition)
    }
}

private extension PianoFingeringKeyboardLayout {
    init(keyboardGeometry: PianoKeyboardGeometry) {
        self.init(keys: keyboardGeometry.keys.map { key in
            let kind: PianoFingeringKeyboardLayout.KeyKind
            switch key.kind {
            case .white:
                kind = .white
            case .black:
                kind = .black
            }
            return PianoFingeringKeyboardLayout.Key(
                midiNote: key.midiNote,
                kind: kind,
                localX: Double(key.localCenter.x)
            )
        })
    }
}

private extension PianoHandMotionClipBuilder.KeyboardLayout {
    init(keyboardGeometry: PianoKeyboardGeometry) {
        self.init(keys: keyboardGeometry.keys.map {
            .init(
                midiNote: $0.midiNote,
                contactPositionLocal: SIMD3<Float>(
                    $0.localCenter.x,
                    $0.surfaceLocalY,
                    $0.localCenter.z
                ),
                surfaceLocalY: $0.surfaceLocalY,
                topSurfaceSizeLocal: SIMD2($0.localSize.x, $0.localSize.z)
            )
        })
    }
}
