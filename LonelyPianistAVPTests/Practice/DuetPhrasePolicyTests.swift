import Foundation
import ImprovProtocol
@testable import LonelyPianistAVP
import Testing

@Test
func duetPhraseBufferSnapshotProjectsHeldNotesAndRecentStats() {
    var buffer = DuetPhraseBuffer()
    buffer.recordNoteOn(midi: 60, velocity: 80, timestampSeconds: 0.0)
    buffer.recordNoteOff(midi: 60, timestampSeconds: 0.4, sustainIsDown: false)
    buffer.recordNoteOn(midi: 64, velocity: 92, timestampSeconds: 0.6)

    let snapshot = buffer.snapshot(nowTimestampSeconds: 1.0, lookbackSeconds: 4.0, maxPromptSeconds: 3.0)

    #expect(snapshot.promptNotes.count == 2)
    #expect(snapshot.heldNoteMIDIs == [64])
    #expect(snapshot.lastUserEventTimestampSeconds == 0.6)
    #expect(snapshot.recentIOIMedianSeconds != nil)
    #expect(snapshot.recentNoteDensityPerSecond > 0)
    #expect(snapshot.activePitchCenter != nil)
}

@Test
func duetPhraseBufferKeepsReleasedNotesWhileSustainIsDown() {
    var buffer = DuetPhraseBuffer()
    buffer.recordNoteOn(midi: 60, velocity: 88, timestampSeconds: 0)
    buffer.recordNoteOff(midi: 60, timestampSeconds: 0.2, sustainIsDown: true)

    let sustained = buffer.snapshot(nowTimestampSeconds: 0.3, lookbackSeconds: 4, maxPromptSeconds: 3)
    #expect(sustained.heldNoteMIDIs == [60])

    buffer.releaseSustainedNotes(timestampSeconds: 0.4)
    let released = buffer.snapshot(nowTimestampSeconds: 0.5, lookbackSeconds: 4, maxPromptSeconds: 3)
    #expect(released.heldNoteMIDIs.isEmpty)
}

@Test
func duetPhrasePolicyBuildPromptEventsMergesCCAndNotesInTimeOrder() {
    var noteBuffer = DuetPhraseBuffer()
    noteBuffer.recordNoteOn(midi: 60, velocity: 90, timestampSeconds: 1.0)
    noteBuffer.recordNoteOff(midi: 60, timestampSeconds: 1.2, sustainIsDown: false)
    let noteSnapshot = noteBuffer.snapshot(nowTimestampSeconds: 1.5, lookbackSeconds: 4.0, maxPromptSeconds: 3.0)

    var ccBuffer = DuetPhraseEventBuffer()
    ccBuffer.recordControlChange(controller: 64, value: 127, timestampSeconds: 0.9)
    ccBuffer.recordControlChange(controller: 64, value: 0, timestampSeconds: 1.1)
    let ccSnapshot = ccBuffer.snapshot(nowTimestampSeconds: 1.5, lookbackSeconds: 4.0, maxPromptSeconds: 3.0)

    let events = DuetPhrasePolicy.buildPromptEvents(
        noteSnapshot: noteSnapshot,
        ccSnapshot: ccSnapshot,
        policy: .init(lookbackSeconds: 4.0, maxPromptSeconds: 3.0, requestWindowSeconds: 0.7, minRequestIntervalSeconds: 0.24, maxTokens: 40)
    )

    #expect(events.count >= 3)
    #expect(events.first?.type == .cc)
    #expect(events.contains { $0.type == .note && $0.note == 60 })
}

@Test
func duetPhrasePolicyShapeScheduleDropsHeldConflictsAndClipsHorizon() {
    var noteBuffer = DuetPhraseBuffer()
    noteBuffer.recordNoteOn(midi: 60, velocity: 88, timestampSeconds: 10.0)
    let snapshot = noteBuffer.snapshot(nowTimestampSeconds: 10.2, lookbackSeconds: 4.0, maxPromptSeconds: 3.0)

    let schedule = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 60, velocity: 100)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.20, kind: .noteOff(midi: 60)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.10, kind: .noteOn(midi: 67, velocity: 100)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.30, kind: .noteOff(midi: 67)),
        PracticeSequencerMIDIEvent(timeSeconds: 1.20, kind: .noteOn(midi: 72, velocity: 100)),
    ]

    let shaped = DuetPhrasePolicy.shapeSchedule(
        schedule,
        noteSnapshot: snapshot,
        controlMode: .support,
        horizonSeconds: 0.7
    )

    #expect(shaped.contains { if case let .noteOn(midi, _) = $0.kind { return midi == 67 } else { return false } })
    #expect(shaped.contains { if case let .noteOn(midi, _) = $0.kind { return midi == 60 } else { return false } } == false)
    #expect(shaped.contains { $0.timeSeconds > 0.7 } == false)
}

