import SwiftUI

struct TakeNowPlayingBarView: View {
    @Bindable var playbackViewModel: TakePlaybackViewModel
    let isRecording: Bool
    let totalDuration: TimeInterval
    let presentationViewModel: any TakeLibraryPresentationViewModelProtocol
    let onTogglePlayback: () -> Void
    let onStopPlayback: () -> Void
    let onCommitScrubbing: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(
                playbackViewModel.isPlaying ? "暂停回放" : "继续回放",
                systemImage: playbackViewModel.isPlaying ? "pause.fill" : "play.fill",
                action: onTogglePlayback
            )
            .font(.title3)
            .labelStyle(.iconOnly)
            .buttonBorderShape(.roundedRectangle)
            .hoverEffect()
            .disabled(playbackViewModel.currentTakeID == nil || isRecording)

            Button("停止回放", systemImage: "stop.fill", action: onStopPlayback)
                .font(.title3)
                .labelStyle(.iconOnly)
                .buttonBorderShape(.roundedRectangle)
                .hoverEffect()
                .disabled(playbackViewModel.currentTakeID == nil || isRecording)

            Slider(value: $playbackViewModel.scrubPositionSeconds, in: 0 ... max(0.001, totalDuration)) { editing in
                if editing {
                    playbackViewModel.beginScrubbing()
                } else {
                    onCommitScrubbing()
                }
            }
            .disabled(playbackViewModel.currentTakeID == nil || isRecording)

            Text(presentationViewModel.formattedDuration(playbackViewModel.displayedPositionSeconds))
                .monospacedDigit()
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 45, alignment: .trailing)

            Text("/ \(presentationViewModel.formattedDuration(totalDuration))")
                .monospacedDigit()
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 45, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
