import SwiftUI
import Library

private let libraryBookFlowCoordinateSpace = "LibraryBookFlow"

struct LibraryBookFlow: View {
    private static let animation = Animation.timingCurve(0.16, 1, 0.30, 1, duration: 0.56)

    let entries: [SongLibraryEntry]
    let selectedEntryID: UUID?
    let playingEntryID: UUID?
    let isPlaying: Bool
    let reduceMotion: Bool
    let allowsDestructiveActions: Bool
    let onSelectEntry: (UUID) -> Void
    let onTogglePlayback: (UUID) -> Void
    let onImportMusicXML: () -> Void
    let onImmediateDelete: (UUID) -> Void

    init(
        entries: [SongLibraryEntry],
        selectedEntryID: UUID?,
        playingEntryID: UUID?,
        isPlaying: Bool,
        reduceMotion: Bool,
        allowsDestructiveActions: Bool,
        onSelectEntry: @escaping (UUID) -> Void,
        onTogglePlayback: @escaping (UUID) -> Void,
        onImportMusicXML: @escaping () -> Void,
        onImmediateDelete: @escaping (UUID) -> Void
    ) {
        self.entries = entries
        self.selectedEntryID = selectedEntryID
        self.playingEntryID = playingEntryID
        self.isPlaying = isPlaying
        self.reduceMotion = reduceMotion
        self.allowsDestructiveActions = allowsDestructiveActions
        self.onSelectEntry = onSelectEntry
        self.onTogglePlayback = onTogglePlayback
        self.onImportMusicXML = onImportMusicXML
        self.onImmediateDelete = onImmediateDelete
    }

    @ScaledMetric(relativeTo: .body) private var itemWidth: CGFloat = 200
    @State private var scrollTargetID: UUID?
    @State private var viewportWidth: CGFloat = 0
    @State private var liftOffset: CGFloat = 0
    @State private var downwardDragOffset: CGFloat = 0
    @State private var hasVerticalDragIntent = false
    @State private var deletionHoldEntryID: UUID?
    @State private var deletionHoldStartedAt: Date?
    @State private var didDeleteDuringDrag = false

    private var selectedEntry: SongLibraryEntry? {
        entries.first(where: { $0.id == selectedEntryID })
    }

    private var scrollContentMargin: CGFloat {
        max(0, (viewportWidth - itemWidth) / 2)
    }

