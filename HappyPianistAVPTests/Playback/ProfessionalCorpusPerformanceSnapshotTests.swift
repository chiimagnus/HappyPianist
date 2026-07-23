import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func professionalCorpusTimelinesPreserveReviewedPerformanceContracts() throws {
    for fixture in try PianoPerformanceCorpusFixtureLoader().load() {
        let performance = try makeCorpusPerformance(fixture)
        try assertFullTimelineContract(performance)
    }
}

@Test
func professionalCorpusHighRiskFixturesShareAppAndCoreMIDIEventStreams() async throws {
    let fixtures = try PianoPerformanceCorpusFixtureLoader().load().filter(isHighRiskFixture)
    guard fixtures.isEmpty == false else {
        throw CorpusPerformanceSnapshotError.violation(
            fixtureID: "corpus",
            requirementID: "P15-CORPUS-PERFORMANCE",
            detail: "no high-risk fixtures were selected"
        )
    }

    for fixture in fixtures {
        let performance = try makeCorpusPerformance(fixture)
        let range = try makeActiveRange(for: performance)
        let timeline = AutoplayPerformanceTimeline.build(
            plan: performance.plan,
            guideProjection: performance.guides,
            stepProjection: performance.steps,
            tempoMap: performance.tempoMap,
            practiceHandMode: .both,
            activeRange: range,
            transportStartTick: range.tickRange.lowerBound
        )
        let expectedApproximations = PerformanceRangeStateResolver().resolve(
            plan: performance.plan,
            at: range.tickRange.lowerBound,
            practiceHandMode: .both
        ).approximations
        try requirePerformance(
            timeline.rangeStartApproximations == expectedApproximations,
            fixture: fixture,
            detail: "active-range approximation provenance differs: \(PerformanceEventSnapshot().encodePerformanceContract(timeline))"
        )
        try requirePerformance(
            timeline.events.allSatisfy {
                $0.tick >= range.tickRange.lowerBound && $0.tick <= range.tickRange.upperBound
            },
            fixture: fixture,
            detail: "active range emitted an event outside \(range.tickRange)"
        )

        let sequenceBuilder = PracticeSequencerSequenceBuilder()
        let schedule = sequenceBuilder.buildPerformanceEventSchedule(
            timeline: timeline,
            tempoMap: performance.tempoMap,
            startTick: range.tickRange.lowerBound,
            endTick: range.tickRange.upperBound
        )
        let coreMIDISequence = try sequenceBuilder.buildSequence(from: schedule)
        let appSequence = try await PlaybackSequenceBuilder().buildPerformanceSequence(
            timeline: timeline,
            tempoMap: performance.tempoMap,
            startTick: range.tickRange.lowerBound,
            endTick: range.tickRange.upperBound,
            leadInSeconds: 0
        )
        let snapshot = PerformanceEventSnapshot()
        try requireSameEventStream(
            expected: snapshot.encode(coreMIDISequence.events),
            actual: snapshot.encode(appSequence.events),
            fixture: fixture,
            path: "app/CoreMIDI"
        )
        try assertLoopClosesEveryScheduledNote(coreMIDISequence.events, fixture: fixture)
    }
}

private struct CorpusPerformance {
    let fixture: PianoPerformanceCorpusFixture
    let plan: ScorePerformancePlan
    let tempoMap: MusicXMLTempoMap
    let steps: [PracticeStep]
    let guides: [PianoHighlightGuide]
    let timeline: AutoplayPerformanceTimeline
}

private enum CorpusPerformanceSnapshotError: Error, LocalizedError {
    case violation(fixtureID: String, requirementID: String, detail: String)
    case streamMismatch(fixtureID: String, requirementID: String, path: String, detail: String)

    var errorDescription: String? {
        switch self {
        case let .violation(fixtureID, requirementID, detail):
            "fixture=\(fixtureID) requirement=\(requirementID) violation=\(detail)"
        case let .streamMismatch(fixtureID, requirementID, path, detail):
            "fixture=\(fixtureID) requirement=\(requirementID) stream=\(path) mismatch=\(detail)"
        }
    }
}

