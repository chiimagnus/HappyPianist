import Foundation

struct MIDIDiagnosticsConfiguration: Equatable, Sendable {
    var isPerNoteInfoLoggingEnabled: Bool = false

    static func live(userDefaults: UserDefaults = .standard) -> MIDIDiagnosticsConfiguration {
        MIDIDiagnosticsConfiguration(
            isPerNoteInfoLoggingEnabled: userDefaults.bool(forKey: Keys.perNoteInfoLoggingEnabled)
        )
    }

    private enum Keys {
        static let perNoteInfoLoggingEnabled = "midiDiagnostics.isPerNoteInfoLoggingEnabled"
    }
}

