import Foundation

/// Continuous-duet helpers for prompt extraction, short-window policy, and response shaping.
enum DuetPhrasePolicy {
    struct RequestPolicy: Equatable {
        let lookbackSeconds: TimeInterval
        let maxPromptSeconds: TimeInterval
        let requestWindowSeconds: TimeInterval
        let minRequestIntervalSeconds: TimeInterval
        let maxTokens: Int
    }

    struct QualityAssessment: Equatable {
        enum Band: String, Equatable {
            case acceptable
            case risky
            case reject
        }

        enum Reason: String, Equatable {
            case registerCollision
            case densityOverload
            case excessiveRepetition
            case fragmentedWindow
            case extremeLeap
        }

        let band: Band
        let score: Int
        let reasons: [Reason]
        let noteOnCount: Int
        let effectiveDurationSeconds: TimeInterval

        var primaryReason: Reason? {
            reasons.first
        }
    }

    static func requestPolicy(for decision: DuetTurnTakingCore.Decision) -> RequestPolicy {
        RequestPolicy(
            lookbackSeconds: 4.0,
            maxPromptSeconds: 3.0,
            requestWindowSeconds: decision.requestWindowSeconds,
            minRequestIntervalSeconds: decision.minRequestIntervalSeconds,
            maxTokens: decision.maxTokens
        )
    }

