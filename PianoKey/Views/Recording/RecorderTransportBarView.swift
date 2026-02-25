import Observation
import SwiftUI

struct RecorderTransportBarView: View {
    @Bindable var viewModel: PianoKeyViewModel

    var body: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.startRecordingTake()
            } label: {
                Label("Rec", systemImage: "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!viewModel.canRecord)

            Button {
                viewModel.playSelectedTake()
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canPlay)

            Button {
                viewModel.stopTransport()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canStop)

            Spacer(minLength: 0)

            Text(modeText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(durationText)
                .font(.system(.body, design: .monospaced))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var modeText: String {
        switch viewModel.recorderMode {
        case .idle:
            return "Idle"
        case .recording:
            return "Recording"
        case .playing:
            return "Playing"
        }
    }

    private var durationText: String {
        let seconds = Int(viewModel.selectedTake?.durationSec ?? 0)
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

