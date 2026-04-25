import SwiftUI

struct PianoKeyboard88View: View {
    static let aspectRatio: CGFloat = 52.0 / 8.0
    static let minPlayableMIDINote = 21
    static let maxPlayableMIDINote = 108

    let highlightedMIDINotes: Set<Int>
    let fingeringByMIDINote: [Int: String]
    let highlightColorByMIDINote: [Int: Color]

    init(
        highlightedMIDINotes: Set<Int>,
        fingeringByMIDINote: [Int: String] = [:],
        highlightColorByMIDINote: [Int: Color] = [:]
    ) {
        self.highlightedMIDINotes = highlightedMIDINotes
        self.fingeringByMIDINote = fingeringByMIDINote
        self.highlightColorByMIDINote = highlightColorByMIDINote
    }

    var body: some View {
        GeometryReader { proxy in
            let whiteKeyWidth = proxy.size.width / CGFloat(max(1, Self.whiteKeys.count))
            let whiteKeyHeight = proxy.size.height
            let blackKeyWidth = whiteKeyWidth * 0.62
            let blackKeyHeight = whiteKeyHeight * 0.62

            ZStack(alignment: .topLeading) {
                ForEach(Self.whiteKeys) { key in
                    let isHighlighted = isHighlighted(key.midiNote)
                    Rectangle()
                        .fill(whiteKeyFillColor(midiNote: key.midiNote, isHighlighted: isHighlighted))
                        .overlay {
                            Rectangle()
                                .stroke(.black.opacity(0.22), lineWidth: 0.6)
                        }
                        .overlay(alignment: .bottom) {
                            if isHighlighted,
                               let fingering = fingeringByMIDINote[key.midiNote]
                            {
                                Text(fingering)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.black.opacity(0.78))
                                    .padding(.bottom, 10)
                            }
                        }
                        .frame(width: whiteKeyWidth, height: whiteKeyHeight)
                        .offset(x: CGFloat(key.whiteIndex) * whiteKeyWidth)
                }

                ForEach(Self.blackKeys) { key in
                    let isHighlighted = isHighlighted(key.midiNote)
                    Rectangle()
                        .fill(blackKeyFillColor(midiNote: key.midiNote, isHighlighted: isHighlighted))
                        .overlay {
                            Rectangle()
                                .stroke(.white.opacity(0.28), lineWidth: 0.5)
                        }
                        .overlay(alignment: .bottom) {
                            if isHighlighted,
                               let fingering = fingeringByMIDINote[key.midiNote]
                            {
                                Text(fingering)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .padding(.bottom, 6)
                            }
                        }
                        .frame(width: blackKeyWidth, height: blackKeyHeight)
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

    private func isHighlighted(_ midiNote: Int) -> Bool {
        highlightedMIDINotes.contains(midiNote)
    }

    private func whiteKeyFillColor(midiNote: Int, isHighlighted: Bool) -> Color {
        guard isHighlighted else { return .white }
        if let custom = highlightColorByMIDINote[midiNote] {
            return custom.opacity(0.55)
        }
        return .yellow.opacity(0.48)
    }

    private func blackKeyFillColor(midiNote: Int, isHighlighted: Bool) -> Color {
        guard isHighlighted else { return .black.opacity(0.88) }
        if let custom = highlightColorByMIDINote[midiNote] {
            return custom.opacity(0.92)
        }
        return .orange.opacity(0.95)
    }

    static func keyCenterFraction(midiNote: Int) -> CGFloat? {
        if let whiteIndex = whiteIndexByMIDINote[midiNote] {
            return (CGFloat(whiteIndex) + 0.5) / CGFloat(max(1, whiteKeys.count))
        }
        if let blackCenter = blackKeyCenterFractionByMIDINote[midiNote] {
            return blackCenter
        }
        return nil
    }

    private static let playableRange = minPlayableMIDINote ... maxPlayableMIDINote
    private static let blackPitchClasses: Set<Int> = [1, 3, 6, 8, 10]

    private static let whiteKeys: [WhiteKey] = {
        var keys: [WhiteKey] = []
        var whiteIndex = 0

        for midiNote in playableRange {
            guard isBlackKey(midiNote) == false else { continue }
            keys.append(WhiteKey(midiNote: midiNote, whiteIndex: whiteIndex))
            whiteIndex += 1
        }

        return keys
    }()

    private static let whiteIndexByMIDINote: [Int: Int] = Dictionary(
        uniqueKeysWithValues: whiteKeys.map { ($0.midiNote, $0.whiteIndex) }
    )

    private static let blackKeys: [BlackKey] = playableRange.compactMap { midiNote in
        guard isBlackKey(midiNote) else { return nil }
        guard let leftWhiteIndex = whiteIndexByMIDINote[midiNote - 1] else { return nil }
        return BlackKey(midiNote: midiNote, leftWhiteIndex: leftWhiteIndex)
    }

    private static let blackKeyCenterFractionByMIDINote: [Int: CGFloat] = Dictionary(
        uniqueKeysWithValues: blackKeys.map { key in
            // Black key is centered at the boundary between leftWhiteIndex and leftWhiteIndex+1.
            (key.midiNote, CGFloat(key.leftWhiteIndex + 1) / CGFloat(max(1, whiteKeys.count)))
        }
    )

    private static func isBlackKey(_ midiNote: Int) -> Bool {
        blackPitchClasses.contains(midiNote % 12)
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
    PianoKeyboard88View(highlightedMIDINotes: [21, 60, 61, 72, 108, 130])
        .aspectRatio(PianoKeyboard88View.aspectRatio, contentMode: .fit)
        .padding()
}
