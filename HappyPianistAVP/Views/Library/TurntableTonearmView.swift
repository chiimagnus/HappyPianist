import SwiftUI

struct TurntableTonearmView: View {
    let isPlaying: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 207 / 255, green: 200 / 255, blue: 191 / 255),
                            Color(red: 125 / 255, green: 118 / 255, blue: 108 / 255),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 9, height: 36)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 239 / 255, green: 233 / 255, blue: 225 / 255),
                                    Color(red: 139 / 255, green: 133 / 255, blue: 123 / 255),
                                ],
                                center: UnitPoint(x: 0.40, y: 0.30),
                                startRadius: 0,
                                endRadius: 11
                            )
                        )
                        .frame(width: 17, height: 10)
                        .offset(y: -5)
                }
                .shadow(color: .black.opacity(0.40), radius: 5, y: 3)
                .position(
                    x: LibraryDesignTokens.armrestCenterX,
                    y: LibraryDesignTokens.armrestCenterY
                )

            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 238 / 255, green: 232 / 255, blue: 224 / 255),
                                Color(red: 162 / 255, green: 156 / 255, blue: 147 / 255),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: LibraryDesignTokens.tonearmLength, height: 7)
                    .shadow(color: .black.opacity(0.34), radius: 6, y: 4)
            }
            .frame(width: LibraryDesignTokens.tonearmLength, height: 40)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.31), Color(white: 0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 15, height: 22)
                    .rotationEffect(.degrees(30))
                    .offset(x: -6)
                    .shadow(color: .black.opacity(0.46), radius: 4, y: 2)
            }
            .overlay(alignment: .trailing) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 239 / 255, green: 233 / 255, blue: 225 / 255),
                                Color(red: 139 / 255, green: 133 / 255, blue: 123 / 255),
                            ],
                            center: UnitPoint(x: 0.36, y: 0.30),
                            startRadius: 0,
                            endRadius: 20
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay {
                        Circle().stroke(.white.opacity(0.38), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.42), radius: 7, y: 4)
                    .offset(x: 18)
            }
            .rotationEffect(.degrees(isPlaying ? -58 : -80), anchor: .trailing)
            .position(
                x: LibraryDesignTokens.tonearmPivotX - LibraryDesignTokens.tonearmLength / 2,
                y: LibraryDesignTokens.tonearmPivotY
            )
            .animation(reduceMotion ? nil : LibraryDesignTokens.ease, value: isPlaying)
        }
        .frame(
            width: LibraryDesignTokens.recordReferenceDiameter,
            height: LibraryDesignTokens.recordReferenceDiameter,
            alignment: .topLeading
        )
        .scaleEffect(LibraryDesignTokens.recordScale, anchor: .topLeading)
        .frame(
            width: LibraryDesignTokens.recordDiameter,
            height: LibraryDesignTokens.recordDiameter,
            alignment: .topLeading
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
