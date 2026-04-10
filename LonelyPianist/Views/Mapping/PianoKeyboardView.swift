import SwiftUI

struct PianoKeyLabels {
    var noteName: String
    var mappingLabel: String?
}

struct PianoKeyboardView: View {
    let noteRange: ClosedRange<Int>
    let highlightedNotes: Set<Int>
    let selectedNotes: Set<Int>
    let labelsForNote: (Int) -> PianoKeyLabels
    let onTapNote: (Int) -> Void

    init(
        noteRange: ClosedRange<Int>,
        highlightedNotes: Set<Int> = [],
        selectedNotes: Set<Int> = [],
        labelsForNote: @escaping (Int) -> PianoKeyLabels = { note in
            PianoKeyLabels(noteName: MIDINote(note).name, mappingLabel: nil)
        },
        onTapNote: @escaping (Int) -> Void = { _ in }
    ) {
        self.noteRange = noteRange
        self.highlightedNotes = highlightedNotes
        self.selectedNotes = selectedNotes
        self.labelsForNote = labelsForNote
        self.onTapNote = onTapNote
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = PianoLayout(noteRange: noteRange)
            let whiteWidth = max(geometry.size.width / max(CGFloat(layout.whiteNotes.count), 1), 16)
            let blackWidth = whiteWidth * 0.62
            let blackHeight = geometry.size.height * 0.62

            ZStack(alignment: .topLeading) {
                ForEach(layout.whiteNotes, id: \ .self) { note in
                    let x = CGFloat(layout.whiteIndexByNote[note] ?? 0) * whiteWidth
                    PianoWhiteKeyView(
                        labels: labelsForNote(note),
                        state: state(for: note),
                        action: { onTapNote(note) }
                    )
                    .frame(width: whiteWidth, height: geometry.size.height)
                    .position(x: x + (whiteWidth / 2), y: geometry.size.height / 2)
                }

                ForEach(layout.blackNotes, id: \ .self) { note in
                    let leftWhiteIndex = layout.leftWhiteIndex(forBlackNote: note)
                    let x = (CGFloat(leftWhiteIndex) + 1) * whiteWidth - (blackWidth / 2)
                    PianoBlackKeyView(
                        labels: labelsForNote(note),
                        state: state(for: note),
                        action: { onTapNote(note) }
                    )
                    .frame(width: blackWidth, height: blackHeight)
                    .position(x: x + (blackWidth / 2), y: blackHeight / 2)
                    .zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minHeight: 180)
    }

    private func state(for note: Int) -> PianoKeyVisualState {
        let isHighlighted = highlightedNotes.contains(note)
        let isSelected = selectedNotes.contains(note)

        switch (isHighlighted, isSelected) {
        case (true, true):
            return .highlightedAndSelected
        case (true, false):
            return .highlighted
        case (false, true):
            return .selected
        case (false, false):
            return .normal
        }
    }
}

private enum PianoKeyVisualState {
    case normal
    case highlighted
    case selected
    case highlightedAndSelected
}

private struct PianoLayout {
    let noteRange: ClosedRange<Int>
    let whiteNotes: [Int]
    let blackNotes: [Int]
    let whiteIndexByNote: [Int: Int]

    init(noteRange: ClosedRange<Int>) {
        self.noteRange = noteRange

        let notes = Array(noteRange)
        whiteNotes = notes.filter { !Self.isBlackNote($0) }
        blackNotes = notes.filter(Self.isBlackNote)

        var indexMap: [Int: Int] = [:]
        for (index, note) in whiteNotes.enumerated() {
            indexMap[note] = index
        }
        whiteIndexByNote = indexMap
    }

    func leftWhiteIndex(forBlackNote note: Int) -> Int {
        var cursor = note - 1
        while cursor >= noteRange.lowerBound {
            if let index = whiteIndexByNote[cursor] {
                return index
            }
            cursor -= 1
        }
        return 0
    }

    nonisolated static func isBlackNote(_ note: Int) -> Bool {
        switch note % 12 {
        case 1, 3, 6, 8, 10:
            return true
        default:
            return false
        }
    }
}

private struct PianoWhiteKeyView: View {
    let labels: PianoKeyLabels
    let state: PianoKeyVisualState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(labels.mappingLabel ?? "")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 0)

                Text(labels.noteName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.secondary)
                    .padding(.bottom, 6)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var background: some ShapeStyle {
        switch state {
        case .normal:
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
        case .highlighted:
            return AnyShapeStyle(Color.accentColor.opacity(0.22))
        case .selected:
            return AnyShapeStyle(Color.orange.opacity(0.2))
        case .highlightedAndSelected:
            return AnyShapeStyle(Color.accentColor.opacity(0.35))
        }
    }

    private var borderColor: Color {
        switch state {
        case .normal:
            return Color(nsColor: .separatorColor)
        case .highlighted:
            return Color.accentColor.opacity(0.75)
        case .selected:
            return Color.orange.opacity(0.8)
        case .highlightedAndSelected:
            return Color.accentColor
        }
    }

    private var borderWidth: CGFloat {
        state == .normal ? 1 : 1.4
    }
}

private struct PianoBlackKeyView: View {
    let labels: PianoKeyLabels
    let state: PianoKeyVisualState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(labels.mappingLabel ?? "")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)

                Spacer(minLength: 0)

                Text(labels.noteName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .padding(.bottom, 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var background: some ShapeStyle {
        switch state {
        case .normal:
            return AnyShapeStyle(Color(nsColor: .labelColor).opacity(0.86))
        case .highlighted:
            return AnyShapeStyle(Color.accentColor.opacity(0.78))
        case .selected:
            return AnyShapeStyle(Color.orange.opacity(0.75))
        case .highlightedAndSelected:
            return AnyShapeStyle(Color.accentColor)
        }
    }

    private var borderColor: Color {
        switch state {
        case .normal:
            return Color.black.opacity(0.45)
        case .highlighted, .highlightedAndSelected:
            return Color.accentColor.opacity(0.95)
        case .selected:
            return Color.orange.opacity(0.95)
        }
    }

    private var borderWidth: CGFloat {
        state == .normal ? 0.8 : 1.3
    }
}

#Preview {
    PianoKeyboardView(
        noteRange: 48...83,
        highlightedNotes: [60, 64, 67],
        selectedNotes: [61, 63],
        labelsForNote: { note in
            let map: [Int: String] = [60: "a", 61: "w", 62: "s", 63: "e", 64: "d", 67: "g"]
            return PianoKeyLabels(noteName: MIDINote(note).name, mappingLabel: map[note])
        }
    ) { _ in }
    .padding()
    .frame(width: 980, height: 230)
}