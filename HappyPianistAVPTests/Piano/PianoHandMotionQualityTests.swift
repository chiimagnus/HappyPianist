@testable import HappyPianistAVP
import Foundation
import HappyPianistTestFixtures
import MusicXML
@testable import Practice
import simd
import Testing

@Test
func handMotionCorpusMeetsCoverageTimingAndContactGates() throws {
    let corpus = try HandMotionCorpus.load()
    var contactErrors: [Float] = []
    var timingErrors: [TimeInterval] = []

    for fixture in corpus.cases {
        let preparedFixture = try fixture.makeInput()
        let input = preparedFixture.input
        let result = try PianoHandMotionClipBuilder().build(input: input)
        let expectedOccurrenceIDs = Set(input.contacts.contacts.map(\.occurrenceID))
        let coverage = Set(result.clips.flatMap(\.coverage).map(\.occurrenceID))
        #expect(result.rejectedOccurrenceIDs.isEmpty, "fixture=\(fixture.id)")
        #expect(coverage == expectedOccurrenceIDs, "fixture=\(fixture.id)")

        for (index, note) in fixture.notes.enumerated() {
            let occurrenceID = "\(fixture.id)-\(index)"
            let clip = try #require(result.clips.first { $0.hand == note.scoreHand }, "fixture=\(fixture.id)")
            let frame = try #require(
                clip.frames.min(by: {
                    abs($0.timeSeconds - note.onsetSeconds) < abs($1.timeSeconds - note.onsetSeconds)
                }),
                "fixture=\(fixture.id), occurrence=\(occurrenceID)"
            )
            timingErrors.append(abs(frame.timeSeconds - note.onsetSeconds))
            let joints = try #require(PianoDemonstrationHandRootPlanner.fingerJointPositions(
                finger: note.finger,
                hand: note.scoreHand,
                rootTransform: frame.rootTransform,
                jointRotations: frame.jointRotations
            ), "fixture=\(fixture.id), occurrence=\(occurrenceID)")
            let target = try #require(preparedFixture.contactPositionByMIDINote[note.midiNote])
            contactErrors.append(simd_distance(try #require(joints.last), target))
            #expect(frame.jointRotations.allSatisfy {
                abs(simd_length($0) - 1) < 0.000_1
            }, "fixture=\(fixture.id), occurrence=\(occurrenceID)")
        }
    }

    #expect(percentile95(contactErrors) <= 0.005, "P95 contact error exceeded 5 mm")
    #expect(percentile95(timingErrors) <= 0.05, "P95 timing error exceeded 50 ms")
    #expect((timingErrors.max() ?? 0) <= 0.1, "maximum timing error exceeded 100 ms")
}

private struct HandMotionCorpus: Decodable {
    let schemaVersion: Int
    let cases: [Case]

    struct Case: Decodable {
        let id: String
        let notes: [Note]

        struct PreparedFixture {
            let input: PianoHandMotionClipBuilder.Input
            let contactPositionByMIDINote: [Int: SIMD3<Float>]
        }

        func makeInput() throws -> PreparedFixture {
            let frame = try #require(KeyboardFrame(
                a0World: .zero,
                c8World: [1, 0, 0],
                planeHeight: 0
            ))
            let geometry = try #require(VirtualPianoKeyGeometryService().generateKeyboardGeometry(from: frame))
            let keyboardLayout = PianoHandMotionClipBuilder.KeyboardLayout(keyboardGeometry: geometry)
            let contactPositionByMIDINote = Dictionary(uniqueKeysWithValues: keyboardLayout.keys.map {
                ($0.midiNote, $0.contactPositionLocal)
            })
            let contacts = notes.enumerated().map { index, note in
                PianoKeyContactTimeline.Contact(
                    occurrenceID: "\(id)-\(index)",
                    midiNote: note.midiNote,
                    staff: note.scoreHand == .left ? 2 : 1,
                    handAssignment: .init(hand: note.scoreHand, provenance: .score),
                    fingerings: [],
                    velocity: 96,
                    guideID: nil,
                    stepIndex: nil,
                    carriedIn: false,
                    timing: .scheduled(
                        onsetSeconds: note.onsetSeconds,
                        releaseSeconds: note.onsetSeconds + 0.1
                    )
                )
            }
            return PreparedFixture(
                input: .init(
                    contacts: .init(contacts: contacts),
                    fingeringPlan: .init(results: notes.enumerated().map { index, note in
                        .init(
                            occurrenceID: "\(id)-\(index)",
                            resolution: .planned(hand: note.scoreHand, finger: note.finger, source: .planned)
                        )
                    }),
                    keyboardLayout: keyboardLayout,
                    scoreRevision: "hand-motion-corpus-v2"
                ),
                contactPositionByMIDINote: contactPositionByMIDINote
            )
        }
    }

    struct Note: Decodable {
        let midiNote: Int
        let hand: String
        let finger: Int
        let onsetSeconds: TimeInterval

        var scoreHand: ScoreHand {
            hand == "left" ? .left : .right
        }
    }

    static func load() throws -> Self {
        let url = HappyPianistTestFixtures.url(named: "HandMotionCorpus/manifest.json")
        let corpus = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard corpus.schemaVersion == 2 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Unsupported hand-motion corpus schema."
            ))
        }
        return corpus
    }
}

private func percentile95<T: BinaryFloatingPoint>(_ values: [T]) -> T {
    guard values.isEmpty == false else { return 0 }
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)]
}
