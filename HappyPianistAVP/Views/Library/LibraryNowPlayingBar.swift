import SwiftUI

@MainActor
struct LibraryNowPlayingBar: View {
    let title: String
    let subtitle: String
    let progress: Double
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let canSeek: Bool
    let canPerformPlaybackAction: Bool
    let playbackTitle: String
    let playbackSystemImage: String

    private let onPlayback: @MainActor @Sendable () -> Void
    private let onSeek: @MainActor @Sendable (Double) -> Void

    init(
        title: String,
        subtitle: String,
        progress: Double,
        currentTime: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool,
        canSeek: Bool,
        canPerformPlaybackAction: Bool,
        playbackTitle: String,
        playbackSystemImage: String,
        onPlayback: @escaping @MainActor @Sendable () -> Void,
        onSeek: @escaping @MainActor @Sendable (Double) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.currentTime = currentTime
        self.duration = duration
        self.isPlaying = isPlaying
        self.canSeek = canSeek
        self.canPerformPlaybackAction = canPerformPlaybackAction
        self.playbackTitle = playbackTitle
        self.playbackSystemImage = playbackSystemImage
        self.onPlayback = onPlayback
        self.onSeek = onSeek
    }

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: isPlaying ? "record.circle.fill" : "record.circle")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 180, maxWidth: 260, alignment: .leading)

            VStack(spacing: 5) {
                Slider(
                    value: Binding(
                        get: { clampedProgress },
                        set: onSeek
                    ),
                    in: 0 ... 1
                )
                .disabled(canSeek == false)
                .accessibilityLabel("播放进度")
                .accessibilityValue("\(Int(clampedProgress * 100))%")

                HStack {
                    Text(formattedTime(currentTime))
                    Spacer()
                    Text(formattedTime(duration))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .frame(maxWidth: 420)

            Button(playbackTitle, systemImage: playbackSystemImage, action: onPlayback)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .disabled(canPerformPlaybackAction == false)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("当前播放")
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private func formattedTime(_ time: TimeInterval) -> String {
        Duration.seconds(max(time, 0)).formatted(.time(pattern: .minuteSecond))
    }
}

#Preview("当前播放条") {
    LibraryNowPlayingBar(
        title: "Bohemian Rhapsody",
        subtitle: "Queen · arr. Phillip Keveren",
        progress: 0.38,
        currentTime: 134,
        duration: 354,
        isPlaying: true,
        canSeek: true,
        canPerformPlaybackAction: true,
        playbackTitle: "暂停",
        playbackSystemImage: "pause.fill",
        onPlayback: {},
        onSeek: { _ in }
    )
    .frame(width: 860)
    .padding()
}
