import SwiftUI

struct LibraryTrackInfoView: View {
    let presentation: SongLibraryTrackPresentation
    let progress: Double
    let currentTime: TimeInterval
    let duration: TimeInterval
    let canSeek: Bool
    let onSeek: (Double) -> Void

    @State private var progressBarWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(presentation.title)
                .font(.system(.largeTitle, design: .serif))
                .bold()
                .foregroundStyle(LibraryDesignTokens.text)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(presentation.subtitle)
                .font(.subheadline)
                .foregroundStyle(LibraryDesignTokens.secondaryText)
                .lineLimit(1)

            VStack(spacing: 7) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LibraryDesignTokens.line)

                    Capsule()
                        .fill(LibraryDesignTokens.text)
                        .frame(width: progressBarWidth * min(max(progress, 0), 1))
                }
                .frame(height: 5)
                .contentShape(.rect)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
                    progressBarWidth = width
                }
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            guard canSeek, progressBarWidth > 0 else { return }
                            onSeek(min(max(value.location.x / progressBarWidth, 0), 1))
                        }
                )
                .accessibilityLabel("播放进度")
                .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100))%")
                .accessibilityAdjustableAction { direction in
                    guard canSeek else { return }
                    let currentProgress = min(max(progress, 0), 1)
                    switch direction {
                    case .increment:
                        onSeek(min(currentProgress + 0.05, 1))
                    case .decrement:
                        onSeek(max(currentProgress - 0.05, 0))
                    @unknown default:
                        break
                    }
                }

                HStack {
                    Text(Self.formattedTime(currentTime))
                    Spacer()
                    Text(Self.formattedTime(duration))
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(LibraryDesignTokens.faintText)
            }
            .frame(maxWidth: 340)
            .padding(.top, 9)
        }
    }

    private static func formattedTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "0:00" }
        let totalSeconds = Int(time.rounded(.down))
        let seconds = totalSeconds % 60
        let secondsText = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        return "\(totalSeconds / 60):\(secondsText)"
    }
}
