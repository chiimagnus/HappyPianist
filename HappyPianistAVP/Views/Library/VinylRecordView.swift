import SwiftUI

struct VinylRecordView: View {
    let labelColor: Color
    let isPlaying: Bool
    let reduceMotion: Bool

    @State private var accumulatedRotationTime: TimeInterval = 0
    @State private var rotationStartedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: rotationStartedAt == nil)) { context in
            let activeElapsed = rotationStartedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
            let elapsed = accumulatedRotationTime + activeElapsed
            let angle = reduceMotion ? 0 : elapsed.truncatingRemainder(dividingBy: 14) / 14 * 360

            ZStack {
                Circle()
                    .fill(Color(red: 14 / 255, green: 13 / 255, blue: 13 / 255))

                Canvas { context, size in
                    let diameter = min(size.width, size.height)
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    var ringIndex = 0

                    for radius in stride(from: diameter / 2 - 3, through: 10, by: -4) {
                        let rect = CGRect(
                            x: center.x - radius,
                            y: center.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                        let color =
                            ringIndex.isMultiple(of: 2)
                                ? Color(red: 36 / 255, green: 34 / 255, blue: 34 / 255)
                                : Color(red: 19 / 255, green: 18 / 255, blue: 18 / 255)
                        context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 2)
                        ringIndex += 1
                    }
                }
                .clipShape(.circle)

                Circle()
                    .inset(by: 10)
                    .fill(
                        AngularGradient(
                            stops: [
                                .init(color: .clear, location: 0.00),
                                .init(color: .clear, location: 0.06),
                                .init(color: .white.opacity(0.09), location: 0.10),
                                .init(color: .clear, location: 0.14),
                                .init(color: .clear, location: 0.52),
                                .init(color: .white.opacity(0.06), location: 0.57),
                                .init(color: .clear, location: 0.62),
                                .init(color: .clear, location: 1.00),
                            ],
                            center: .center,
                            angle: .degrees(210)
                        )
                    )

                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(
                                    color: Color(red: 239 / 255, green: 233 / 255, blue: 224 / 255),
                                    location: 0.00
                                ),
                                .init(
                                    color: Color(red: 239 / 255, green: 233 / 255, blue: 224 / 255),
                                    location: 0.11
                                ),
                                .init(color: labelColor, location: 0.15),
                                .init(color: labelColor, location: 0.78),
                                .init(color: labelColor.opacity(0.55), location: 1.00),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 41 * LibraryDesignTokens.recordScale
                        )
                    )
                    .frame(
                        width: 82 * LibraryDesignTokens.recordScale,
                        height: 82 * LibraryDesignTokens.recordScale
                    )
                    .overlay {
                        Circle()
                            .stroke(.black.opacity(0.30), lineWidth: 1)
                    }
            }
            .rotationEffect(.degrees(angle))
        }
        .frame(width: LibraryDesignTokens.recordDiameter, height: LibraryDesignTokens.recordDiameter)
        .shadow(
            color: .black.opacity(0.44),
            radius: 24 * LibraryDesignTokens.recordScale,
            y: 18 * LibraryDesignTokens.recordScale
        )
        .onAppear(perform: updateRotationState)
        .onChange(of: isPlaying) {
            updateRotationState()
        }
        .onChange(of: reduceMotion) {
            updateRotationState()
        }
        .accessibilityHidden(true)
    }

    private func updateRotationState() {
        if isPlaying, reduceMotion == false {
            if rotationStartedAt == nil {
                rotationStartedAt = .now
            }
            return
        }

        if let rotationStartedAt {
            accumulatedRotationTime += max(0, Date.now.timeIntervalSince(rotationStartedAt))
            self.rotationStartedAt = nil
        }
    }
}

#Preview("黑胶唱片") {
    VinylRecordView(labelColor: LibraryDesignTokens.accent, isPlaying: false, reduceMotion: false)
}