    static func buildPromptEvents(
        noteSnapshot: DuetPhraseBuffer.Snapshot,
        ccSnapshot: DuetPhraseEventBuffer.Snapshot,
        policy _: RequestPolicy
    ) -> [ImprovEvent] {
        let noteEvents = noteSnapshot.promptNotes.map { note in
            ImprovEvent.note(note: note.note, velocity: note.velocity, time: note.time, duration: note.duration)
        }

        return (ccSnapshot.promptEvents + noteEvents).sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            if lhs.type != rhs.type { return lhs.type == .cc }
            switch (lhs.type, rhs.type) {
            case (.cc, .cc):
                return (lhs.controller ?? 0) < (rhs.controller ?? 0)
            case (.note, .note):
                return (lhs.note ?? 0) < (rhs.note ?? 0)
            default:
                return false
            }
        }
    }

    static func assessSchedule(
        _ schedule: [PracticeSequencerMIDIEvent],
        noteSnapshot: DuetPhraseBuffer.Snapshot,
        horizonSeconds: TimeInterval
    ) -> QualityAssessment {
        let noteOnEvents = schedule.compactMap { event -> (time: TimeInterval, midi: Int)? in
            guard case let .noteOn(midi, _) = event.kind else { return nil }
            return (event.timeSeconds, midi)
        }.sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return lhs.midi < rhs.midi
        }

        guard noteOnEvents.isEmpty == false else {
            return QualityAssessment(
                band: .reject,
                score: 0,
                reasons: [.fragmentedWindow],
                noteOnCount: 0,
                effectiveDurationSeconds: 0
            )
        }

        let lastNoteEventTime = schedule.compactMap { event -> TimeInterval? in
            switch event.kind {
            case .noteOn, .noteOff:
                event.timeSeconds
            case .controlChange, .pitchBend, .programChange, .channelPressure, .polyPressure:
                nil
            }
        }.max() ?? 0
        let effectiveDurationSeconds = min(max(0.05, lastNoteEventTime), max(0.2, horizonSeconds))
        let density = Double(noteOnEvents.count) / effectiveDurationSeconds
        let repeatedRunLength = maxRepeatedRunLength(noteOnEvents.map(\.midi))
        let maxLeap = maxMelodicLeap(noteOnEvents)
        let collisionCount = noteOnEvents.count(where: { event in
            let nearHeldNote = noteSnapshot.heldNoteMIDIs.contains(where: { abs($0 - event.midi) <= 2 })
            let nearPitchCenter = noteSnapshot.activePitchCenter.map { abs($0 - Double(event.midi)) <= 1.5 } ?? false
            return nearHeldNote || nearPitchCenter
        })
        let isFragmentedWindow = noteOnEvents.count <= 1 && effectiveDurationSeconds < 0.12

        var score = 100
        var reasons: [QualityAssessment.Reason] = []
        var rejected = false

        if isFragmentedWindow {
            reasons.append(.fragmentedWindow)
            score -= 70
            rejected = true
        }

        if density >= 9 {
            reasons.append(.densityOverload)
            score -= 50
            rejected = true
        } else if density >= 5 {
            reasons.append(.densityOverload)
            score -= 25
        }

        if repeatedRunLength >= 4 {
            reasons.append(.excessiveRepetition)
            score -= 45
            rejected = true
        } else if repeatedRunLength == 3 {
            reasons.append(.excessiveRepetition)
            score -= 20
        }

        if maxLeap >= 24 {
            reasons.append(.extremeLeap)
            score -= 45
            rejected = true
        } else if maxLeap >= 16 {
            reasons.append(.extremeLeap)
            score -= 20
        }

        if collisionCount >= max(2, noteOnEvents.count / 2) {
            reasons.append(.registerCollision)
            score -= 35
            rejected = true
        } else if collisionCount > 0 {
            reasons.append(.registerCollision)
            score -= 15
        }

        score = max(0, score)
        let band: QualityAssessment.Band = if rejected || score < 45 {
            .reject
        } else if reasons.isEmpty == false || score < 80 {
            .risky
        } else {
            .acceptable
        }

        return QualityAssessment(
            band: band,
            score: score,
            reasons: reasons,
            noteOnCount: noteOnEvents.count,
            effectiveDurationSeconds: effectiveDurationSeconds
        )
    }

    static func shapeSchedule(
        _ schedule: [PracticeSequencerMIDIEvent],
        noteSnapshot: DuetPhraseBuffer.Snapshot,
        controlMode: DuetTurnTakingCore.Mode,
        horizonSeconds: TimeInterval
    ) -> [PracticeSequencerMIDIEvent] {
        guard schedule.isEmpty == false else { return [] }
        guard controlMode != .silent, controlMode != .yield else { return [] }

        let clippedHorizon = max(0.2, horizonSeconds)
        let heldMIDIs = noteSnapshot.heldNoteMIDIs

        var droppedNoteDepths: [Int: Int] = [:]
        var retainedNoteDepths: [Int: Int] = [:]
        var noteOnIndex = 0
        var shaped: [PracticeSequencerMIDIEvent] = []

        for event in schedule.sorted(by: sortEvents) {
            switch event.kind {
            case let .noteOn(midi, velocity):
                guard event.timeSeconds < clippedHorizon else { continue }
                let shouldDropForConflict = heldMIDIs.contains(midi)
                let shouldDropForSparse = controlMode == .sparse && noteOnIndex.isMultiple(of: 2) == false
                noteOnIndex += 1

                if shouldDropForConflict || shouldDropForSparse {
                    droppedNoteDepths[midi, default: 0] += 1
                    continue
                }

                retainedNoteDepths[midi, default: 0] += 1
                shaped.append(
                    PracticeSequencerMIDIEvent(
                        timeSeconds: max(0, event.timeSeconds),
                        kind: .noteOn(midi: midi, velocity: adjustedVelocity(velocity, mode: controlMode))
                    )
                )

            case let .noteOff(midi):
                if (droppedNoteDepths[midi] ?? 0) > 0 {
                    droppedNoteDepths[midi, default: 0] -= 1
                    continue
                }
                guard (retainedNoteDepths[midi] ?? 0) > 0 else { continue }
                retainedNoteDepths[midi, default: 0] -= 1
                shaped.append(
                    PracticeSequencerMIDIEvent(
                        timeSeconds: min(clippedHorizon, max(0, event.timeSeconds)),
                        kind: .noteOff(midi: midi)
                    )
                )

            case let .controlChange(controller, value):
                guard event.timeSeconds <= clippedHorizon else { continue }
                shaped.append(
                    PracticeSequencerMIDIEvent(
                        timeSeconds: max(0, event.timeSeconds),
                        kind: .controlChange(controller: controller, value: value)
                    )
                )

            case let .pitchBend(value):
                guard event.timeSeconds <= clippedHorizon else { continue }
                shaped.append(
                    PracticeSequencerMIDIEvent(
                        timeSeconds: max(0, event.timeSeconds),
                        kind: .pitchBend(value: value)
                    )
                )

            case let .programChange(program):
                guard event.timeSeconds <= clippedHorizon else { continue }
                shaped.append(
                    PracticeSequencerMIDIEvent(
                        timeSeconds: max(0, event.timeSeconds),
                        kind: .programChange(program: program)
                    )
                )

            case let .channelPressure(value):
                guard event.timeSeconds <= clippedHorizon else { continue }
                shaped.append(
                    PracticeSequencerMIDIEvent(
                        timeSeconds: max(0, event.timeSeconds),
                        kind: .channelPressure(value: value)
                    )
                )

            case let .polyPressure(midi, value):
                guard event.timeSeconds <= clippedHorizon else { continue }
                shaped.append(
                    PracticeSequencerMIDIEvent(
                        timeSeconds: max(0, event.timeSeconds),
                        kind: .polyPressure(midi: midi, value: value)
                    )
                )
            }
        }

        let guardedSchedule = applyQualityGuardrails(
            to: shaped.sorted(by: sortEvents),
            noteSnapshot: noteSnapshot,
            horizonSeconds: clippedHorizon,
            controlMode: controlMode
        )
        return closeOpenNotes(in: guardedSchedule, at: clippedHorizon)
    }

    private static func closeOpenNotes(
        in schedule: [PracticeSequencerMIDIEvent],
        at horizonSeconds: TimeInterval
    ) -> [PracticeSequencerMIDIEvent] {
        guard schedule.isEmpty == false else { return [] }

        var openDepths: [Int: Int] = [:]
        for event in schedule.sorted(by: sortEvents) {
            switch event.kind {
            case let .noteOn(midi, _):
                openDepths[midi, default: 0] += 1
            case let .noteOff(midi):
                guard (openDepths[midi] ?? 0) > 0 else { continue }
                openDepths[midi, default: 0] -= 1
            case .controlChange, .pitchBend, .programChange, .channelPressure, .polyPressure:
                continue
            }
        }

        var closed = schedule
        for (midi, openDepth) in openDepths where openDepth > 0 {
            for _ in 0 ..< openDepth {
                closed.append(
                    PracticeSequencerMIDIEvent(
                        timeSeconds: horizonSeconds,
                        kind: .noteOff(midi: midi)
                    )
                )
            }
        }
        return closed.sorted(by: sortEvents)
    }

    private static func maxMelodicLeap(_ events: [(time: TimeInterval, midi: Int)]) -> Int {
        let groups = Dictionary(grouping: events, by: { $0.time })
        let onsetCenters = groups.keys.sorted().compactMap { onset -> Double? in
            guard let group = groups[onset], group.isEmpty == false else { return nil }
            return Double(group.map(\.midi).reduce(0, +)) / Double(group.count)
        }
        return zip(onsetCenters.dropFirst(), onsetCenters)
            .map { Int(abs($0 - $1).rounded()) }
            .max() ?? 0
    }

    private static func adjustedVelocity(_ velocity: UInt8, mode: DuetTurnTakingCore.Mode) -> UInt8 {
        switch mode {
        case .support:
            UInt8(clamping: Int((Double(velocity) * 0.85).rounded()))
        case .sparse:
            UInt8(clamping: Int((Double(velocity) * 0.65).rounded()))
        case .yield, .silent:
            0
        }
    }

    private static func sortEvents(_ lhs: PracticeSequencerMIDIEvent, _ rhs: PracticeSequencerMIDIEvent) -> Bool {
        if lhs.timeSeconds != rhs.timeSeconds { return lhs.timeSeconds < rhs.timeSeconds }
        if eventPriority(lhs.kind) != eventPriority(rhs.kind) {
            return eventPriority(lhs.kind) < eventPriority(rhs.kind)
        }
        return tieBreaker(lhs.kind) < tieBreaker(rhs.kind)
    }

    private static func eventPriority(_ kind: PracticeSequencerMIDIEvent.Kind) -> Int {
        switch kind {
        case .controlChange:
            0
        case .programChange, .pitchBend, .channelPressure, .polyPressure:
            1
        case .noteOff:
            2
        case .noteOn:
            3
        }
    }

    private static func tieBreaker(_ kind: PracticeSequencerMIDIEvent.Kind) -> Int {
        switch kind {
        case let .controlChange(controller, value):
            Int(controller) * 256 + Int(value)
        case let .noteOff(midi):
            midi
        case let .noteOn(midi, velocity):
            midi * 256 + Int(velocity)
        case let .pitchBend(value):
            1_000_000 + Int(value)
        case let .programChange(program):
            2_000_000 + Int(program)
        case let .channelPressure(value):
            3_000_000 + Int(value)
        case let .polyPressure(midi, value):
            4_000_000 + midi * 256 + Int(value)
        }
    }

    private static func applyQualityGuardrails(
        to schedule: [PracticeSequencerMIDIEvent],
        noteSnapshot: DuetPhraseBuffer.Snapshot,
        horizonSeconds: TimeInterval,
        controlMode: DuetTurnTakingCore.Mode
    ) -> [PracticeSequencerMIDIEvent] {
        let assessment = assessSchedule(schedule, noteSnapshot: noteSnapshot, horizonSeconds: horizonSeconds)
        switch assessment.band {
        case .acceptable:
            return schedule
        case .reject:
            return []
        case .risky:
            let salvaged = salvageSchedule(schedule, controlMode: controlMode, horizonSeconds: horizonSeconds)
            let salvagedAssessment = assessSchedule(salvaged, noteSnapshot: noteSnapshot, horizonSeconds: horizonSeconds)
            return salvagedAssessment.band == .reject ? [] : salvaged
        }
    }

    private static func salvageSchedule(
        _ schedule: [PracticeSequencerMIDIEvent],
        controlMode: DuetTurnTakingCore.Mode,
        horizonSeconds: TimeInterval
    ) -> [PracticeSequencerMIDIEvent] {
        var droppedNoteDepths: [Int: Int] = [:]
        var keptNoteOnCount = 0
        let velocityScale: Double = controlMode == .support ? 0.75 : 0.65
        var salvaged: [PracticeSequencerMIDIEvent] = []

        for event in schedule.sorted(by: sortEvents) {
            switch event.kind {
            case let .noteOn(midi, velocity):
                let keepThisNote = keptNoteOnCount.isMultiple(of: 2)
                keptNoteOnCount += 1
                guard keepThisNote else {
                    droppedNoteDepths[midi, default: 0] += 1
                    continue
                }
                salvaged.append(
                    PracticeSequencerMIDIEvent(
                        timeSeconds: min(horizonSeconds, max(0, event.timeSeconds)),
                        kind: .noteOn(
                            midi: midi,
                            velocity: UInt8(clamping: Int((Double(velocity) * velocityScale).rounded()))
                        )
                    )
                )

            case let .noteOff(midi):
                if (droppedNoteDepths[midi] ?? 0) > 0 {
                    droppedNoteDepths[midi, default: 0] -= 1
                    continue
                }
                salvaged.append(
                    PracticeSequencerMIDIEvent(
                        timeSeconds: min(horizonSeconds, max(0, event.timeSeconds)),
                        kind: .noteOff(midi: midi)
                    )
                )

            case .controlChange, .pitchBend, .programChange, .channelPressure, .polyPressure:
                salvaged.append(event)
            }
        }

        return salvaged.sorted(by: sortEvents)
    }

    private static func maxRepeatedRunLength(_ values: [Int]) -> Int {
        guard let first = values.first else { return 0 }
        var maxRunLength = 1
        var currentRunLength = 1
        var previous = first

        for value in values.dropFirst() {
            if value == previous {
                currentRunLength += 1
            } else {
                maxRunLength = max(maxRunLength, currentRunLength)
                currentRunLength = 1
                previous = value
            }
        }

        return max(maxRunLength, currentRunLength)
    }
}