@Test
func duetPhrasePolicyShapeScheduleThinsSparseMode() {
    let snapshot = DuetPhraseBuffer.Snapshot(
        nowTimestampSeconds: 1.0,
        promptNotes: [],
        heldNotes: [],
        heldNoteMIDIs: [],
        lastUserEventTimestampSeconds: 0.9,
        lastNoteOnTimestampSeconds: 0.9,
        recentIOIMedianSeconds: 0.2,
        recentVelocityTrend: 0,
        recentNoteDensityPerSecond: 1.0,
        activePitchCenter: nil
    )

    let schedule = [
        PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 60, velocity: 100)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.30, kind: .noteOff(midi: 60)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.32, kind: .noteOn(midi: 64, velocity: 100)),
        PracticeSequencerMIDIEvent(timeSeconds: 0.52, kind: .noteOff(midi: 64)),
    ]

    let shaped = DuetPhrasePolicy.shapeSchedule(
        schedule,
        noteSnapshot: snapshot,
        controlMode: .sparse,
        horizonSeconds: 0.6
    )

    let noteOnMIDIs = shaped.compactMap { event -> Int? in
        if case let .noteOn(midi, _) = event.kind { return midi }
        return nil
    }
    #expect(noteOnMIDIs == [60])
}

@Test
func duetPhrasePolicyShapeScheduleSalvagesRiskyWindow() {
	let snapshot = DuetPhraseBuffer.Snapshot(
		nowTimestampSeconds: 1.0,
		promptNotes: [],
		heldNotes: [],
		heldNoteMIDIs: [],
		lastUserEventTimestampSeconds: 0.9,
		lastNoteOnTimestampSeconds: 0.9,
		recentIOIMedianSeconds: 0.18,
		recentVelocityTrend: 0,
		recentNoteDensityPerSecond: 2.0,
		activePitchCenter: nil
	)

	let schedule = [
		PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 72, velocity: 100)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.10, kind: .noteOff(midi: 72)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.12, kind: .noteOn(midi: 72, velocity: 100)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.22, kind: .noteOff(midi: 72)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.24, kind: .noteOn(midi: 72, velocity: 100)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.34, kind: .noteOff(midi: 72)),
	]

	let shaped = DuetPhrasePolicy.shapeSchedule(
		schedule,
		noteSnapshot: snapshot,
		controlMode: .support,
		horizonSeconds: 0.6
	)

	let noteOns = shaped.compactMap { event -> (Int, UInt8)? in
		if case let .noteOn(midi, velocity) = event.kind { return (midi, velocity) }
		return nil
	}
	#expect(noteOns.count == 2)
	#expect(noteOns.allSatisfy { $0.1 < 100 })
	let assessment = DuetPhrasePolicy.assessSchedule(shaped, noteSnapshot: snapshot, horizonSeconds: 0.6)
	#expect(assessment.band != .reject)
}

@Test
func duetPhrasePolicyShapeScheduleDropsRejectedWindow() {
	let snapshot = DuetPhraseBuffer.Snapshot(
		nowTimestampSeconds: 1.0,
		promptNotes: [],
		heldNotes: [],
		heldNoteMIDIs: [60],
		lastUserEventTimestampSeconds: 0.9,
		lastNoteOnTimestampSeconds: 0.9,
		recentIOIMedianSeconds: 0.1,
		recentVelocityTrend: 0,
		recentNoteDensityPerSecond: 3.0,
		activePitchCenter: 60
	)

	let schedule = [
		PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 61, velocity: 100)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.03, kind: .noteOn(midi: 62, velocity: 100)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.06, kind: .noteOn(midi: 63, velocity: 100)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.09, kind: .noteOn(midi: 64, velocity: 100)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.12, kind: .noteOn(midi: 65, velocity: 100)),
	]

	let shaped = DuetPhrasePolicy.shapeSchedule(
		schedule,
		noteSnapshot: snapshot,
		controlMode: .support,
		horizonSeconds: 0.6
	)

	#expect(shaped.isEmpty)
}

