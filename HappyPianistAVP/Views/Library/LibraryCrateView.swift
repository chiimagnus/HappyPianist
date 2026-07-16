import SwiftUI

struct LibraryCrateView: View {
    let entries: [SongLibraryEntry]
    let selectedEntryID: UUID?
    let playingEntryID: UUID?
    let isPlaying: Bool
    let reduceMotion: Bool
    let allowsDestructiveActions: Bool
    let onSelectEntry: (UUID) -> Void
    let onTogglePlayback: (UUID) -> Void
    let onImportMusicXML: () -> Void
    let onBindAudio: (UUID) -> Void
    let onImmediateDelete: (UUID) -> Void

    @State private var horizontalDragOffset: CGFloat = 0
    @State private var liftOffset: CGFloat = 0
    @State private var downwardDragOffset: CGFloat = 0
    @State private var dragIsHorizontal: Bool?
    @State private var deletionHoldEntryID: UUID?
    @State private var deletionHoldStartedAt: Date?
    @State private var didDeleteDuringDrag = false

    private var selectedEntry: SongLibraryEntry? {
        entries.first(where: { $0.id == selectedEntryID })
    }

    var body: some View {
        let selectedIndex = entries.firstIndex(where: { $0.id == selectedEntryID }) ?? 0
        let selectedEntry = entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil
        let dragProgress = horizontalDragOffset / LibraryDesignTokens.carouselNeighborOffset

        ZStack {
            LibraryImportLiftView(liftOffset: liftOffset)
                .offset(y: LibraryDesignTokens.recordDiameter / 2 - 74)
                .zIndex(1)

            LibraryDeleteHoldView(
                downwardDragOffset: downwardDragOffset,
                holdStartedAt: deletionHoldStartedAt,
                isBundled: selectedEntry?.isBundled == true,
                allowsDestructiveActions: allowsDestructiveActions
            )
            .offset(y: 74 - LibraryDesignTokens.recordDiameter / 2)
            .zIndex(1)

            ForEach(entries.enumerated(), id: \.element.id) { index, entry in
                let relativeIndex = index - selectedIndex
                let distance = abs(relativeIndex)

                if distance <= 3 {
                    let isActive = relativeIndex == 0
                    let pose = LibraryCarouselPose(
                        relativePosition: CGFloat(relativeIndex) + dragProgress
                    )
                    let presentation = SongLibraryTrackPresentation(entry: entry, index: index)

                    Button {
                        handleRecordTap(entryID: entry.id, index: index, selectedIndex: selectedIndex)
                    } label: {
                        VinylRecordView(
                            labelColor: presentation.labelColor,
                            isPlaying: isActive && playingEntryID == entry.id && isPlaying,
                            reduceMotion: reduceMotion
                        )
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                    .contextMenu {
                        if entry.isBundled != true {
                            Button("导入或替换音频", systemImage: "waveform") {
                                onBindAudio(entry.id)
                            }
                        }
                    }
                    // ponytail: visionOS clips rotated record layers; horizontal compression keeps the depth cue.
                    .scaleEffect(x: pose.scale * pose.horizontalScale, y: pose.scale)
                    .opacity(pose.opacity)
                    .saturation(pose.saturation)
                    .offset(
                        x: pose.horizontalOffset,
                        y: isActive ? downwardDragOffset - liftOffset : 0
                    )
                    .zIndex(pose.zIndex)
                    .animation(reduceMotion ? nil : LibraryDesignTokens.easeOut, value: selectedEntryID)
                    .allowsHitTesting(distance <= 2)
                    .accessibilityHidden(distance > 2)
                    .accessibilityLabel(presentation.title)
                    .accessibilityHint(isActive ? "播放或暂停当前曲目" : "切换到这首曲目")
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }

            TurntableTonearmView(isPlaying: isPlaying, reduceMotion: reduceMotion)
                .zIndex(30)

            VStack {
                Spacer()
                LibraryPageIndicatorView(count: entries.count, selectedIndex: selectedIndex)
                    .padding(.bottom, 12)
            }
            .zIndex(40)

            HStack {
                Button("上一首", systemImage: "chevron.left") {
                    select(index: selectedIndex - 1)
                }
                .labelStyle(.iconOnly)
                .opacity(selectedIndex > 0 ? 0.95 : 0)
                .disabled(selectedIndex == 0)

                Spacer()

                Button("下一首", systemImage: "chevron.right") {
                    select(index: selectedIndex + 1)
                }
                .labelStyle(.iconOnly)
                .opacity(selectedIndex < entries.count - 1 ? 0.95 : 0)
                .disabled(selectedIndex >= entries.count - 1)
            }
            .padding()
            .zIndex(50)

            VStack {
                Spacer()
                Text("↑ 上拽唱片导入乐谱")
                    .font(.caption)
                    .foregroundStyle(LibraryDesignTokens.faintText)
                    .padding(.bottom, 54)
            }
            .zIndex(35)
            .accessibilityHidden(true)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: LibraryDesignTokens.crateMinimumHeight,
            maxHeight: .infinity
        )
        .contentShape(.rect)
        .highPriorityGesture(dragGesture)
        .task(id: deletionHoldEntryID) {
            guard let entryID = deletionHoldEntryID else { return }

            do {
                try await Task.sleep(for: LibraryDesignTokens.deletionHoldDuration)
            } catch {
                return
            }

            guard deletionHoldEntryID == entryID,
                  allowsDestructiveActions,
                  entries.contains(where: { $0.id == entryID && $0.isBundled != true })
            else {
                return
            }

            onImmediateDelete(entryID)
            didDeleteDuringDrag = true
            cancelDeletionHold()
        }
        .onChange(of: allowsDestructiveActions) { _, allowsDestructiveActions in
            if allowsDestructiveActions == false {
                cancelDeletionHold()
            }
        }
        .onChange(of: selectedEntryID) {
            cancelDeletionHold()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("唱片架，左右滑动选曲")
        .accessibilityAction(named: "删除曲目") {
            guard let selectedEntry,
                  selectedEntry.isBundled != true,
                  allowsDestructiveActions
            else {
                return
            }
            onImmediateDelete(selectedEntry.id)
        }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                select(index: selectedIndex + 1)
            case .decrement:
                select(index: selectedIndex - 1)
            @unknown default:
                break
            }
        }
        .clipped()
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 7)
            .onChanged { value in
                if dragIsHorizontal == nil {
                    dragIsHorizontal = abs(value.translation.width) >= abs(value.translation.height)
                }

                if dragIsHorizontal == true {
                    cancelDeletionHold()
                    horizontalDragOffset = min(
                        max(
                            value.translation.width,
                            -LibraryDesignTokens.carouselNeighborOffset
                        ),
                        LibraryDesignTokens.carouselNeighborOffset
                    )
                } else if value.translation.height < 0 {
                    cancelDeletionHold()
                    downwardDragOffset = 0
                    liftOffset = min(-value.translation.height, LibraryDesignTokens.liftMaximum)
                } else {
                    liftOffset = 0
                    downwardDragOffset = min(value.translation.height, LibraryDesignTokens.liftMaximum)
                    updateDeletionHold(for: value.translation.height)
                }
            }
            .onEnded { value in
                let selectedIndex = entries.firstIndex(where: { $0.id == selectedEntryID }) ?? 0

                if dragIsHorizontal == true {
                    switch LibraryCarouselSelectionDirection.from(
                        horizontalDragTranslation: value.translation.width
                    ) {
                    case .next:
                        select(index: selectedIndex + 1)
                    case .previous:
                        select(index: selectedIndex - 1)
                    case nil:
                        break
                    }
                } else if liftOffset >= LibraryDesignTokens.liftTrigger, didDeleteDuringDrag == false {
                    onImportMusicXML()
                }

                withAnimation(reduceMotion ? nil : LibraryDesignTokens.easeOut) {
                    horizontalDragOffset = 0
                    liftOffset = 0
                    downwardDragOffset = 0
                }
                cancelDeletionHold()
                didDeleteDuringDrag = false
                dragIsHorizontal = nil
            }
    }

