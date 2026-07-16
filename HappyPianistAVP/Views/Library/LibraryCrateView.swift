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
    let onDelete: (UUID) -> Void

    @State private var horizontalDragOffset: CGFloat = 0
    @State private var liftOffset: CGFloat = 0
    @State private var dragIsHorizontal: Bool?

    var body: some View {
        let selectedIndex = entries.firstIndex(where: { $0.id == selectedEntryID }) ?? 0
        let dragProgress = horizontalDragOffset / LibraryDesignTokens.carouselNeighborOffset

        ZStack {
            LibraryImportLiftView(liftOffset: liftOffset)
                .offset(y: LibraryDesignTokens.recordDiameter / 2 - 74)
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
                            Button("删除曲目", systemImage: "trash", role: .destructive) {
                                onDelete(entry.id)
                            }
                            .disabled(allowsDestructiveActions == false)
                            .accessibilityHint(
                                allowsDestructiveActions ? "删除当前曲目" : "曲谱导入期间不能删除曲目"
                            )
                        }
                    }
                    // ponytail: visionOS clips rotated record layers; horizontal compression keeps the depth cue.
                    .scaleEffect(x: pose.scale * pose.horizontalScale, y: pose.scale)
                    .opacity(pose.opacity)
                    .saturation(pose.saturation)
                    .offset(
                        x: pose.horizontalOffset,
                        y: isActive ? -liftOffset : 0
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
                    horizontalDragOffset = min(
                        max(
                            value.translation.width,
                            -LibraryDesignTokens.carouselNeighborOffset
                        ),
                        LibraryDesignTokens.carouselNeighborOffset
                    )
                } else if value.translation.height < 0 {
                    liftOffset = min(-value.translation.height, LibraryDesignTokens.liftMaximum)
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

private struct VinylRecordView: View {
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
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                            .padding(2 * LibraryDesignTokens.recordScale)
                    }
            }
            .rotationEffect(.degrees(angle))
        }
        .frame(width: LibraryDesignTokens.recordDiameter, height: LibraryDesignTokens.recordDiameter)
        .overlay {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
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

private struct TurntableTonearmView: View {
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
        onDelete: { _ in }
    )
    .frame(width: 1_140, height: 500)
    .background(.black)
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
