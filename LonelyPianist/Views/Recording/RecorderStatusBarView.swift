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
            Text("Duration: \(durationText(for: take))")
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func durationText(for take: RecordingTake?) -> String {
        let duration = Int(take?.durationSec ?? 0)
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