@Test
func duetPhrasePolicyAssessScheduleAcceptsSupportiveWindow() {
	let snapshot = DuetPhraseBuffer.Snapshot(
		nowTimestampSeconds: 1.0,
		promptNotes: [],
		heldNotes: [],
		heldNoteMIDIs: [48],
		lastUserEventTimestampSeconds: 0.9,
		lastNoteOnTimestampSeconds: 0.9,
		recentIOIMedianSeconds: 0.25,
		recentVelocityTrend: 0,
		recentNoteDensityPerSecond: 1.0,
		activePitchCenter: 55
	)

	let schedule = [
		PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 64, velocity: 96)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.20, kind: .noteOff(midi: 64)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.24, kind: .noteOn(midi: 67, velocity: 92)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.46, kind: .noteOff(midi: 67)),
	]

	let assessment = DuetPhrasePolicy.assessSchedule(schedule, noteSnapshot: snapshot, horizonSeconds: 0.7)
	#expect(assessment.band == .acceptable)
	#expect(assessment.reasons.isEmpty)
	#expect(assessment.score >= 80)
}

@Test
func duetPhrasePolicyAssessScheduleRejectsDensityOverload() {
	let snapshot = DuetPhraseBuffer.Snapshot(
		nowTimestampSeconds: 1.0,
		promptNotes: [],
		heldNotes: [],
		heldNoteMIDIs: [],
		lastUserEventTimestampSeconds: 0.9,
		lastNoteOnTimestampSeconds: 0.9,
		recentIOIMedianSeconds: 0.08,
		recentVelocityTrend: 0,
		recentNoteDensityPerSecond: 4.0,
		activePitchCenter: nil
	)

	let schedule = [
		PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 60, velocity: 90)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.03, kind: .noteOn(midi: 62, velocity: 90)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.06, kind: .noteOn(midi: 64, velocity: 90)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.09, kind: .noteOn(midi: 65, velocity: 90)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.12, kind: .noteOn(midi: 67, velocity: 90)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.15, kind: .noteOn(midi: 69, velocity: 90)),
	]

	let assessment = DuetPhrasePolicy.assessSchedule(schedule, noteSnapshot: snapshot, horizonSeconds: 0.6)
	#expect(assessment.band == .reject)
	#expect(assessment.reasons.contains(.densityOverload))
}

@Test
func duetPhrasePolicyRejectsDenseSupportWindowBeforeClosingOpenNotes() {
    let snapshot = DuetPhraseBuffer.Snapshot(
        nowTimestampSeconds: 1,
        promptNotes: [],
        heldNotes: [],
        heldNoteMIDIs: [],
        lastUserEventTimestampSeconds: 0.9,
        lastNoteOnTimestampSeconds: 0.9,
        recentIOIMedianSeconds: 0.08,
        recentVelocityTrend: 0,
        recentNoteDensityPerSecond: 4,
        activePitchCenter: nil
    )
    let schedule = [60, 62, 64, 65, 67, 69].enumerated().map { index, midi in
        PracticeSequencerMIDIEvent(timeSeconds: Double(index) * 0.03, kind: .noteOn(midi: midi, velocity: 90))
    } + [
        PracticeSequencerMIDIEvent(timeSeconds: 0.7, kind: .controlChange(controller: 64, value: 0)),
    ]

    let shaped = DuetPhrasePolicy.shapeSchedule(
        schedule,
        noteSnapshot: snapshot,
        controlMode: .support,
        horizonSeconds: 0.7
    )
    #expect(shaped.isEmpty)
}

@Test
func duetPhrasePolicyAssessScheduleRejectsExcessiveRepetition() {
	let snapshot = DuetPhraseBuffer.Snapshot(
		nowTimestampSeconds: 1.0,
		promptNotes: [],
		heldNotes: [],
		heldNoteMIDIs: [],
		lastUserEventTimestampSeconds: 0.9,
		lastNoteOnTimestampSeconds: 0.9,
		recentIOIMedianSeconds: 0.12,
		recentVelocityTrend: 0,
		recentNoteDensityPerSecond: 2.0,
		activePitchCenter: nil
	)

	let schedule = [
		PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 72, velocity: 90)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.10, kind: .noteOff(midi: 72)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.12, kind: .noteOn(midi: 72, velocity: 90)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.22, kind: .noteOff(midi: 72)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.24, kind: .noteOn(midi: 72, velocity: 90)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.34, kind: .noteOff(midi: 72)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.36, kind: .noteOn(midi: 72, velocity: 90)),
	]

	let assessment = DuetPhrasePolicy.assessSchedule(schedule, noteSnapshot: snapshot, horizonSeconds: 0.6)
	#expect(assessment.band == .reject)
	#expect(assessment.reasons.contains(.excessiveRepetition))
}

