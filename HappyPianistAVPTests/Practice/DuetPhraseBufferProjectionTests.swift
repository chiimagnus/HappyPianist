import Foundation
import HappyPianistTestFixtures
import Practice
@testable import HappyPianistAVP
import Testing

private struct CompanionProjectionFixture: Decodable {
    struct Case: Decodable {
        struct Event: Decodable {
            let type: String
            let time: Double
            let note: Int?
            let velocity: Int?
            let value: Int?
        }

        struct Expected: Decodable {
            let heldNotesCount: Int
            let sustainValue: Int
            let recentIOIMedianSeconds: Double?
            let recentNoteDensityPerSecond: Double
            let secondsSinceLastNoteOn: Double?
            let isAIPlaybackActive: Bool
            let userNoteOnSinceAIPlaybackStarted: Bool

            enum CodingKeys: String, CodingKey {
                case heldNotesCount = "held_notes_count"
                case sustainValue = "sustain_value"
                case recentIOIMedianSeconds = "recent_ioi_median_seconds"
                case recentNoteDensityPerSecond = "recent_note_density_per_second"
                case secondsSinceLastNoteOn = "seconds_since_last_note_on"
                case isAIPlaybackActive = "is_ai_playback_active"
                case userNoteOnSinceAIPlaybackStarted = "user_note_on_since_ai_playback_started"
            }
        }

        let id: String
        let events: [Event]
        let snapshotTime: Double
        let isAIPlaybackActive: Bool
        let userNoteOnSinceAIPlaybackStarted: Bool
        let expected: Expected

        enum CodingKeys: String, CodingKey {
            case id, events, expected
            case snapshotTime = "snapshot_time"
            case isAIPlaybackActive = "is_ai_playback_active"
            case userNoteOnSinceAIPlaybackStarted = "user_note_on_since_ai_playback_started"
        }
    }

    let projectionVersion: String
    let cases: [Case]

    enum CodingKeys: String, CodingKey {
        case projectionVersion = "projection_version"
        case cases
    }
}

private let projectionSource = PerformanceObservation.Source(
    kind: .midi1,
    id: "companion-qwen-projection-fixture",
    generation: 1
)

@Test
func qwenCompanionStateProjectionMatchesCanonicalFixture() throws {
    let url = HappyPianistTestFixtures.url(named: "CompanionQwenStateProjection.json")
    let fixture = try JSONDecoder().decode(
        CompanionProjectionFixture.self,
        from: Data(contentsOf: url)
    )
    #expect(fixture.projectionVersion == "duet-phrase-buffer-v1")

    for testCase in fixture.cases {
        var notes = DuetPhraseBuffer()
        var controls = DuetPhraseEventBuffer()
        var sustainValue = 0

        for event in testCase.events.sorted(by: { $0.time < $1.time }) {
            let phraseEvent: PerformanceObservationPhraseAdapter.PhraseEvent
            switch event.type {
            case "note_on":
                phraseEvent = projectionEvent(
                    .noteOn(
                        midi: try #require(event.note),
                        velocity: try #require(event.velocity)
                    ),
                    at: event.time
                )
                notes.record(phraseEvent, sustainIsDown: sustainValue >= 64)
            case "note_off":
                phraseEvent = projectionEvent(
                    .noteOff(midi: try #require(event.note)),
                    at: event.time
                )
                notes.record(phraseEvent, sustainIsDown: sustainValue >= 64)
            case "cc64":
                let nextValue = try #require(event.value)
                phraseEvent = projectionEvent(
                    .controlChange(controller: 64, value: nextValue),
                    at: event.time
                )
                let wasDown = sustainValue >= 64
                controls.record(phraseEvent)
                sustainValue = nextValue
                if wasDown, sustainValue < 64 {
                    notes.releaseSustainedNotes(timestampSeconds: event.time)
                }
            default:
                Issue.record("Unsupported fixture event type: \(event.type)")
                continue
            }
        }

        let noteSnapshot = notes.snapshot(
            nowTimestampSeconds: testCase.snapshotTime,
            lookbackSeconds: 4,
            maxPromptSeconds: 3
        )
        let ccSnapshot = controls.snapshot(
            nowTimestampSeconds: testCase.snapshotTime,
            lookbackSeconds: 4,
            maxPromptSeconds: 3
        )
        let actual = QwenCompanionState(
            heldNotesCount: noteSnapshot.heldNotes.count,
            sustainValue: ccSnapshot.sustainValue,
            recentIOIMedianSeconds: noteSnapshot.recentIOIMedianSeconds,
            recentNoteDensityPerSecond: noteSnapshot.recentNoteDensityPerSecond,
            secondsSinceLastNoteOn: noteSnapshot.lastNoteOnTimestampSeconds.map {
                max(0, testCase.snapshotTime - $0)
            },
            isAIPlaybackActive: testCase.isAIPlaybackActive,
            userNoteOnSinceAIPlaybackStarted: testCase.userNoteOnSinceAIPlaybackStarted
        )

        #expect(actual.heldNotesCount == testCase.expected.heldNotesCount, Comment(rawValue: testCase.id))
        #expect(actual.sustainValue == testCase.expected.sustainValue, Comment(rawValue: testCase.id))
        expectOptionalClose(actual.recentIOIMedianSeconds, testCase.expected.recentIOIMedianSeconds, id: testCase.id)
        #expect(abs(actual.recentNoteDensityPerSecond - testCase.expected.recentNoteDensityPerSecond) < 1e-9, Comment(rawValue: testCase.id))
        expectOptionalClose(actual.secondsSinceLastNoteOn, testCase.expected.secondsSinceLastNoteOn, id: testCase.id)
        #expect(actual.isAIPlaybackActive == testCase.expected.isAIPlaybackActive, Comment(rawValue: testCase.id))
        #expect(actual.userNoteOnSinceAIPlaybackStarted == testCase.expected.userNoteOnSinceAIPlaybackStarted, Comment(rawValue: testCase.id))
    }
}

private func projectionEvent(
    _ kind: PerformanceObservationPhraseAdapter.PhraseEvent.Kind,
    at timestamp: Double
) -> PerformanceObservationPhraseAdapter.PhraseEvent {
    .init(
        observationID: UUID(),
        source: projectionSource,
        timestamp: .init(seconds: timestamp),
        timingProvenance: .hostOnly,
        kind: kind
    )
}

private func expectOptionalClose(_ actual: Double?, _ expected: Double?, id: String) {
    switch (actual, expected) {
    case let (.some(actual), .some(expected)):
        #expect(abs(actual - expected) < 1e-9, Comment(rawValue: id))
    case (.none, .none):
        break
    default:
        Issue.record("Optional numeric mismatch for \(id): actual=\(String(describing: actual)) expected=\(String(describing: expected))")
    }
}
