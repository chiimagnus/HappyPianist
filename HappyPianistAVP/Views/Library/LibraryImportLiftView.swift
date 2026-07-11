import SwiftUI

struct LibraryImportLiftView: View {
    let liftOffset: CGFloat

    var body: some View {
        let progress = min(max(liftOffset / LibraryDesignTokens.liftMaximum, 0), 1)
        let isArmed = liftOffset >= LibraryDesignTokens.liftTrigger

        Label("导入 MusicXML", systemImage: "plus")
            .font(.subheadline)
            .foregroundStyle(isArmed ? LibraryDesignTokens.accentForeground : LibraryDesignTokens.text)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(
                isArmed
                    ? LibraryDesignTokens.accent
                    : Color(red: 30 / 255, green: 27 / 255, blue: 26 / 255).opacity(0.66),
                in: .capsule
            )
            .overlay {
                Capsule()
                    .stroke(
                        isArmed ? LibraryDesignTokens.accent : Color.white.opacity(0.42),
                        style: StrokeStyle(lineWidth: 1, dash: isArmed ? [] : [5, 4])
                    )
            }
            .opacity(progress)
            .scaleEffect(0.92 + 0.08 * progress)
            .offset(y: 66 - 18 * progress)
            .accessibilityHidden(true)
    }
}