private func makeCorpusPerformance(_ fixture: PianoPerformanceCorpusFixture) throws -> CorpusPerformance {
    let parsed = try MusicXMLParser().parse(fileURL: fixture.url)
    let normalized = MusicXMLPianoGrandStaffNormalizer().normalize(score: parsed)
    let includedPartIDs = Set(normalized.notes.map(\.partID))
    let primaryPartID = normalized.logicalInstruments.first?.memberPartIDs.first
        ?? normalized.notes.first?.partID
        ?? "P1"
    let performedOrder = MusicXMLStructureExpander().expandStructureIfPossible(
        score: normalized,
        primaryPartID: primaryPartID,
        includedPartIDs: includedPartIDs
    )
    let plan = makeTestScorePerformancePlan(
        from: performedOrder.score,
        performanceTimingEnabled: true
    )
    let wordsSemantics = MusicXMLWordsSemanticsInterpreter().interpret(
        wordsEvents: performedOrder.score.wordsEvents,
        tempoEvents: performedOrder.score.tempoEvents
    )
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: performedOrder.score.tempoEvents + wordsSemantics.derivedTempoEvents,
        tempoRamps: wordsSemantics.derivedTempoRamps,
        partID: includedPartIDs.sorted().first
    )
    let steps = PracticeStepBuilder().buildSteps(from: plan).steps
    let guides = PianoHighlightGuideBuilderService().buildGuides(plan: plan)
    let timeline = AutoplayPerformanceTimeline.build(
        plan: plan,
        guideProjection: guides,
        stepProjection: steps,
        tempoMap: tempoMap,
        practiceHandMode: .both
    )
    return CorpusPerformance(
        fixture: fixture,
        plan: plan,
        tempoMap: tempoMap,
        steps: steps,
        guides: guides,
        timeline: timeline
    )
}

private func assertFullTimelineContract(_ performance: CorpusPerformance) throws {
    let fixture = performance.fixture
    let timeline = performance.timeline
    let transport = PerformanceTransportReducer().reduce(notes: performance.plan.noteEvents.map { note in
        PerformanceTransportReducer.Note(
            eventID: note.id,
            midiNote: note.midiNote,
            velocity: note.velocity,
            onTick: note.performedOnTick,
            offTick: note.performedOffTick
        )
    })
    let expectedNotes = transport.commands.map { command in
        let kind: ExpectedTimelineEventKind
        switch command.kind {
        case let .noteOn(velocity):
            kind = .noteOn(midi: command.midiNote, velocity: velocity)
        case .noteOff:
            kind = .noteOff(midi: command.midiNote)
        }
        return ExpectedTimelineEvent(
            sourceEventID: command.eventID.description,
            tick: command.tick,
            kind: kind
        )
    }
    let actualNotes = timeline.events.compactMap { event -> ExpectedTimelineEvent? in
        switch event.kind {
        case let .noteOn(midi, velocity):
            ExpectedTimelineEvent(sourceEventID: event.sourceEventID, tick: event.tick, kind: .noteOn(midi: midi, velocity: velocity))
        case let .noteOff(midi):
            ExpectedTimelineEvent(sourceEventID: event.sourceEventID, tick: event.tick, kind: .noteOff(midi: midi))
        case .pauseSeconds, .controlChange, .tempo, .advanceStep, .advanceGuide:
            nil
        }
    }
    try requirePerformance(actualNotes == expectedNotes, fixture: fixture, detail: "note IDs, on/off, velocity, or order changed")

    for (index, tempo) in performance.plan.tempoEvents.enumerated() {
        let sourceEventID = tempo.sourceDirectionID?.description
            ?? "tempo:\(tempo.performedOccurrenceIndex):\(tempo.tick):\(index)"
        try requirePerformance(
            timeline.events.contains { event in
                guard event.sourceEventID == sourceEventID, event.tick == tempo.tick,
                      case let .tempo(quarterBPM, endTick, endQuarterBPM) = event.kind
                else { return false }
                return quarterBPM == tempo.quarterBPM
                    && endTick == tempo.endTick
                    && endQuarterBPM == tempo.endQuarterBPM
            },
            fixture: fixture,
            detail: "missing tempo event \(sourceEventID)"
        )
    }
    for (index, controller) in performance.plan.controllerEvents.enumerated() {
        let sourceEventID = controller.sourceDirectionID?.description
            ?? "controller:\(controller.performedOccurrenceIndex):\(controller.tick):\(index)"
        try requirePerformance(
            timeline.events.contains { event in
                guard event.sourceEventID == sourceEventID, event.tick == controller.tick,
                      case let .controlChange(number, value) = event.kind
                else { return false }
                return number == controller.controllerNumber && value == controller.value
            },
            fixture: fixture,
            detail: "missing controller event \(sourceEventID)"
        )
    }
    for annotation in performance.plan.annotations where annotation.kind == .pause {
        try requirePerformance(
            timeline.events.contains { event in
                guard event.tick == annotation.tick, case .pauseSeconds = event.kind else { return false }
                return true
            },
            fixture: fixture,
            detail: "missing pause annotation at tick \(annotation.tick)"
        )
    }
    try requirePerformance(
        timeline.events.enumerated().allSatisfy { index, event in
            event.id == index && (index == 0 || timeline.events[index - 1].tick <= event.tick)
        },
        fixture: fixture,
        detail: "timeline event IDs or tick order are not canonical"
    )
}

private enum ExpectedTimelineEventKind: Equatable {
    case noteOn(midi: Int, velocity: UInt8)
    case noteOff(midi: Int)
}

private struct ExpectedTimelineEvent: Equatable {
    let sourceEventID: String?
    let tick: Int
    let kind: ExpectedTimelineEventKind
}

