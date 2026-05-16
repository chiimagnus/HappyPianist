import SwiftUI

struct Step3AudioDebugOverlay: View {
    @Bindable var sessionViewModel: PracticeSessionViewModel
    let isAutoplayEnabled: Bool

    private var snapshot: PracticeAudioRecognitionDebugSnapshot {
        sessionViewModel.audioRecognitionDebugSnapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Audio", text: statusText)
            row("Mode", text: "\(snapshot.requestedDetectorMode.rawValue)->\(snapshot.activeDetectorMode.rawValue)")
            row("Fallback", text: snapshot.fallbackReason ?? "-")
            row("Input", text: String(format: "%.3f", snapshot.inputLevel))
            row("Expected", text: notesText(snapshot.expectedMIDINotes))
            row("Progress", text: snapshot.matchProgress.ifEmpty("-"))
            row(
                "Window",
                text: "\(snapshot.rollingWindowSize) / \(String(format: "%.1f", snapshot.processingDurationMs))ms"
            )
            row("Hand Gate", text: handGateText)
            row("Suppress", text: suppressText)
            row("Autoplay", text: isAutoplayEnabled ? "isolating" : "off")
            row("Decision", text: snapshot.lastDecisionReason.ifEmpty("-"))

            if snapshot.templateMatchResults.isEmpty == false {
                Divider()
                ForEach(Array(snapshot.templateMatchResults.prefix(4).enumerated()), id: \.offset) { _, result in
                    row(
                        "T\(result.midiNote)",
                        text: String(
                            format: "%@ c=%.2f h=%.2f t=%.2f d=%.2f",
                            result.role.rawValue,
                            result.confidence,
                            result.harmonicScore,
                            result.tonalRatio,
                            result.dominanceOverWrong
                        )
                    )
                }
            }

            if snapshot.recentDetectedNotes.isEmpty == false {
                Divider()
                ForEach(Array(snapshot.recentDetectedNotes.suffix(4).enumerated()), id: \.offset) { _, note in
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
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var statusText: String {
        switch sessionViewModel.audioRecognitionStatus {
            case .idle: "idle"
            case .requestingPermission: "requestingPermission"
            case .permissionDenied: "permissionDenied"
            case .running: "running"
            case let .engineFailed(reason): "engineFailed(\(reason))"
            case .stopped: "stopped"
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
        if remaining > 0 { return String(format: "on %.2fs", remaining) }
        return "off"
    }

    private func notesText(_ notes: [Int]) -> String {
        notes.isEmpty ? "-" : notes.map(String.init).joined(separator: ",")
    }

    private func row(_ title: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).foregroundStyle(.white.opacity(0.7)).frame(width: 72, alignment: .leading)
            Text(text).lineLimit(2).multilineTextAlignment(.leading)
        }
    }
}

private extension String {
    func ifEmpty(_ replacement: String) -> String {
        isEmpty ? replacement : self
    }
}
