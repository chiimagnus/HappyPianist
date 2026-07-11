import SwiftUI

struct LibraryCrateView: View {
    let entries: [SongLibraryEntry]
    @Binding var selectedEntryID: UUID?
    let playingEntryID: UUID?
    let isPlaying: Bool
    let reduceMotion: Bool
    let onSelectionChanged: (UUID) -> Void
    let onTogglePlayback: (UUID) -> Void
    let onImportMusicXML: () -> Void
    let onBindAudio: (UUID) -> Void
    let onDelete: (UUID) -> Void

    @State private var horizontalDragOffset: CGFloat = 0
    @State private var liftOffset: CGFloat = 0
    @State private var dragIsHorizontal: Bool?

    var body: some View {
        let selectedIndex = entries.firstIndex(where: { $0.id == selectedEntryID }) ?? 0

        ZStack {
            LibraryImportLiftView(liftOffset: liftOffset)
                .zIndex(1)

            ForEach(entries.enumerated(), id: \.element.id) { index, entry in
                let relativeIndex = index - selectedIndex
                let distance = abs(relativeIndex)

                if distance <= 3 {
                    let isActive = relativeIndex == 0
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
                            Button("删除曲目", systemImage: "trash", role: .destructive) {
                                onDelete(entry.id)
                            }
                        }
                    }
                    .rotation3DEffect(
                        .degrees(isActive ? 0 : relativeIndex < 0 ? 42 : -42),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.6
                    )
                    .scaleEffect(isActive ? 1 : 0.74)
                    .opacity(isActive ? 1 : 0.52)
                    .saturation(isActive ? 1 : 0.62)
                    .brightness(isActive ? 0 : -0.06)
                    .offset(
                        x: CGFloat(relativeIndex) * LibraryDesignTokens.recordSpacing + horizontalDragOffset,
                        y: isActive ? -liftOffset : 0
                    )
                    .zIndex(Double(20 - distance))
                    .animation(reduceMotion ? nil : LibraryDesignTokens.easeOut, value: selectedEntryID)
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
                .font(.title2)
                .frame(width: 46, height: 46)
                .background(
                    Color(red: 26 / 255, green: 23 / 255, blue: 22 / 255).opacity(0.44), in: .circle
                )
                .overlay { Circle().stroke(LibraryDesignTokens.line, lineWidth: 1) }
                .buttonStyle(.plain)
                .opacity(selectedIndex > 0 ? 0.95 : 0)
                .disabled(selectedIndex == 0)

                Spacer()

                Button("下一首", systemImage: "chevron.right") {
                    select(index: selectedIndex + 1)
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 46, height: 46)
                .background(
                    Color(red: 26 / 255, green: 23 / 255, blue: 22 / 255).opacity(0.44), in: .circle
                )
                .overlay { Circle().stroke(LibraryDesignTokens.line, lineWidth: 1) }
                .buttonStyle(.plain)
                .opacity(selectedIndex < entries.count - 1 ? 0.95 : 0)
                .disabled(selectedIndex >= entries.count - 1)
            }
            .padding(.horizontal, 18)
            .zIndex(50)

            VStack {
                Spacer()
                Text("↑ 上拽唱片导入乐谱")
                    .font(.caption)
                    .foregroundStyle(LibraryDesignTokens.faintText)
                    .padding(.bottom, 31)
            }
            .zIndex(35)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .contentShape(.rect)
        .highPriorityGesture(dragGesture)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("唱片架，左右滑动选曲")
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
                    horizontalDragOffset = value.translation.width
                } else if value.translation.height < 0 {
                    liftOffset = min(-value.translation.height, LibraryDesignTokens.liftMaximum)
                }
            }
            .onEnded { value in
                let selectedIndex = entries.firstIndex(where: { $0.id == selectedEntryID }) ?? 0

                if dragIsHorizontal == true {
                    if value.translation.width <= -60 {
                        select(index: selectedIndex + 1)
                    } else if value.translation.width >= 60 {
                        select(index: selectedIndex - 1)
                    }
                } else if liftOffset >= LibraryDesignTokens.liftTrigger {
                    onImportMusicXML()
                }

                withAnimation(reduceMotion ? nil : LibraryDesignTokens.easeOut) {
                    horizontalDragOffset = 0
                    liftOffset = 0
                }
                dragIsHorizontal = nil
            }
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
        withAnimation(reduceMotion ? nil : LibraryDesignTokens.easeOut) {
            selectedEntryID = entryID
        }
        onSelectionChanged(entryID)
    }
}