    private func updateDeletionHold(for downwardDragTranslation: CGFloat) {
        guard didDeleteDuringDrag == false,
              let selectedEntry,
              LibraryDeletionHoldPolicy.isArmed(
                  downwardDragTranslation: downwardDragTranslation,
                  isBundled: selectedEntry.isBundled == true,
                  allowsDestructiveActions: allowsDestructiveActions
              )
        else {
            cancelDeletionHold()
            return
        }

        guard deletionHoldEntryID != selectedEntry.id else { return }
        deletionHoldEntryID = selectedEntry.id
        deletionHoldStartedAt = .now
    }

    private func cancelDeletionHold() {
        deletionHoldEntryID = nil
        deletionHoldStartedAt = nil
    }

    private func handleRecordTap(entryID: UUID, index: Int, selectedIndex: Int) {
        if index == selectedIndex {
            onTogglePlayback(entryID)
        } else {
            select(index: index)
        }
    }

    private func select(index: Int) {
        guard entries.indices.contains(index) else { return }
        let entryID = entries[index].id
        onSelectEntry(entryID)
    }
}

private struct LibraryImportLiftView: View {
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

private struct LibraryDeleteHoldView: View {
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

private struct LibraryPageIndicatorView: View {
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
                ForEach(0 ..< count, id: \.self) { index in
                    Capsule()
                        .fill(index == selectedIndex ? LibraryDesignTokens.text : Color.white.opacity(0.28))
                        .frame(width: index == selectedIndex ? 22 : 6, height: 6)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.30), value: selectedIndex)
                }
            }
        }
    }
}

#Preview("正在播放的唱片架") {
    LibraryCrateView(
        entries: LibraryCratePreviewFixture.entries,
        selectedEntryID: LibraryCratePreviewFixture.entries[1].id,
        playingEntryID: LibraryCratePreviewFixture.entries[1].id,
        isPlaying: true,
        reduceMotion: false,
        allowsDestructiveActions: true,
        onSelectEntry: { _ in },
        onTogglePlayback: { _ in },
        onImportMusicXML: {},
        onBindAudio: { _ in },
        onImmediateDelete: { _ in }
    )
    .frame(width: 1_140, height: 500)
}

private enum LibraryCratePreviewFixture {
    static let entries = [
        entry(named: "Bohemian Rhapsody"),
        entry(named: "Despacito"),
        entry(named: "Under Pressure"),
    ]

    private static func entry(named name: String) -> SongLibraryEntry {
        SongLibraryEntry(
            id: UUID(),
            displayName: name,
            musicXMLFileName: "\(name).musicxml",
            scoreFileVersionID: UUID(),
            importedAt: .now,
            audioFileName: "\(name).mp3",
            isBundled: true
        )
    }
}
