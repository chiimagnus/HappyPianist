import Foundation

nonisolated struct PracticeAudioRecognitionDebugSnapshot: Equatable, Sendable {
    enum PermissionState: String, Equatable {
        case unknown
        case granted
        case denied
    }

    enum EngineState: String, Equatable {
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
    let requestedDetectorMode: PracticeAudioRecognitionDetectorMode
    let activeDetectorMode: PracticeAudioRecognitionDetectorMode
    let fallbackReason: String?
    let rollingWindowSize: Int
    let processingDurationMs: Double
    let templateMatchResults: [TemplateMatchResult]

    init(
        permissionState: PermissionState,
        engineState: EngineState,
        inputLevel: Double,
        expectedMIDINotes: [Int],
        recentDetectedNotes: [DetectedNoteEvent],
        matchProgress: String,
        handGate: Bool,
        suppress: Bool,
        generation: Int,
        lastDecisionReason: String,
        requestedDetectorMode: PracticeAudioRecognitionDetectorMode = .harmonicTemplate,
        activeDetectorMode: PracticeAudioRecognitionDetectorMode = .harmonicTemplate,
        fallbackReason: String? = nil,
        rollingWindowSize: Int = 0,
        processingDurationMs: Double = 0,
        templateMatchResults: [TemplateMatchResult] = []
    ) {
        self.permissionState = permissionState
        self.engineState = engineState
        self.inputLevel = inputLevel
        self.expectedMIDINotes = expectedMIDINotes
        self.recentDetectedNotes = recentDetectedNotes
        self.matchProgress = matchProgress
        self.handGate = handGate
        self.suppress = suppress
        self.generation = generation
        self.lastDecisionReason = lastDecisionReason
        self.requestedDetectorMode = requestedDetectorMode
        self.activeDetectorMode = activeDetectorMode
        self.fallbackReason = fallbackReason
        self.rollingWindowSize = rollingWindowSize
        self.processingDurationMs = processingDurationMs
        self.templateMatchResults = templateMatchResults
    }

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
