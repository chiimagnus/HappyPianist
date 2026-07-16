import SwiftUI

struct LibraryPracticeEmptyAnimationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.18),
                    Color.accentColor.opacity(0.04),
                    .clear,
                ],
                center: .center,
                startRadius: 8,
                endRadius: 138
            )
            .frame(width: 282, height: 228)
            .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, expanded in
                content
                    .scaleEffect(expanded ? 1.04 : 0.96)
                    .opacity(expanded ? 1 : 0.72)
            } animation: { _ in
                reduceMotion ? nil : .easeInOut(duration: 2.4)
            }

            LibraryPracticePianoKeyboardView()
                .offset(y: 42)
                .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, raised in
                    content
                        .offset(y: raised ? -3 : 2)
                } animation: { _ in
                    reduceMotion ? nil : .easeInOut(duration: 2.2)
                }

            LibraryPracticeFloatingNote(
                systemImage: "music.note",
                horizontalOffset: -78,
                verticalOffset: -60,
                lift: 12,
                delay: 0
            )

            LibraryPracticeFloatingNote(
                systemImage: "music.note.list",
                horizontalOffset: 72,
                verticalOffset: -62,
                lift: 9,
                delay: 0.2
            )

            LibraryPracticeFloatingNote(
                systemImage: "music.quarternote.3",
                horizontalOffset: 8,
                verticalOffset: -103,
                lift: 14,
                delay: 0.42
            )
        }
        .frame(height: 246)
        .accessibilityHidden(true)
    }
}

private struct LibraryPracticePianoKeyboardView: View {
    private static let blackKeyOffsets: [CGFloat] = [39, 70, 132, 163, 194]

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.96),
                            Color.black.opacity(0.78),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 252, height: 116)
                .offset(y: 12)

            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.76),
                            Color.black.opacity(0.92),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 252, height: 112)
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }

            HStack(spacing: 3) {
                ForEach(0 ..< 7, id: \.self) { index in
                    LibraryPracticeWhiteKey(index: index)
                }
            }
            .padding(.leading, 10)
            .padding(.top, 10)

            ForEach(Self.blackKeyOffsets.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.black, .black.opacity(0.76)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 18, height: 57)
                    .offset(x: Self.blackKeyOffsets[index], y: 10)
                    .shadow(color: .black.opacity(0.22), radius: 3, y: 3)
            }
        }
        .frame(width: 252, height: 128)
        .rotationEffect(.degrees(-6))
        .perspectiveRotationEffect(
            .degrees(16),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.52
        )
        .shadow(color: .black.opacity(0.22), radius: 22, y: 18)
    }
}

private struct LibraryPracticeWhiteKey: View {
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(
                LinearGradient(
                    colors: [
                        .white,
                        .white.opacity(0.80),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 30, height: 92)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.black.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 2, y: 2)
            .phaseAnimator(reduceMotion ? [false] : [false, true, false]) { content, pressed in
                content
                    .offset(y: pressed ? 3 : 0)
                    .brightness(pressed ? -0.04 : 0)
            } animation: { phase in
                guard reduceMotion == false else { return nil }
                return .easeInOut(duration: phase ? 0.14 : 1.8).delay(Double(index) * 0.11)
            }
    }
}

private struct LibraryPracticeFloatingNote: View {
    let systemImage: String
    let horizontalOffset: CGFloat
    let verticalOffset: CGFloat
    let lift: CGFloat
    let delay: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(.title2, design: .rounded))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.tint)
            .offset(x: horizontalOffset, y: verticalOffset)
            .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, raised in
                content
                    .offset(y: raised ? -lift : lift / 3)
                    .rotationEffect(.degrees(raised ? 6 : -6))
                    .scaleEffect(raised ? 1.04 : 0.96)
                    .opacity(raised ? 1 : 0.72)
            } animation: { _ in
                reduceMotion ? nil : .easeInOut(duration: 1.55).delay(delay)
            }
    }
}

#Preview("无练习数据时的动画") {
    LibraryPracticeEmptyAnimationView()
}
