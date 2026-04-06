import Observation
import SwiftUI

struct DialogueControlView: View {
    @Bindable var viewModel: LonelyPianistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button(viewModel.dialogueStatus == .idle ? "Start Dialogue" : "Stop Dialogue") {
                    if viewModel.dialogueStatus == .idle {
                        viewModel.startDialogue()
                    } else {
                        viewModel.stopDialogue()
                    }
                }
                .keyboardShortcut(.defaultAction)

                Text(statusText)
                    .foregroundStyle(.secondary)

                if let latency = viewModel.dialogueLatencyMs, viewModel.dialogueStatus != .idle {
                    Text("latency \(latency)ms")
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Form {
                Picker("During AI playback", selection: $viewModel.dialoguePlaybackInterruptionBehavior) {
                    ForEach(DialoguePlaybackInterruptionBehavior.allCases) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }
            }
            .formStyle(.grouped)

            Text("Backend: ws://127.0.0.1:8765/ws")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(16)
    }

    private var statusText: String {
        switch viewModel.dialogueStatus {
        case .idle:
            return "Idle"
        case .listening:
            return "Listening"
        case .thinking:
            return "Thinking"
        case .playing:
            return "Playing"
        }
    }
}

