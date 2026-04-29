import Foundation
import os

extension PracticeSessionViewModel {
    func startAutoplayTaskIfNeeded() {
        guard autoplayState == .playing else { return }
        guard case .guiding = state else { return }
        guard steps.isEmpty == false else { return }
        if let error = autoplayStartErrorMessage() {
            stopAutoplayWithError(error)
            return
        }

        guard autoplayTask == nil else { return }

        autoplayTaskGeneration += 1
        let generation = autoplayTaskGeneration
        resetAutoplayCursorForCurrentStep()
        let tempoMapSnapshot = tempoMap
        let isTimingDebugEnabled = UserDefaults.standard.bool(forKey: "practiceTimingDebugEnabled")
        let timingStartWallSeconds = timingClock.nowSeconds()
        let timingBaseTick = currentStep?.tick ?? 0
        let timingBaseTempoSeconds = tempoMapSnapshot.timeSeconds(atTick: timingBaseTick)
        var timingPauseOffsetSeconds: TimeInterval = 0
        var timingLoopCount = 0

        autoplayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var currentTick = timingBaseTick
            isSustainPedalDown = pedalTimeline?.isDown(atTick: currentTick) ?? false
            let initialStats = await processAutoplayEventsWithStats(atTick: currentTick, timingDebugEnabled: isTimingDebugEnabled)
            timingPauseOffsetSeconds += initialStats.pauseSecondsExecuted
            if isTimingDebugEnabled {
                let wallElapsed = timingClock.nowSeconds() - timingStartWallSeconds
                let expectedElapsed = (tempoMapSnapshot.timeSeconds(atTick: currentTick) - timingBaseTempoSeconds)
                    + timingPauseOffsetSeconds
                let driftSeconds = wallElapsed - expectedElapsed
                timingLogger.debug(
                    "autoplay start tick=\(currentTick, privacy: .public) expected=\(expectedElapsed, privacy: .public)s wall=\(wallElapsed, privacy: .public)s drift=\(driftSeconds, privacy: .public)s events=\(initialStats.eventCount, privacy: .public) pause=\(initialStats.pauseSecondsExecuted, privacy: .public)s proc=\(initialStats.processingSeconds, privacy: .public)s"
                )
            }

            while Task.isCancelled == false {
                guard autoplayState == .playing else { break }
                guard case .guiding = state else { break }
                guard currentAutoplayEventIndex < autoplayTimeline.events.count else { break }

                timingLoopCount += 1
                let nextTick = autoplayTimeline.events[currentAutoplayEventIndex].tick
                let deltaTicks = nextTick - currentTick
                let expectedElapsed = (tempoMapSnapshot.timeSeconds(atTick: nextTick) - timingBaseTempoSeconds)
                    + timingPauseOffsetSeconds
                let wallElapsed = timingClock.nowSeconds() - timingStartWallSeconds
                let waitSeconds = expectedElapsed - wallElapsed

                if waitSeconds >= 0.01 {
                    try? await sleeper.sleep(for: .seconds(waitSeconds))
                }

                guard Task.isCancelled == false else { break }
                guard autoplayState == .playing else { break }
                guard case .guiding = state else { break }

                currentTick = nextTick
                let stats = await processAutoplayEventsWithStats(atTick: currentTick, timingDebugEnabled: isTimingDebugEnabled)
                timingPauseOffsetSeconds += stats.pauseSecondsExecuted
                if isTimingDebugEnabled {
                    let wallElapsedAfter = timingClock.nowSeconds() - timingStartWallSeconds
                    let expectedElapsedAfter = (tempoMapSnapshot.timeSeconds(atTick: currentTick) - timingBaseTempoSeconds)
                        + timingPauseOffsetSeconds
                    let driftSeconds = wallElapsedAfter - expectedElapsedAfter
                    if stats.pauseSecondsExecuted > 0 || driftSeconds > 0.05 || timingLoopCount.isMultiple(of: 50) {
                        timingLogger.debug(
                            "autoplay tick=\(currentTick, privacy: .public) Δtick=\(deltaTicks, privacy: .public) wait=\(waitSeconds, privacy: .public)s pause=\(stats.pauseSecondsExecuted, privacy: .public)s expected=\(expectedElapsedAfter, privacy: .public)s wall=\(wallElapsedAfter, privacy: .public)s drift=\(driftSeconds, privacy: .public)s events=\(stats.eventCount, privacy: .public) on=\(stats.noteOnCount, privacy: .public) off=\(stats.noteOffCount, privacy: .public) step=\(stats.advanceStepCount, privacy: .public) guide=\(stats.advanceGuideCount, privacy: .public) proc=\(stats.processingSeconds, privacy: .public)s"
                        )
                    }
                }
            }

            guard self.autoplayTaskGeneration == generation else { return }
            self.autoplayTask = nil
        }
    }

    private func autoplayStartErrorMessage() -> String? {
        guard noteOutput != nil else {
            return "无法自动播放：音频输出未就绪。请重启 App 或重新打开曲目。"
        }
        guard pedalTimeline != nil else {
            return "无法自动播放：缺少踏板信息。请重新导入这份 MusicXML。"
        }
        guard fermataTimeline != nil else {
            return "无法自动播放：缺少延长停顿（fermata）信息。请重新导入这份 MusicXML。"
        }
        guard highlightGuides.isEmpty == false else {
            return "无法自动播放：缺少键盘高亮引导数据。请重新导入这份 MusicXML。"
        }
        guard strictTriggerGuideIndex(forStepIndex: currentStepIndex) != nil else {
            return "无法自动播放：引导数据不一致（找不到当前步骤的触发点）。请重新导入这份 MusicXML。"
        }
        return nil
    }

    private func stopAutoplayWithError(_ message: String) {
        autoplayState = .off
        stopAutoplayTask()
        stopAutoplayAudio()
        autoplayErrorMessage = message
        refreshAudioRecognitionForCurrentState()
    }

    private func strictTriggerGuideIndex(forStepIndex stepIndex: Int) -> Int? {
        highlightGuides.firstIndex { guide in
            guide.practiceStepIndex == stepIndex && guide.kind == .trigger
        }
    }

    func setCurrentHighlightGuideForStepIndex(_ stepIndex: Int) {
        guard steps.indices.contains(stepIndex) else {
            currentHighlightGuideIndex = nil
            return
        }
        currentHighlightGuideIndex = strictTriggerGuideIndex(forStepIndex: stepIndex)
    }

    func updateHighlightGuideAfterStepAdvance(previousTick: Int, nextStepIndex: Int) {
        guard autoplayState == .off else {
            setCurrentHighlightGuideForStepIndex(nextStepIndex)
            return
        }
        manualHighlightTransitionTask?.cancel()
        guard steps.indices.contains(nextStepIndex) else {
            currentHighlightGuideIndex = nil
            return
        }
        let nextTick = steps[nextStepIndex].tick
        let transitionIndex = highlightGuides.firstIndex { guide in
            guide.tick > previousTick && guide.tick < nextTick && (guide.kind == .release || guide.kind == .gap)
        }
        guard let transitionIndex else {
            setCurrentHighlightGuideForStepIndex(nextStepIndex)
            return
        }
        currentHighlightGuideIndex = transitionIndex
        manualHighlightTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await sleeper.sleep(for: .seconds(0.12))
            guard Task.isCancelled == false else { return }
            setCurrentHighlightGuideForStepIndex(nextStepIndex)
            manualHighlightTransitionTask = nil
        }
    }

    func rebuildAutoplayTimeline() {
        guard
            let pedalTimeline,
            let fermataTimeline,
            highlightGuides.isEmpty == false
        else {
            autoplayTimeline = .empty
            resetAutoplayCursorForCurrentStep()
            return
        }

        autoplayTimeline = AutoplayPerformanceTimeline.build(
            guides: highlightGuides,
            steps: steps,
            pedalTimeline: pedalTimeline,
            fermataTimeline: fermataTimeline,
            tempoMap: tempoMap
        )
        resetAutoplayCursorForCurrentStep()
    }

    func resetAutoplayCursorForCurrentStep() {
        let tick = currentStep?.tick ?? 0
        currentAutoplayEventIndex = autoplayTimeline.firstEventIndex(atOrAfter: tick)
    }

    private struct AutoplayTickStats: Equatable {
        var eventCount: Int = 0
        var noteOnCount: Int = 0
        var noteOffCount: Int = 0
        var advanceStepCount: Int = 0
        var advanceGuideCount: Int = 0
        var pauseSecondsExecuted: TimeInterval = 0
        var processingSeconds: TimeInterval = 0
    }

    private func processAutoplayEventsWithStats(atTick tick: Int, timingDebugEnabled: Bool) async -> AutoplayTickStats {
        if timingDebugEnabled == false {
            var stats = AutoplayTickStats()
            while currentAutoplayEventIndex < autoplayTimeline.events.count,
                  autoplayTimeline.events[currentAutoplayEventIndex].tick == tick
            {
                let event = autoplayTimeline.events[currentAutoplayEventIndex]
                currentAutoplayEventIndex += 1

                if case let .pauseSeconds(seconds) = event.kind {
                    if seconds > 0 {
                        stats.pauseSecondsExecuted += seconds
                        try? await sleeper.sleep(for: .seconds(seconds))
                        guard Task.isCancelled == false else { return stats }
                        guard autoplayState == .playing else { return stats }
                    }
                } else {
                    processAutoplayEvent(event)
                }
            }
            return stats
        }

        let clock = ContinuousClock()
        let startInstant = clock.now
        var stats = AutoplayTickStats()
        while currentAutoplayEventIndex < autoplayTimeline.events.count,
              autoplayTimeline.events[currentAutoplayEventIndex].tick == tick
        {
            let event = autoplayTimeline.events[currentAutoplayEventIndex]
            currentAutoplayEventIndex += 1
            stats.eventCount += 1

            if case let .pauseSeconds(seconds) = event.kind {
                if seconds > 0 {
                    stats.pauseSecondsExecuted += seconds
                    try? await sleeper.sleep(for: .seconds(seconds))
                    guard Task.isCancelled == false else { return stats }
                    guard autoplayState == .playing else { return stats }
                }
            } else {
                switch event.kind {
                    case .noteOn:
                        stats.noteOnCount += 1
                    case .noteOff:
                        stats.noteOffCount += 1
                    case .advanceStep:
                        stats.advanceStepCount += 1
                    case .advanceGuide:
                        stats.advanceGuideCount += 1
                    case .pauseSeconds:
                        break
                    case .pedalDown, .pedalUp:
                        break
                }
                processAutoplayEvent(event)
            }
        }
        stats.processingSeconds = Self.durationSeconds(startInstant.duration(to: clock.now))
        return stats
    }

    private func processAutoplayEvent(_ event: AutoplayPerformanceTimeline.Event) {
        guard autoplayState == .playing else { return }

        switch event.kind {
            case .pauseSeconds:
                break
            case let .noteOff(midi):
                handleAutoplayNoteOff(midi: midi, atTick: event.tick)
            case .pedalDown:
                isSustainPedalDown = true
            case .pedalUp:
                isSustainPedalDown = false
                releasePendingAutoplayNotes(atTick: event.tick)
            case let .noteOn(midi, velocity):
                handleAutoplayNoteOn(midi: midi, velocity: velocity)
            case let .advanceStep(index):
                advanceAutoplayStep(to: index)
            case let .advanceGuide(index, _):
                currentHighlightGuideIndex = index
        }
    }

    private func handleAutoplayNoteOn(midi: Int, velocity: UInt8) {
        guard let noteOutput else { return }
        guard audioPlaybackErrorMessage == nil else { return }

        if activeAutoplayMIDINotes.contains(midi) {
            noteOutput.noteOff(midi: midi)
            activeAutoplayMIDINotes.remove(midi)
            pendingPedalReleaseOffTickByMIDI[midi] = nil
        }

        do {
            try noteOutput.noteOn(midi: midi, velocity: velocity)
            activeAutoplayMIDINotes.insert(midi)
        } catch {
            recordPlaybackError(error)
        }
    }

    private func handleAutoplayNoteOff(midi: Int, atTick tick: Int) {
        guard activeAutoplayMIDINotes.contains(midi) else { return }

        if isSustainPedalDown {
            pendingPedalReleaseOffTickByMIDI[midi] = tick
        } else {
            noteOutput?.noteOff(midi: midi)
            activeAutoplayMIDINotes.remove(midi)
        }
    }

    private func releasePendingAutoplayNotes(atTick tick: Int) {
        let releasable = pendingPedalReleaseOffTickByMIDI.filter { _, offTick in
            offTick <= tick
        }

        for (midi, _) in releasable {
            pendingPedalReleaseOffTickByMIDI[midi] = nil
            if activeAutoplayMIDINotes.contains(midi) {
                noteOutput?.noteOff(midi: midi)
                activeAutoplayMIDINotes.remove(midi)
            }
        }
    }

    private func advanceAutoplayStep(to stepIndex: Int) {
        guard steps.indices.contains(stepIndex) else { return }
        guard currentStepIndex != stepIndex else { return }
        chordAttemptAccumulator.reset()
        currentStepIndex = stepIndex
        state = .guiding(stepIndex: stepIndex)
        refreshAudioRecognitionForCurrentState()
    }

    func stopAutoplayTask() {
        autoplayTaskGeneration += 1
        autoplayTask?.cancel()
        autoplayTask = nil
    }

    func stopAutoplayAudio() {
        activeAutoplayMIDINotes = []
        pendingPedalReleaseOffTickByMIDI = [:]
        resetAutoplayCursorForCurrentStep()
        noteOutput?.allNotesOff()
    }
}
