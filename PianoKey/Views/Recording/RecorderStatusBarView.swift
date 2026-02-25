import Observation
import SwiftUI

struct RecorderStatusBarView: View {
    @Bindable var viewModel: PianoKeyViewModel

    var body: some View {
        HStack(spacing: 14) {
            Text(viewModel.recorderStatusMessage)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text("Notes: \(viewModel.selectedTake?.notes.count ?? 0)")
            Text("Duration: \(durationText)")
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var durationText: String {
        let duration = Int(viewModel.selectedTake?.durationSec ?? 0)
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

