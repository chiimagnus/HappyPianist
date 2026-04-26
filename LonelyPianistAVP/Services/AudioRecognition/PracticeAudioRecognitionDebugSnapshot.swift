import Foundation

struct PracticeAudioRecognitionDebugSnapshot: Sendable, Equatable {
    enum PermissionState: String, Sendable, Equatable {
        case unknown
        case granted
        case denied
    }

    enum EngineState: String, Sendable, Equatable {
        case idle
        case starting
        case running
        case stopped
        case failed
    }

    let permissionState: PermissionState
    let engineState: EngineState
    let inputLevel: Double
    let expectedMIDINotes: [Int]
    let recentDetectedNotes: [DetectedNoteEvent]
    let matchProgress: String
    let handGate: Bool
    let suppress: Bool
    let generation: Int
    let lastDecisionReason: String

    static let empty = PracticeAudioRecognitionDebugSnapshot(
        permissionState: .unknown,
        engineState: .idle,
        inputLevel: 0,
        expectedMIDINotes: [],
        recentDetectedNotes: [],
        matchProgress: "",
        handGate: false,
        suppress: false,
        generation: 0,
        lastDecisionReason: ""
    )
}
