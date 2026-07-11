import SwiftUI

struct LibraryPageIndicatorView: View {
    let count: Int
    let selectedIndex: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if count > 12 {
            Text("\(selectedIndex + 1) / \(count)")
                .font(.caption)
                .foregroundStyle(LibraryDesignTokens.faintText)
                .monospacedDigit()
        } else {
            HStack(spacing: 7) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(index == selectedIndex ? LibraryDesignTokens.text : Color.white.opacity(0.28))
                        .frame(width: index == selectedIndex ? 22 : 6, height: 6)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.30), value: selectedIndex)
                }
            }
        }
    }
}
