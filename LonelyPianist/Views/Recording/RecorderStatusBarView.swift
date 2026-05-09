import Observation
import SwiftUI

struct RecorderStatusBarView: View {
    @Bindable var viewModel: LonelyPianistViewModel

    var body: some View {
        let take = viewModel.displayedTake

        HStack(spacing: 14) {
            Text(viewModel.recorderStatusMessage)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text("Notes: \(take?.notes.count ?? 0)")

            Text(statusTimeText(for: take))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func statusTimeText(for take: RecordingTake?) -> String {
        let total = Int(take?.durationSec ?? 0)
        let current = Int(viewModel.playheadSec)
        return "\(modeText) \(format(seconds: current)) / \(format(seconds: total))"
    }

    private var modeText: String {
        switch viewModel.recorderMode {
            case .idle:
                "Idle"
            case .recording:
                "Recording"
            case .playing:
                "Playing"
        }
    }

    private func format(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        let remainder = max(0, seconds) % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}
