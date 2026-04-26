import Foundation

enum PracticeAudioRecognitionStatus: Equatable {
    case idle
    case requestingPermission
    case permissionDenied
    case running
    case engineFailed(reason: String)
    case stopped
}
