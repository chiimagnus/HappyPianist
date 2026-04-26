import SwiftUI

struct Step3AudioDebugOverlay: View {
    @Bindable var sessionViewModel: PracticeSessionViewModel
    let isAutoplayEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Audio", text: statusText)
            row("Input", text: String(format: "%.3f", sessionViewModel.audioRecognitionDebugSnapshot.inputLevel))
            row("Expected", text: notesText(sessionViewModel.audioRecognitionDebugSnapshot.expectedMIDINotes))
            row("Progress", text: sessionViewModel.audioRecognitionDebugSnapshot.matchProgress.ifEmpty("-"))
            row("Hand Gate", text: handGateText)
            row("Suppress", text: suppressText)
            row("Autoplay", text: isAutoplayEnabled ? "isolating" : "off")
            row("Decision", text: sessionViewModel.audioRecognitionDebugSnapshot.lastDecisionReason.ifEmpty("-"))

            if sessionViewModel.audioRecognitionDebugSnapshot.recentDetectedNotes.isEmpty == false {
                Divider()
                ForEach(
                    Array(sessionViewModel.audioRecognitionDebugSnapshot.recentDetectedNotes.suffix(4).enumerated()),
                    id: \.offset
                ) { _, note in
                    row(
                        "N\(note.midiNote)",
                        text: String(
                            format: "c=%.2f o=%.2f %@ g=%d %@",
                            note.confidence,
                            note.onsetScore,
                            note.isOnset ? "on" : "sustain",
                            note.generation,
                            "\(note.source)"
                        )
                    )
                }
            }
        }
        .font(.caption2.monospaced())
        .padding(10)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .foregroundStyle(.white)
        .frame(maxWidth: 340, alignment: .leading)
    }

    private var statusText: String {
        switch sessionViewModel.audioRecognitionStatus {
            case .idle:
                "idle"
            case .requestingPermission:
                "requestingPermission"
            case .permissionDenied:
                "permissionDenied"
            case .running:
                "running"
            case let .engineFailed(reason):
                "engineFailed(\(reason))"
            case .stopped:
                "stopped"
        }
    }

    private var handGateText: String {
        let gate = sessionViewModel.handGateState
        if gate.exactPressedNotes.isEmpty == false {
            return "exact \(notesText(Array(gate.exactPressedNotes).sorted())) boost=\(String(format: "%.2f", gate.confidenceBoost))"
        }
        return "\(gate.isNearKeyboard ? "near" : "far")/\(gate.hasDownwardMotion ? "down" : "flat") boost=\(String(format: "%.2f", gate.confidenceBoost))"
    }

    private var suppressText: String {
        let remaining = sessionViewModel.audioRecognitionSuppressRemainingSeconds
        if remaining > 0 {
            return String(format: "on %.2fs", remaining)
        }
        return "off"
    }

    private func notesText(_ notes: [Int]) -> String {
        notes.isEmpty ? "-" : notes.map(String.init).joined(separator: ",")
    }

    private func row(_ title: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 64, alignment: .leading)
            Text(text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}

private extension String {
    func ifEmpty(_ replacement: String) -> String {
        isEmpty ? replacement : self
    }
}
