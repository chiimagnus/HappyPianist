import Foundation
@testable import HappyPianistAVP

enum DuetQualityRegressionFixtures {
    struct Fixture {
        let name: String
        let noteSnapshot: DuetPhraseBuffer.Snapshot
        let rawSchedule: [PracticeSequencerMIDIEvent]
        let horizonSeconds: TimeInterval
        let expectedBand: DuetPhrasePolicy.QualityAssessment.Band
    }

    struct RubricFixture {
        let name: String
        let response: [PracticeSequencerMIDIEvent]
        let context: ImprovQualityRubric.PhraseContext
        let expectedBand: ImprovQualityRubric.Band
        let expectedReason: ImprovQualityRubric.Reason?
        let expectedCadenceEvidence: ImprovQualityRubric.Evidence?
        let voicePairs: [ImprovQualityRubric.VoicePair]

        init(
            name: String,
            response: [PracticeSequencerMIDIEvent],
            context: ImprovQualityRubric.PhraseContext,
            expectedBand: ImprovQualityRubric.Band,
            expectedReason: ImprovQualityRubric.Reason?,
            expectedCadenceEvidence: ImprovQualityRubric.Evidence?,
            voicePairs: [ImprovQualityRubric.VoicePair] = []
        ) {
            self.name = name
            self.response = response
            self.context = context
            self.expectedBand = expectedBand
            self.expectedReason = expectedReason
            self.expectedCadenceEvidence = expectedCadenceEvidence
            self.voicePairs = voicePairs
        }
    }

    struct BackendQualityCorpus {
        enum Response {
            case generatedRule
            case coreMLEventIDs([Int])
            case networkFakeEvents([ImprovEvent])
        }

        let provider: ImprovBackendKind
        let seed: UInt64
        let promptNotes: [ImprovDialogueNote]
        let parameters: ImprovGenerateParams
        let response: Response
        let expectedBand: ImprovQualityRubric.Band
    }

