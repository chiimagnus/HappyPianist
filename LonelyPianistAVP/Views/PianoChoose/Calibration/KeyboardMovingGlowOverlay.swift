import SwiftUI

struct KeyboardMovingGlowOverlay: View {
    let isActive: Bool
    let startFraction: CGFloat
    let endFraction: CGFloat

    @State private var progress: CGFloat = 0
    private let animationDurationSeconds: Double = 1.25

    var body: some View {
        // KEEP_GEOMETRYREADER: needs live size to compute glow travel and clipping correctly.
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let glowWidth = max(60, width * 0.18)
            let clampedStart = max(0, min(1, startFraction))
            let clampedEnd = max(0, min(1, endFraction))

            let startCenterX = clampedStart * width
            let endCenterX = clampedEnd * width
            let centerX = startCenterX + (progress * (endCenterX - startCenterX))
            let x = centerX - (glowWidth / 2)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.blue.opacity(0.32),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: glowWidth, height: height)
                .blur(radius: 10)
                .offset(x: x, y: 0)
                .opacity(isActive ? 1 : 0)
                .allowsHitTesting(false)
                .task(id: isActive) {
                    if isActive {
                        withTransaction(Transaction(animation: nil)) {
                            progress = 0
                        }
                        withAnimation(.easeInOut(duration: animationDurationSeconds)) {
                            progress = 1
                        }
                    } else {
                        withTransaction(Transaction(animation: nil)) {
                            progress = 0
                        }
                    }
                }
        }
        .clipShape(.rect(cornerRadius: 12))
        .allowsHitTesting(false)
    }
}
