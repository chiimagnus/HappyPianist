import Foundation

struct TargetedHarmonicDetectionFrame: Equatable, Sendable {
    let events: [DetectedNoteEvent]
    let templateMatchResults: [TemplateMatchResult]
    let processingDurationMs: Double
    let suppressing: Bool
    let fallbackReason: String?
    let activeDetectorMode: PracticeAudioRecognitionDetectorMode
    let rollingWindowSize: Int
}
