import Foundation

struct MIDIDiagnosticsConfiguration: Equatable, Sendable {
    var isPerNoteInfoLoggingEnabled: Bool = false
    var isPerNoteDebugLoggingEnabled: Bool = false

    static func live(userDefaults: UserDefaults = .standard) -> MIDIDiagnosticsConfiguration {
        MIDIDiagnosticsConfiguration(
            isPerNoteInfoLoggingEnabled: userDefaults.bool(forKey: Keys.perNoteInfoLoggingEnabled),
            isPerNoteDebugLoggingEnabled: userDefaults.bool(forKey: Keys.perNoteDebugLoggingEnabled)
        )
    }

    private enum Keys {
        static let perNoteInfoLoggingEnabled = "midiDiagnostics.isPerNoteInfoLoggingEnabled"
        static let perNoteDebugLoggingEnabled = "midiDiagnostics.isPerNoteDebugLoggingEnabled"
    }
}
