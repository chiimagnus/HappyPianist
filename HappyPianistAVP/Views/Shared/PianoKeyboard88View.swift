import SwiftUI

struct PianoKeyboard88Highlight: Equatable {
    enum Fill: Equatable {
        case guide(PianoGuideHighlightStyle)
        case solid(color: Color, opacity: Double)
    }

    let fill: Fill
}

struct PianoKeyboard88View: View {
    static let aspectRatio: CGFloat = CGFloat(PianoKeyboardTopology.whiteKeyCount) / 8

    let highlightByMIDINote: [Int: PianoKeyboard88Highlight]
    let highlightOccurrenceID: Int?
    let fingeringByMIDINote: [Int: String]

    init(
        highlightByMIDINote: [Int: PianoKeyboard88Highlight],
        highlightOccurrenceID: Int? = nil,
        fingeringByMIDINote: [Int: String] = [:]
    ) {
        self.highlightByMIDINote = highlightByMIDINote
        self.highlightOccurrenceID = highlightOccurrenceID
        self.fingeringByMIDINote = fingeringByMIDINote
    }

    var body: some View {
        // KEEP_GEOMETRYREADER: requires container size to compute key widths/heights for accurate rendering.
        GeometryReader { proxy in
            let whiteKeyWidth = proxy.size.width / CGFloat(max(1, Self.whiteKeys.count))
            let whiteKeyHeight = proxy.size.height
            let blackKeyWidth = whiteKeyWidth * 0.62
            let blackKeyHeight = whiteKeyHeight * 0.62

            ZStack(alignment: .topLeading) {
                ForEach(Self.whiteKeys) { key in
                    let highlight = highlightByMIDINote[key.midiNote]
                    Rectangle()
                        .fill(whiteKeyFillColor(midiNote: key.midiNote, highlight: highlight))
                        .overlay {
                            Rectangle()
                                .stroke(.black.opacity(0.22), lineWidth: 0.6)
                        }
                        .overlay(alignment: .bottom) {
                            if highlight != nil,
                               let fingering = fingeringByMIDINote[key.midiNote]
                            {
                                Text(fingering)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.black.opacity(0.78))
                                    .padding(.bottom, 10)
                            }
                        }
                        .frame(width: whiteKeyWidth, height: whiteKeyHeight)
                        .id(Self.highlightKeyViewID(
                            isBlackKey: false,
                            midiNote: key.midiNote,
                            highlightOccurrenceID: highlightOccurrenceID,
                            isHighlighted: highlight != nil
                        ))
                        .offset(x: CGFloat(key.whiteIndex) * whiteKeyWidth)
                }

                ForEach(Self.blackKeys) { key in
                    let highlight = highlightByMIDINote[key.midiNote]
                    Rectangle()
                        .fill(blackKeyFillColor(midiNote: key.midiNote, highlight: highlight))
                        .overlay {
                            Rectangle()
                                .stroke(.white.opacity(0.28), lineWidth: 0.5)
                        }
                        .overlay(alignment: .bottom) {
                            if highlight != nil,
                               let fingering = fingeringByMIDINote[key.midiNote]
                            {
                                Text(fingering)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .padding(.bottom, 6)
                            }
                        }
                        .frame(width: blackKeyWidth, height: blackKeyHeight)
                        .id(Self.highlightKeyViewID(
                            isBlackKey: true,
                            midiNote: key.midiNote,
                            highlightOccurrenceID: highlightOccurrenceID,
                            isHighlighted: highlight != nil
                        ))
                        .offset(
                            x: (CGFloat(key.leftWhiteIndex + 1) * whiteKeyWidth) - (blackKeyWidth / 2)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityLabel("88 键钢琴")
    }

    private func whiteKeyFillColor(midiNote _: Int, highlight: PianoKeyboard88Highlight?) -> Color {
        guard let highlight else { return .white }
        switch highlight.fill {
        case let .guide(style):
            return style.tintToken.swiftUIColor.opacity(style.opacity)
        case let .solid(color, opacity):
            return color.opacity(opacity)
        }
    }

    private func blackKeyFillColor(midiNote _: Int, highlight: PianoKeyboard88Highlight?) -> Color {
        guard let highlight else { return .black.opacity(0.88) }
        switch highlight.fill {
        case let .guide(style):
            return style.tintToken.swiftUIColor.opacity(style.opacity)
        case let .solid(color, opacity):
            return color.opacity(opacity)
        }
    }

    static func keyCenterFraction(midiNote: Int) -> CGFloat? {
        if let whiteIndex = PianoKeyboardTopology.layout.whiteKeyIndexByMIDINote[midiNote] {
            return (CGFloat(whiteIndex) + 0.5) / CGFloat(max(1, whiteKeys.count))
        }
        if let blackCenter = blackKeyCenterFractionByMIDINote[midiNote] {
            return blackCenter
        }
        return nil
    }

    private static let whiteKeys: [WhiteKey] = PianoKeyboardTopology.playableMIDINoteRange.compactMap { midiNote in
        guard let whiteIndex = PianoKeyboardTopology.layout.whiteKeyIndexByMIDINote[midiNote] else { return nil }
        return WhiteKey(midiNote: midiNote, whiteIndex: whiteIndex)
    }

    private static let blackKeys: [BlackKey] = PianoKeyboardTopology.playableMIDINoteRange.compactMap { midiNote in
        guard let leftWhiteIndex = PianoKeyboardTopology.layout.adjacentWhiteKeyIndicesByBlackMIDINote[midiNote]?.left else {
            return nil
        }
        return BlackKey(midiNote: midiNote, leftWhiteIndex: leftWhiteIndex)
    }

    private static let blackKeyCenterFractionByMIDINote: [Int: CGFloat] = Dictionary(
        uniqueKeysWithValues: blackKeys.map { key in
            // Black key is centered at the boundary between leftWhiteIndex and leftWhiteIndex+1.
            (key.midiNote, CGFloat(key.leftWhiteIndex + 1) / CGFloat(max(1, whiteKeys.count)))
        }
    )

    static func keyKind(for midiNote: Int) -> PianoKeyKind {
        PianoKeyboardTopology.keyKind(for: midiNote)
    }

    nonisolated static func highlightKeyViewID(
        isBlackKey: Bool,
        midiNote: Int,
        highlightOccurrenceID: Int?,
        isHighlighted: Bool
    ) -> String {
        let prefix = isBlackKey ? "black" : "white"
        return "\(prefix)-\(midiNote)-\(highlightOccurrenceID ?? 0)-\(isHighlighted)"
    }
}

private struct WhiteKey: Identifiable {
    let midiNote: Int
    let whiteIndex: Int

    var id: Int {
        midiNote
    }
}

private struct BlackKey: Identifiable {
    let midiNote: Int
    let leftWhiteIndex: Int

    var id: Int {
        midiNote
    }
}

#Preview {
    let notes: Set = [21, 60, 61, 72, 108, 130]
    let highlightByMIDINote = Dictionary(uniqueKeysWithValues: notes.map { midiNote in
        let style = PianoGuideHighlightStyle.resolve(
            hand: .right,
            phase: .active,
            keyKind: PianoKeyboard88View.keyKind(for: midiNote)
        )
        return (midiNote, PianoKeyboard88Highlight(fill: .guide(style)))
    })
    PianoKeyboard88View(highlightByMIDINote: highlightByMIDINote)
        .aspectRatio(PianoKeyboard88View.aspectRatio, contentMode: .fit)
        .padding()
}
