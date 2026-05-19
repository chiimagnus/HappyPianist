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
        let timelineSnapshot = autoplayTimeline
        let tempoMapSnapshot = tempoMap
        let timingBaseTick = currentStep?.tick ?? 0
        autoplayTimingBaseTick = timingBaseTick
        notationGuideScrollScheduleTaskGeneration = -1

        autoplayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let initialSustainPedalDown = pedalTimeline?.isDown(atTick: timingBaseTick) ?? false
            isSustainPedalDown = initialSustainPedalDown
            let leadInSeconds = autoplayTimingLeadInSeconds

            do {
                try sequencerPlaybackService.warmUp()
            } catch {
                recordPlaybackError(error)
                stopAutoplayWithError(audioPlaybackErrorMessage ?? "无法自动播放：音频服务初始化失败。")
                return
            }

            let sequence: PracticeSequencerSequence
            do {
                sequence = try await playbackSequenceBuilder.buildAutoplaySequence(
                    timeline: timelineSnapshot,
                    tempoMap: tempoMapSnapshot,
                    startTick: timingBaseTick,
                    initialSustainPedalDown: initialSustainPedalDown,
                    leadInSeconds: leadInSeconds
                )
            } catch {
                recordPlaybackError(error)
                stopAutoplayWithError(audioPlaybackErrorMessage ?? "无法自动播放：构建 MIDI 序列失败。")
                return
            }

            do {
                try sequencerPlaybackService.load(sequence: sequence)
                try sequencerPlaybackService.play(fromSeconds: 0)
            } catch {
                recordPlaybackError(error)
                stopAutoplayWithError(audioPlaybackErrorMessage ?? "无法自动播放：播放服务启动失败。")
                return
            }

            decisionLogger.debug(
                "autoplay sequencer started leadIn=\(leadInSeconds, privacy: .public)s now=\(sequencerPlaybackService.currentSeconds(), privacy: .public)s"
            )

            var cursor = AutoplayTimelineTimeCursor(
                timeline: timelineSnapshot,
                tickToSeconds: { tempoMapSnapshot.timeSeconds(atTick: $0) },
                startTick: timingBaseTick,
                leadInSeconds: leadInSeconds
            )
            var pedalCursor = AutoplayTimelinePedalTimeCursor(
                timeline: timelineSnapshot,
                tickToSeconds: { tempoMapSnapshot.timeSeconds(atTick: $0) },
                startTick: timingBaseTick,
                initialIsDown: isSustainPedalDown,
                leadInSeconds: leadInSeconds
            )
            let sequenceEndSeconds = max(0, sequence.durationSeconds)

            while Task.isCancelled == false {
                guard autoplayState == .playing else { break }
                guard case .guiding = state else { break }

                let nowSeconds = sequencerPlaybackService.currentSeconds()

                if let isDown = pedalCursor.advance(toSeconds: nowSeconds) {
                    isSustainPedalDown = isDown
                }

                let events = cursor.advance(toSeconds: nowSeconds)
                for event in events {
                    switch event {
                        case let .step(index):
                            advanceAutoplayStep(to: index)
                        case let .guide(index, _):
                            currentHighlightGuideIndex = index
                    }
                }

                if nowSeconds >= sequenceEndSeconds, pedalCursor.isFinished, cursor.isFinished {
                    break
                }

                try? await Task.sleep(for: .milliseconds(33))
            }

            if Task.isCancelled == false {
                sequencerPlaybackService.stop()
            }

            guard autoplayTaskGeneration == generation else { return }
            autoplayTask = nil
        }
    }

    private func autoplayStartErrorMessage() -> String? {
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

    func rebuildAutoplayTimeline() {
        guard
            let pedalTimeline,
            let fermataTimeline,
            highlightGuides.isEmpty == false
        else {
            autoplayTimeline = .empty
            return
        }

        autoplayTimeline = AutoplayPerformanceTimeline.build(
            guides: highlightGuides,
            steps: steps,
            pedalTimeline: pedalTimeline,
            fermataTimeline: fermataTimeline,
            tempoMap: tempoMap
        )
    }

    private struct AutoplayTimelinePedalTimeCursor: Equatable {
        private struct TimedPedal: Equatable {
            let timeSeconds: TimeInterval
            let isDown: Bool
        }

        private let scheduled: [TimedPedal]
        private var nextIndex: Int
        private var latestIsDown: Bool

        init(
            timeline: AutoplayPerformanceTimeline,
            tickToSeconds: (Int) -> TimeInterval,
            startTick: Int,
            initialIsDown: Bool,
            leadInSeconds: TimeInterval = 0
        ) {
            let baseTick = max(0, startTick)
            let baseSeconds = tickToSeconds(baseTick)

            let startIndex = timeline.firstEventIndex(atOrAfter: baseTick)
            var pausePrefixSeconds: TimeInterval = 0

            var scheduled: [TimedPedal] = []
            scheduled.reserveCapacity(32)

            for event in timeline.events[startIndex...] {
                switch event.kind {
                    case let .pauseSeconds(seconds):
                        pausePrefixSeconds += seconds

                    case .pedalDown:
                        scheduled.append(
                            TimedPedal(
                                timeSeconds: tickToSeconds(event.tick) - baseSeconds + pausePrefixSeconds +
                                    leadInSeconds,
                                isDown: true
                            )
                        )

                    case .pedalUp:
                        scheduled.append(
                            TimedPedal(
                                timeSeconds: tickToSeconds(event.tick) - baseSeconds + pausePrefixSeconds +
                                    leadInSeconds,
                                isDown: false
                            )
                        )

                    case .noteOn, .noteOff, .advanceStep, .advanceGuide:
                        continue
                }
            }

            self.scheduled = scheduled
            nextIndex = 0
            latestIsDown = initialIsDown
        }

        var isFinished: Bool {
            nextIndex >= scheduled.count
        }

        mutating func advance(toSeconds now: TimeInterval) -> Bool? {
            var updated = false
            while nextIndex < scheduled.count, scheduled[nextIndex].timeSeconds <= now {
                latestIsDown = scheduled[nextIndex].isDown
                nextIndex += 1
                updated = true
            }
            return updated ? latestIsDown : nil
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
        autoplayTimingBaseTick = nil
        notationGuideScrollSchedule.removeAll()
        notationGuideScrollScheduleTaskGeneration = -1
    }

    func stopAutoplayAudio() {
        sequencerPlaybackService.stop()
    }

    func smoothNotationScrollTick() -> Double? {
        guard autoplayState == .playing, autoplayTask != nil else { return nil }
        guard let baseTick = autoplayTimingBaseTick else { return nil }

        let schedule = ensureNotationGuideScrollSchedule(baseTick: baseTick)
        let fallbackTick = Double(currentPianoHighlightGuide?.tick ?? baseTick)
        guard schedule.isEmpty == false else { return fallbackTick }

        let nowSeconds = sequencerPlaybackService.currentSeconds()
        guard nowSeconds.isFinite else { return fallbackTick }

        if nowSeconds <= schedule[0].timeSeconds {
            return Double(schedule[0].tick)
        }
        if let last = schedule.last, nowSeconds >= last.timeSeconds {
            return Double(last.tick)
        }

        var low = 0
        var high = schedule.count - 1
        var best = 0
        while low <= high {
            let mid = (low + high) / 2
            if schedule[mid].timeSeconds <= nowSeconds {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        let currentIndex = min(best, schedule.count - 1)
        let nextIndex = min(currentIndex + 1, schedule.count - 1)
        guard currentIndex != nextIndex else { return Double(schedule[currentIndex].tick) }

        let currentPoint = schedule[currentIndex]
        let nextPoint = schedule[nextIndex]
        let duration = max(0.000_1, nextPoint.timeSeconds - currentPoint.timeSeconds)
        let fraction = max(0, min(1, (nowSeconds - currentPoint.timeSeconds) / duration))
        return Double(currentPoint.tick) + Double(nextPoint.tick - currentPoint.tick) * fraction
    }

    private func ensureNotationGuideScrollSchedule(baseTick: Int) -> [NotationGuideScrollPoint] {
        if notationGuideScrollScheduleTaskGeneration == autoplayTaskGeneration,
           notationGuideScrollScheduleBaseTick == baseTick,
           notationGuideScrollScheduleTimelineEventCount == autoplayTimeline.events.count
        {
            return notationGuideScrollSchedule
        }

        let safeBaseTick = max(0, baseTick)
        let baseSeconds = tempoMap.timeSeconds(atTick: safeBaseTick)
        let startIndex = autoplayTimeline.firstEventIndex(atOrAfter: safeBaseTick)

        var pausePrefixSeconds: TimeInterval = 0
        var points: [NotationGuideScrollPoint] = []
        points.reserveCapacity(max(16, highlightGuides.count))

        for event in autoplayTimeline.events[startIndex...] {
            switch event.kind {
                case let .pauseSeconds(seconds):
                    pausePrefixSeconds += seconds

                case .advanceGuide:
                    points.append(
                        NotationGuideScrollPoint(
                            timeSeconds: tempoMap.timeSeconds(atTick: event.tick) - baseSeconds + pausePrefixSeconds +
                                autoplayTimingLeadInSeconds,
                            tick: event.tick
                        )
                    )

                case .noteOn, .noteOff, .pedalDown, .pedalUp, .advanceStep:
                    continue
            }
        }

        notationGuideScrollSchedule = points
        notationGuideScrollScheduleBaseTick = baseTick
        notationGuideScrollScheduleTaskGeneration = autoplayTaskGeneration
        notationGuideScrollScheduleTimelineEventCount = autoplayTimeline.events.count
        return points
    }
}