    static let acceptableSupport = Fixture(
        name: "acceptableSupport",
        noteSnapshot: .init(
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
        ),
        rawSchedule: [
            PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 64, velocity: 96)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.20, kind: .noteOff(midi: 64)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.24, kind: .noteOn(midi: 67, velocity: 92)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.46, kind: .noteOff(midi: 67)),
        ],
        horizonSeconds: 0.7,
        expectedBand: .acceptable
    )

    static let registerClash = Fixture(
        name: "registerClash",
        noteSnapshot: .init(
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
        ),
        rawSchedule: [
            PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 61, velocity: 84)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.18, kind: .noteOff(midi: 61)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.22, kind: .noteOn(midi: 62, velocity: 82)),
        ],
        horizonSeconds: 0.7,
        expectedBand: .reject
    )

    static let denseBurst = Fixture(
        name: "denseBurst",
        noteSnapshot: .init(
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
        ),
        rawSchedule: [
            PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 60, velocity: 90)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.03, kind: .noteOn(midi: 62, velocity: 90)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.06, kind: .noteOn(midi: 64, velocity: 90)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.09, kind: .noteOn(midi: 65, velocity: 90)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.12, kind: .noteOn(midi: 67, velocity: 90)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.15, kind: .noteOn(midi: 69, velocity: 90)),
        ],
        horizonSeconds: 0.6,
        expectedBand: .reject
    )

    static let fragmentedHint = Fixture(
        name: "fragmentedHint",
        noteSnapshot: .init(
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
        ),
        rawSchedule: [
            PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 60, velocity: 80)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.03, kind: .noteOff(midi: 60)),
        ],
        horizonSeconds: 0.6,
        expectedBand: .reject
    )

    static let riskyRepetition = Fixture(
        name: "riskyRepetition",
        noteSnapshot: .init(
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
        ),
        rawSchedule: [
            PracticeSequencerMIDIEvent(timeSeconds: 0.00, kind: .noteOn(midi: 72, velocity: 100)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.10, kind: .noteOff(midi: 72)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.12, kind: .noteOn(midi: 72, velocity: 100)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.22, kind: .noteOff(midi: 72)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.24, kind: .noteOn(midi: 72, velocity: 100)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.34, kind: .noteOff(midi: 72)),
        ],
        horizonSeconds: 0.6,
        expectedBand: .risky
    )

    static let all: [Fixture] = [acceptableSupport, registerClash, denseBurst, fragmentedHint, riskyRepetition]

    static let shortPhrase = RubricFixture(
        name: "shortPhrase",
        response: [
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 60, velocity: 88)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 60)),
        ],
        context: .init(
            allowedPitchClasses: [0],
            cadencePitchClasses: [0]
        ),
        expectedBand: .acceptable,
        expectedReason: nil,
        expectedCadenceEvidence: .notObserved
    )

    static let denseChord = RubricFixture(
        name: "denseChord",
        response: [48, 52, 55, 60, 64].flatMap { midi in
            [
                PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: midi, velocity: 88)),
                PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: midi)),
            ]
        },
        context: .init(),
        expectedBand: .reject,
        expectedReason: .densityOverload,
        expectedCadenceEvidence: nil
    )

    static let crossRegisterLeap = RubricFixture(
        name: "crossRegisterLeap",
        response: [
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 48, velocity: 88)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 48)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOn(midi: 84, velocity: 88)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.4, kind: .noteOff(midi: 84)),
        ],
        context: .init(
            allowedPitchClasses: Set(0 ..< 12),
            cadencePitchClasses: [0]
        ),
        expectedBand: .reject,
        expectedReason: .voiceCrossing,
        expectedCadenceEvidence: nil,
        voicePairs: [.init(bass: 72, melody: 60)]
    )

    static let harmonicMismatch = RubricFixture(
        name: "harmonicMismatch",
        response: [
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 61, velocity: 88)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 61)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.25, kind: .noteOn(midi: 65, velocity: 88)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.4, kind: .noteOff(midi: 65)),
        ],
        context: .init(
            allowedPitchClasses: [0, 4, 7],
            cadencePitchClasses: [5]
        ),
        expectedBand: .reject,
        expectedReason: .harmonicMismatch,
        expectedCadenceEvidence: nil
    )

    static let noTermination = RubricFixture(
        name: "noTermination",
        response: [
            PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 60, velocity: 88)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.1, kind: .noteOff(midi: 60)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.25, kind: .noteOn(midi: 61, velocity: 88)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.4, kind: .noteOff(midi: 61)),
        ],
        context: .init(
            allowedPitchClasses: Set(0 ..< 12),
            cadencePitchClasses: [0, 4, 7]
        ),
        expectedBand: .reject,
        expectedReason: .missingCadence,
        expectedCadenceEvidence: nil
    )

    static let rubricAll = [shortPhrase, denseChord, crossRegisterLeap, harmonicMismatch, noTermination]

    static let ruleQualityCorpus = BackendQualityCorpus(
        provider: .localRule,
        seed: 1_234,
        promptNotes: [
            ImprovDialogueNote(note: 60, velocity: 92, time: 0, duration: 0.22),
            ImprovDialogueNote(note: 62, velocity: 92, time: 0.25, duration: 0.18),
            ImprovDialogueNote(note: 64, velocity: 92, time: 0.5, duration: 0.2),
            ImprovDialogueNote(note: 65, velocity: 92, time: 0.75, duration: 0.2),
            ImprovDialogueNote(note: 67, velocity: 92, time: 1, duration: 0.2),
            ImprovDialogueNote(note: 69, velocity: 92, time: 1.25, duration: 0.22),
            ImprovDialogueNote(note: 71, velocity: 92, time: 1.5, duration: 0.18),
            ImprovDialogueNote(note: 72, velocity: 92, time: 1.75, duration: 0.25),
        ],
        parameters: .init(topP: 0.95, maxTokens: 256, strategy: "deterministic", seed: 1_234),
        response: .generatedRule,
        expectedBand: .risky
    )

    static let coreMLQualityCorpus = BackendQualityCorpus(
        provider: .localCoreMLDuet,
        seed: 7,
        promptNotes: [
            ImprovDialogueNote(note: 60, velocity: 80, time: 0, duration: 0.5),
        ],
        parameters: .init(topP: 0.95, maxTokens: 128, strategy: "model", seed: 7),
        response: .coreMLEventIDs([375, 60, 64, 67, 330, 188, 192, 195]),
        expectedBand: .acceptable
    )

    static let networkFakeQualityCorpus = BackendQualityCorpus(
        provider: .networkBonjourHTTPAriaV2,
        seed: 99,
        promptNotes: [
            ImprovDialogueNote(note: 60, velocity: 90, time: 0, duration: 0.2),
        ],
        parameters: .init(topP: 0.9, maxTokens: 64, strategy: "network", seed: 99),
        response: .networkFakeEvents([
            .cc(controller: 64, value: 127, time: 0),
            .note(note: 67, velocity: 88, time: 0, duration: 0.2),
            .note(note: 71, velocity: 84, time: 0.24, duration: 0.2),
        ]),
        expectedBand: .acceptable
    )

    static let backendQualityCorpus = [ruleQualityCorpus, coreMLQualityCorpus, networkFakeQualityCorpus]
}