    var body: some View {
        let selectedIndex = entries.firstIndex(where: { $0.id == selectedEntryID }) ?? 0
        let selectedEntry = entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil
        ZStack {
            LibraryImportLiftView(liftOffset: liftOffset)
                .offset(y: itemWidth * 1.4 / 2 - 74)
                .zIndex(1)

            LibraryDeleteHoldView(
                downwardDragOffset: downwardDragOffset,
                holdStartedAt: deletionHoldStartedAt,
                isBundled: selectedEntry?.isBundled == true,
                allowsDestructiveActions: allowsDestructiveActions
            )
            .offset(y: 74 - itemWidth * 1.4 / 2)
            .zIndex(1)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 24) {
                    ForEach(entries.enumerated(), id: \.element.id) { index, entry in
                        LibraryBookFlowItemView(
                            entry: entry,
                            index: index,
                            selectedEntryID: selectedEntryID,
                            playingEntryID: playingEntryID,
                            isPlaying: isPlaying,
                            reduceMotion: reduceMotion,
                            verticalOffset: downwardDragOffset - liftOffset,
                            viewportWidth: viewportWidth,
                            itemWidth: itemWidth,
                            onTap: handleFolioConfirm
                        )
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(anchor: .center))
            .scrollPosition(id: $scrollTargetID, anchor: .center)
            .contentMargins(.horizontal, scrollContentMargin, for: .scrollContent)
            .coordinateSpace(name: libraryBookFlowCoordinateSpace)
            .onScrollPhaseChange { _, newPhase, _ in
                guard newPhase == .idle else { return }
                commitSettledScrollSelection()
            }

            VStack {
                Spacer()
                Text("↑ 上拽导入乐谱")
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .padding(.bottom, 54)
            }
            .zIndex(35)
            .accessibilityHidden(true)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 410,
            maxHeight: .infinity
        )
        .contentShape(.rect)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { _, width in
            viewportWidth = width
        }
        .simultaneousGesture(verticalDragGesture)
        .task(id: deletionHoldEntryID) {
            guard let entryID = deletionHoldEntryID else { return }

            do {
                try await Task.sleep(for: .seconds(LibraryDeletionHoldPolicy.durationSeconds))
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
            synchronizeScrollTarget(with: selectedEntryID)
        }
        .onChange(of: entries.map(\.id)) { _, entryIDs in
            if let scrollTargetID, entryIDs.contains(scrollTargetID) == false {
                self.scrollTargetID = nil
            }
            synchronizeScrollTarget(with: selectedEntryID)
        }
        .onAppear {
            synchronizeScrollTarget(with: selectedEntryID)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("乐谱库，左右滚动选曲")
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

    private var verticalDragGesture: some Gesture {
        DragGesture(minimumDistance: 7)
            .onChanged { value in
                guard hasVerticalDragIntent || LibraryVerticalDragIntentPolicy.isClearlyVertical(
                    translation: value.translation
                ) else {
                    return
                }
                hasVerticalDragIntent = true

                if value.translation.height < 0 {
                    cancelDeletionHold()
                    downwardDragOffset = 0
                    liftOffset = min(-value.translation.height, LibraryBookFlowDragConfiguration.maximumOffset)
                } else {
                    liftOffset = 0
                    downwardDragOffset = min(value.translation.height, LibraryBookFlowDragConfiguration.maximumOffset)
                    updateDeletionHold(for: value.translation.height)
                }
            }
            .onEnded { _ in
                if hasVerticalDragIntent,
                   liftOffset >= LibraryBookFlowDragConfiguration.trigger,
                   didDeleteDuringDrag == false
                {
                    onImportMusicXML()
                }

                withAnimation(reduceMotion ? nil : Self.animation) {
                    liftOffset = 0
                    downwardDragOffset = 0
                }
                cancelDeletionHold()
                didDeleteDuringDrag = false
                hasVerticalDragIntent = false
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

    private func handleFolioConfirm(entryID: UUID) {
        switch LibraryBookFlowSelectionDecision.action(
            forTappedEntryID: entryID,
            selectedEntryID: selectedEntryID
        ) {
        case .togglePlayback:
            onTogglePlayback(entryID)
        case .selectEntry:
            select(entryID: entryID)
        }
    }

    private func select(index: Int) {
        guard entries.indices.contains(index) else { return }
        select(entryID: entries[index].id)
    }

    private func select(entryID: UUID) {
        withAnimation(reduceMotion ? nil : Self.animation) {
            scrollTargetID = entryID
        }
        onSelectEntry(entryID)
    }

    private func commitSettledScrollSelection() {
        guard let entryID = LibraryBookFlowSelectionDecision.selectionToCommit(
            scrollTargetID: scrollTargetID,
            selectedEntryID: selectedEntryID
        ), entries.contains(where: { $0.id == entryID })
        else {
            return
        }
        onSelectEntry(entryID)
    }

    private func synchronizeScrollTarget(with entryID: UUID?) {
        guard let entryID, entries.contains(where: { $0.id == entryID }) else {
            scrollTargetID = nil
            return
        }
        guard scrollTargetID != entryID else { return }
        withAnimation(reduceMotion ? nil : Self.animation) {
            scrollTargetID = entryID
        }
    }
}

private struct LibraryBookFlowItemView: View {
    @State private var centerDistance: CGFloat = 0
    let entry: SongLibraryEntry
    let index: Int
    let selectedEntryID: UUID?
    let playingEntryID: UUID?
    let isPlaying: Bool
    let reduceMotion: Bool
    let verticalOffset: CGFloat
    let viewportWidth: CGFloat
    let itemWidth: CGFloat
    let onTap: (UUID) -> Void

    private var isSelected: Bool {
        entry.id == selectedEntryID
    }

    private var trackPresentation: SongLibraryTrackPresentation {
        SongLibraryTrackPresentation(entry: entry, index: index)
    }

    var body: some View {
        let presentation = LibraryBookFlowPresentation(
            centerDistance: centerDistance,
            itemExtent: itemWidth,
            reduceMotion: reduceMotion
        )
        ZStack {
            Button {
                onTap(entry.id)
            } label: {
                LibraryScoreFolioView(
                    presentation: trackPresentation,
                    isPlaying: playingEntryID == entry.id && isPlaying
                )
            }
            .buttonStyle(.plain)
            .hoverEffect()
            .perspectiveRotationEffect(.degrees(presentation.rotationDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .scaleEffect(presentation.scale)
            .opacity(presentation.opacity)
            .offset(x: presentation.horizontalOffset)
            .offset(y: isSelected ? verticalOffset : 0)
            .accessibilityLabel(trackPresentation.title)
            .accessibilityHint(isSelected ? "播放或暂停当前曲目" : "选中这首曲目")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .frame(
            width: itemWidth,
            height: itemWidth * 1.4
        )
        .onGeometryChange(for: CGFloat.self, of: {
            $0.frame(in: .named(libraryBookFlowCoordinateSpace)).midX - viewportWidth / 2
        }) { distance in
            guard viewportWidth > 0 else { return }
            centerDistance = distance
        }
        .zIndex(presentation.depthPriority)
    }
}

enum LibraryBookFlowTapAction: Equatable {
    case togglePlayback
    case selectEntry
}

enum LibraryBookFlowSelectionDecision {
    static func action(
        forTappedEntryID entryID: UUID,
        selectedEntryID: UUID?
    ) -> LibraryBookFlowTapAction {
        entryID == selectedEntryID ? .togglePlayback : .selectEntry
    }

    static func selectionToCommit(
        scrollTargetID: UUID?,
        selectedEntryID: UUID?
    ) -> UUID? {
        guard let scrollTargetID, scrollTargetID != selectedEntryID else { return nil }
        return scrollTargetID
    }
}

#Preview("正在播放的乐谱库") {
    LibraryBookFlow(
        entries: LibraryBookFlowPreviewFixture.entries,
        selectedEntryID: LibraryBookFlowPreviewFixture.entries[1].id,
        playingEntryID: LibraryBookFlowPreviewFixture.entries[1].id,
        isPlaying: true,
        reduceMotion: false,
        allowsDestructiveActions: true,
        onSelectEntry: { _ in },
        onTogglePlayback: { _ in },
        onImportMusicXML: {},
        onImmediateDelete: { _ in }
    )
    .frame(width: 1140, height: 500)
}

private enum LibraryBookFlowPreviewFixture {
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