@Test
func duetPhrasePolicyAssessScheduleRejectsExtremeLeap() {
	let snapshot = DuetPhraseBuffer.Snapshot(
		nowTimestampSeconds: 1.0,
		promptNotes: [],
		heldNotes: [],
		heldNoteMIDIs: [],
		lastUserEventTimestampSeconds: 0.9,
		lastNoteOnTimestampSeconds: 0.9,
		recentIOIMedianSeconds: 0.2,
		recentVelocityTrend: 0,
		recentNoteDensityPerSecond: 1.0,
		activePitchCenter: nil
	)

	let schedule = [
		PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 48, velocity: 90)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.10, kind: .noteOff(midi: 48)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.20, kind: .noteOn(midi: 76, velocity: 90)),
	]

	let assessment = DuetPhrasePolicy.assessSchedule(schedule, noteSnapshot: snapshot, horizonSeconds: 0.7)
	#expect(assessment.band == .reject)
	#expect(assessment.reasons.contains(.extremeLeap))
}

@Test
func duetPhrasePolicyDoesNotTreatSimultaneousChordAsExtremeLeap() {
    let snapshot = DuetPhraseBuffer.Snapshot(
        nowTimestampSeconds: 1,
        promptNotes: [],
        heldNotes: [],
        heldNoteMIDIs: [],
        lastUserEventTimestampSeconds: 0.9,
        lastNoteOnTimestampSeconds: 0.9,
        recentIOIMedianSeconds: 0.2,
        recentVelocityTrend: 0,
        recentNoteDensityPerSecond: 1,
        activePitchCenter: nil
    )
    let assessment = DuetPhrasePolicy.assessSchedule(
        [
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 48, velocity: 90)),
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 76, velocity: 90)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.4, kind: .noteOff(midi: 48)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.4, kind: .noteOff(midi: 76)),
        ],
        noteSnapshot: snapshot,
        horizonSeconds: 0.7
    )
    #expect(assessment.reasons.contains(.extremeLeap) == false)
}

@Test
func duetPhrasePolicyAssessScheduleRejectsFragmentedWindow() {
	let snapshot = DuetPhraseBuffer.Snapshot(
		nowTimestampSeconds: 1.0,
		promptNotes: [],
		heldNotes: [],
		heldNoteMIDIs: [],
		lastUserEventTimestampSeconds: 0.9,
		lastNoteOnTimestampSeconds: 0.9,
		recentIOIMedianSeconds: 0.2,
		recentVelocityTrend: 0,
		recentNoteDensityPerSecond: 1.0,
		activePitchCenter: nil
	)

	let schedule = [
		PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 60, velocity: 80)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.03, kind: .noteOff(midi: 60)),
	]

	let assessment = DuetPhrasePolicy.assessSchedule(schedule, noteSnapshot: snapshot, horizonSeconds: 0.6)
	#expect(assessment.band == .reject)
	#expect(assessment.reasons.contains(.fragmentedWindow))
}

@Test
func duetPhrasePolicyAssessScheduleFlagsRegisterCollision() {
	let snapshot = DuetPhraseBuffer.Snapshot(
		nowTimestampSeconds: 1.0,
		promptNotes: [],
		heldNotes: [],
		heldNoteMIDIs: [60],
		lastUserEventTimestampSeconds: 0.9,
		lastNoteOnTimestampSeconds: 0.9,
		recentIOIMedianSeconds: 0.2,
		recentVelocityTrend: 0,
		recentNoteDensityPerSecond: 1.0,
		activePitchCenter: 60
	)

	let schedule = [
		PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 61, velocity: 84)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.18, kind: .noteOff(midi: 61)),
		PracticeSequencerMIDIEvent(timeSeconds: 0.22, kind: .noteOn(midi: 62, velocity: 82)),
	]

	let assessment = DuetPhrasePolicy.assessSchedule(schedule, noteSnapshot: snapshot, horizonSeconds: 0.7)
	#expect(assessment.band == .reject)
	#expect(assessment.reasons.contains(.registerCollision))
}
