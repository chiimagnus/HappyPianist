import Foundation
import Library
import SwiftUI

private let macLibraryRecordShelfCoordinateSpace = "MacLibraryRecordShelf"

struct MacLibraryRecordShelfView: View {
    let entries: [SongLibraryEntry]
    let selectedEntryID: UUID?
    let playingEntryID: UUID?
    let isPlaying: Bool
    let allowsDestructiveActions: Bool
    let onSelectEntry: (UUID) -> Void
    let onTogglePlayback: (UUID) -> Void
    let onImportAudio: (UUID) -> Void
    let onDelete: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollTargetID: UUID?
    @State private var shelfWidth: CGFloat = 0

    private var selectedIndex: Int {
        entries.firstIndex(where: { $0.id == selectedEntryID }) ?? 0
    }

    private var contentMargin: CGFloat {
        max(0, (shelfWidth - MacLibraryRecordLayout.diameter) / 2)
    }

    var body: some View {
        ZStack {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 24) {
                    ForEach(entries.enumerated(), id: \.element.id) { index, entry in
                        MacLibraryRecordItemView(
                            entry: entry,
                            index: index,
                            isSelected: entry.id == selectedEntryID,
                            isPlaying: entry.id == playingEntryID && isPlaying,
                            reduceMotion: reduceMotion,
                            shelfWidth: shelfWidth,
                            allowsDestructiveActions: allowsDestructiveActions,
                            onSelect: onSelectEntry,
                            onTogglePlayback: onTogglePlayback,
                            onImportAudio: onImportAudio,
                            onDelete: onDelete
                        )
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(anchor: .center))
            .scrollPosition(id: $scrollTargetID, anchor: .center)
            .contentMargins(.horizontal, contentMargin, for: .scrollContent)
            .coordinateSpace(name: macLibraryRecordShelfCoordinateSpace)
            .onScrollPhaseChange { _, newPhase, _ in
                guard newPhase == .idle,
                      let scrollTargetID,
                      scrollTargetID != selectedEntryID
                else {
                    return
                }
                onSelectEntry(scrollTargetID)
            }

            MacLibraryTonearmView(isPlaying: isPlaying, reduceMotion: reduceMotion)

            VStack {
                Spacer()
                MacLibraryPageIndicatorView(count: entries.count, selectedIndex: selectedIndex)
                    .padding(.bottom, 10)
            }
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, minHeight: 392, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { _, width in
            shelfWidth = width
        }
        .onAppear {
            scrollTargetID = selectedEntryID
        }
        .onChange(of: selectedEntryID) { _, entryID in
            guard scrollTargetID != entryID else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.36)) {
                scrollTargetID = entryID
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("唱片架，左右滚动选曲")
        .accessibilityAdjustableAction { direction in
            let targetIndex = switch direction {
            case .increment: selectedIndex + 1
            case .decrement: selectedIndex - 1
            @unknown default: selectedIndex
            }
            guard entries.indices.contains(targetIndex) else { return }
            onSelectEntry(entries[targetIndex].id)
        }
    }
}

private struct MacLibraryRecordItemView: View {
    let entry: SongLibraryEntry
    let index: Int
    let isSelected: Bool
    let isPlaying: Bool
    let reduceMotion: Bool
    let shelfWidth: CGFloat
    let allowsDestructiveActions: Bool
    let onSelect: (UUID) -> Void
    let onTogglePlayback: (UUID) -> Void
    let onImportAudio: (UUID) -> Void
    let onDelete: (UUID) -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            if isSelected {
                onTogglePlayback(entry.id)
            } else {
                onSelect(entry.id)
            }
        } label: {
            MacVinylRecordView(
                labelColor: MacLibraryRecordLayout.labelColor(for: index),
                isPlaying: isPlaying,
                reduceMotion: reduceMotion
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .visualEffect { content, geometry in
            let distance = abs(
                geometry.frame(in: .named(macLibraryRecordShelfCoordinateSpace)).midX - shelfWidth / 2
            )
            let emphasis = 1 - min(1, distance / max(1, shelfWidth / 2))
            return content
                .scaleEffect(0.84 + 0.16 * emphasis)
                .opacity(0.58 + 0.42 * emphasis)
                .saturation(0.55 + 0.45 * emphasis)
        }
        .scaleEffect(isHovered ? 1.03 : 1)
        .contextMenu {
            if entry.isBundled != true {
                Button(
                    entry.audioFileName == nil ? "绑定音频" : "替换音频",
                    systemImage: "waveform.badge.plus"
                ) {
                    onImportAudio(entry.id)
                }
                .disabled(allowsDestructiveActions == false)

                Divider()

                Button("删除曲目", systemImage: "trash", role: .destructive) {
                    onDelete(entry.id)
                }
                .disabled(allowsDestructiveActions == false)
            }
        }
        .accessibilityLabel(entry.displayName)
        .accessibilityHint(isSelected ? "点按试听或暂停；右键打开曲目操作" : "点按选中这首曲目")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct MacLibraryTrackInfoView: View {
    let entry: SongLibraryEntry
    let isPlaying: Bool
    let isImporting: Bool
    let onTogglePlayback: () -> Void
    let onImportAudio: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.displayName.replacing("_", with: " "))
                .font(.system(.largeTitle, design: .serif))
                .bold()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 14) {
                Label(entry.musicXMLFileName, systemImage: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)

                Spacer()

                if entry.audioFileName != nil {
                    Button(
                        isPlaying ? "暂停试听" : "试听",
                        systemImage: isPlaying ? "pause.fill" : "play.fill",
                        action: onTogglePlayback
                    )
                    .labelStyle(.iconOnly)
                    .disabled(isImporting)
                    .accessibilityLabel(isPlaying ? "暂停试听" : "试听")
                }

                if entry.isBundled != true {
                    Menu("曲目操作", systemImage: "ellipsis.circle") {
                        Button(
                            entry.audioFileName == nil ? "绑定音频" : "替换音频",
                            systemImage: "waveform.badge.plus",
                            action: onImportAudio
                        )
                        .disabled(isImporting)

                        Divider()

                        Button("删除曲目", systemImage: "trash", role: .destructive, action: onDelete)
                            .disabled(isImporting)
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private var subtitle: String {
        if entry.isBundled == true { return "内置曲目" }
        return "导入于 \(entry.importedAt.formatted(date: .abbreviated, time: .omitted))"
    }
}

private struct MacLibraryPageIndicatorView: View {
    let count: Int
    let selectedIndex: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if count > 12 {
            Text("\(selectedIndex + 1) / \(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else {
            HStack(spacing: 7) {
                ForEach(0 ..< count, id: \.self) { index in
                    Capsule()
                        .fill(index == selectedIndex ? Color.primary : Color.primary.opacity(0.28))
                        .frame(width: index == selectedIndex ? 22 : 6, height: 6)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.30), value: selectedIndex)
                }
            }
        }
    }
}

private struct MacVinylRecordView: View {
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
                    .shadow(color: .black.opacity(0.44), radius: 22, y: 16)

                Canvas { context, size in
                    let diameter = min(size.width, size.height)
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    for (index, radius) in stride(from: diameter / 2 - 3, through: 10, by: -4).enumerated() {
                        let rect = CGRect(
                            x: center.x - radius,
                            y: center.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                        let color = index.isMultiple(of: 2)
                            ? Color(red: 36 / 255, green: 34 / 255, blue: 34 / 255)
                            : Color(red: 19 / 255, green: 18 / 255, blue: 18 / 255)
                        context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 2)
                    }
                }
                .clipShape(.circle)

                Circle()
                    .inset(by: 10)
                    .fill(
                        AngularGradient(
                            stops: [
                                .init(color: .clear, location: 0.06),
                                .init(color: .white.opacity(0.09), location: 0.10),
                                .init(color: .clear, location: 0.14),
                                .init(color: .clear, location: 0.52),
                                .init(color: .white.opacity(0.06), location: 0.57),
                                .init(color: .clear, location: 0.62),
                            ],
                            center: .center,
                            angle: .degrees(210)
                        )
                    )

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 239 / 255, green: 233 / 255, blue: 224 / 255),
                                Color(red: 239 / 255, green: 233 / 255, blue: 224 / 255),
                                labelColor,
                                labelColor.opacity(0.55),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 39
                        )
                    )
                    .frame(width: 78, height: 78)
                    .overlay {
                        Circle().stroke(.black.opacity(0.30), lineWidth: 1)
                    }
            }
            .rotationEffect(.degrees(angle))
        }
        .frame(width: MacLibraryRecordLayout.diameter, height: MacLibraryRecordLayout.diameter)
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

