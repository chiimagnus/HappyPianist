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

struct LibraryDeleteHoldView: View {
    let downwardDragOffset: CGFloat
    let holdStartedAt: Date?
    let isBundled: Bool
    let allowsDestructiveActions: Bool

    var body: some View {
        let dragProgress = LibraryDeletionHoldPolicy.progress(for: downwardDragOffset)
        let isDisabled = isBundled || allowsDestructiveActions == false

        TimelineView(.animation(minimumInterval: 1 / 30, paused: holdStartedAt == nil)) { context in
            let holdProgress = holdStartedAt.map {
                min(
                    max(
                        context.date.timeIntervalSince($0) / LibraryDesignTokens.deletionHoldSeconds,
                        0
                    ),
                    1
                )
            } ?? 0
            let isHolding = holdStartedAt != nil

            Label(
                isBundled
                    ? "内置曲目不能删除"
                    : allowsDestructiveActions
                        ? isHolding ? "继续按住删除" : "下拽唱片删除"
                        : "导入期间不能删除",
                systemImage: "trash"
            )
            .font(.subheadline)
            .foregroundStyle(isDisabled ? LibraryDesignTokens.faintText : isHolding ? .white : .red)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background {
                ZStack {
                    Capsule()
                        .fill(Color(red: 30 / 255, green: 27 / 255, blue: 26 / 255).opacity(0.66))

                    if isDisabled == false {
                        Capsule()
                            .fill(.red)
                            .scaleEffect(x: holdProgress, anchor: .leading)
                    }
                }
                .clipShape(.capsule)
            }
            .overlay {
                Capsule()
                    .stroke(
                        isDisabled ? Color.white.opacity(0.24) : isHolding ? .red : Color.white.opacity(0.42),
                        style: StrokeStyle(lineWidth: 1, dash: isHolding ? [] : [5, 4])
                    )
            }
            .opacity(dragProgress)
            .scaleEffect(0.92 + 0.08 * dragProgress)
            .offset(y: -66 + 18 * dragProgress)
            .accessibilityHidden(true)
        }
    }
}