private func makeActiveRange(for performance: CorpusPerformance) throws -> PracticeActiveRange {
    let fixture = performance.fixture
    guard performance.steps.isEmpty == false else {
        throw CorpusPerformanceSnapshotError.violation(
            fixtureID: fixture.id,
            requirementID: requirementID(for: fixture),
            detail: "cannot create active range without practice steps"
        )
    }
    let lastTick = [
        performance.plan.noteEvents.map(\.performedOffTick).max() ?? 1,
        performance.plan.tempoEvents.map(\.tick).max() ?? 1,
        performance.plan.controllerEvents.map(\.tick).max() ?? 1,
        performance.plan.annotations.map(\.tick).max() ?? 1,
    ].max() ?? 1
    guard lastTick > 1 else {
        throw CorpusPerformanceSnapshotError.violation(
            fixtureID: fixture.id,
            requirementID: requirementID(for: fixture),
            detail: "fixture has no seekable performance interval"
        )
    }
    let resolver = PerformanceRangeStateResolver()
    let startTick = performance.steps
        .map(\.tick)
        .first { $0 > 0 && resolver.resolve(plan: performance.plan, at: $0, practiceHandMode: .both).approximations.isEmpty == false }
        ?? performance.steps.map(\.tick).first(where: { $0 > 0 })
        ?? max(1, lastTick / 2)
    let endTick = max(startTick + 1, lastTick)
    let stepIndices = performance.steps.indices.filter { index in
        performance.steps[index].tick >= startTick && performance.steps[index].tick < endTick
    }
    let firstStep = stepIndices.first ?? max(0, performance.steps.count - 1)
    let pastLastStep = (stepIndices.last ?? firstStep) + 1
    let span = MusicXMLMeasureSpan(
        partID: "P1",
        measureNumber: 1,
        sourceMeasureIndex: 0,
        sourceMeasureNumberToken: "P15",
        occurrenceIndex: 0,
        startTick: startTick,
        endTick: endTick
    )
    let passage = try #require(PracticePassage(start: span.occurrenceID, end: span.occurrenceID))
    return PracticeActiveRange(
        passage: passage,
        occurrenceRange: 0 ..< 1,
        stepRange: firstStep ..< pastLastStep,
        tickRange: startTick ..< endTick,
        measureSpans: [span]
    )
}

private func isHighRiskFixture(_ fixture: PianoPerformanceCorpusFixture) -> Bool {
    let highRiskTags: Set<String> = [
        "autoplay", "fermata", "held-note", "measure-identity", "pedal", "polyphony", "range-start",
        "repeat", "repeats", "repedal", "retrigger", "sustain-latched-note", "tempo", "unison",
    ]
    return highRiskTags.isDisjoint(with: fixture.semanticTags) == false
}

private func assertLoopClosesEveryScheduledNote(
    _ events: [PracticeSequencerMIDIEvent],
    fixture: PianoPerformanceCorpusFixture
) throws {
    for (index, event) in events.enumerated() {
        guard case .noteOn = event.kind, let sourceEventID = event.sourceEventID else { continue }
        try requirePerformance(
            events.dropFirst(index + 1).contains { later in
                guard later.sourceEventID == sourceEventID, case .noteOff = later.kind else { return false }
                return true
            },
            fixture: fixture,
            detail: "loop sequence left note \(sourceEventID) open"
        )
    }
}

private func requireSameEventStream(
    expected: String,
    actual: String,
    fixture: PianoPerformanceCorpusFixture,
    path: String
) throws {
    guard expected == actual else {
        throw CorpusPerformanceSnapshotError.streamMismatch(
            fixtureID: fixture.id,
            requirementID: requirementID(for: fixture),
            path: path,
            detail: firstSnapshotDifference(expected: expected, actual: actual)
        )
    }
}

private func requirePerformance(
    _ condition: @autoclosure () -> Bool,
    fixture: PianoPerformanceCorpusFixture,
    detail: String
) throws {
    guard condition() else {
        throw CorpusPerformanceSnapshotError.violation(
            fixtureID: fixture.id,
            requirementID: requirementID(for: fixture),
            detail: detail
        )
    }
}

private func requirementID(for fixture: PianoPerformanceCorpusFixture) -> String {
    "P15-CORPUS-PERFORMANCE-\(fixture.id)"
}

private func firstSnapshotDifference(expected: String, actual: String) -> String {
    let expectedLines = expected.split(separator: "\n", omittingEmptySubsequences: false)
    let actualLines = actual.split(separator: "\n", omittingEmptySubsequences: false)
    let count = max(expectedLines.count, actualLines.count)
    for index in 0 ..< count {
        let expectedLine = index < expectedLines.count ? expectedLines[index] : "<none>"
        let actualLine = index < actualLines.count ? actualLines[index] : "<none>"
        if expectedLine != actualLine {
            return "line=\(index) expected=\(expectedLine) actual=\(actualLine)"
        }
    }
    return "unknown"
}