private struct MacLibraryTonearmView: View {
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
                .position(x: 238, y: 176)

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
                .frame(width: 184, height: 7)
                .overlay(alignment: .trailing) {
                    Circle()
                        .fill(Color(red: 180 / 255, green: 174 / 255, blue: 165 / 255))
                        .frame(width: 30, height: 30)
                        .offset(x: 15)
                }
                .rotationEffect(.degrees(isPlaying ? -58 : -80), anchor: .trailing)
                .position(x: 172, y: 0)
                .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.62), value: isPlaying)
        }
        .frame(width: 264, height: 236, alignment: .topLeading)
        .scaleEffect(MacLibraryRecordLayout.diameter / 236, anchor: .topLeading)
        .frame(
            width: MacLibraryRecordLayout.diameter,
            height: MacLibraryRecordLayout.diameter,
            alignment: .topLeading
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum MacLibraryRecordLayout {
    static let diameter: CGFloat = 304

    static let palette: [Color] = [
        Color(red: 77 / 255, green: 127 / 255, blue: 116 / 255),
        Color(red: 197 / 255, green: 106 / 255, blue: 86 / 255),
        Color(red: 189 / 255, green: 148 / 255, blue: 82 / 255),
        Color(red: 138 / 255, green: 100 / 255, blue: 134 / 255),
        Color(red: 74 / 255, green: 102 / 255, blue: 140 / 255),
        Color(red: 142 / 255, green: 112 / 255, blue: 82 / 255),
    ]

    static func labelColor(for index: Int) -> Color {
        palette[index % palette.count]
    }
}
