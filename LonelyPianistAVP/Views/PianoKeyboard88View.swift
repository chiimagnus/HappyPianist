import SwiftUI

struct PianoKeyboard88View: View {
    static let aspectRatio: CGFloat = 52.0 / 8.0

    let highlightedMIDINotes: Set<Int>
    let fingeringByMIDINote: [Int: String]

    private let playableRange = 21 ... 108
    private let blackPitchClasses: Set<Int> = [1, 3, 6, 8, 10]

    init(highlightedMIDINotes: Set<Int>, fingeringByMIDINote: [Int: String] = [:]) {
        self.highlightedMIDINotes = highlightedMIDINotes
        self.fingeringByMIDINote = fingeringByMIDINote
    }

    private var highlightedInRange: Set<Int> {
        Set(highlightedMIDINotes.filter { playableRange.contains($0) })
    }

    private var whiteKeys: [WhiteKey] {
        var keys: [WhiteKey] = []
        var whiteIndex = 0

        for midiNote in playableRange {
            guard isBlackKey(midiNote) == false else { continue }
            keys.append(WhiteKey(midiNote: midiNote, whiteIndex: whiteIndex))
            whiteIndex += 1
        }

        return keys
    }

    private var blackKeys: [BlackKey] {
        let whiteIndexByMIDINote = Dictionary(uniqueKeysWithValues: whiteKeys.map { ($0.midiNote, $0.whiteIndex) })

        return playableRange.compactMap { midiNote in
            guard isBlackKey(midiNote) else { return nil }
            guard let leftWhiteIndex = whiteIndexByMIDINote[midiNote - 1] else { return nil }
            return BlackKey(midiNote: midiNote, leftWhiteIndex: leftWhiteIndex)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let whiteKeyWidth = proxy.size.width / CGFloat(max(1, whiteKeys.count))
            let whiteKeyHeight = proxy.size.height
            let blackKeyWidth = whiteKeyWidth * 0.62
            let blackKeyHeight = whiteKeyHeight * 0.62

            ZStack(alignment: .topLeading) {
                ForEach(whiteKeys) { key in
                    Rectangle()
                        .fill(highlightedInRange.contains(key.midiNote) ? .yellow.opacity(0.48) : .white)
                        .overlay {
                            Rectangle()
                                .stroke(.black.opacity(0.22), lineWidth: 0.6)
                        }
                        .overlay(alignment: .bottom) {
                            if highlightedInRange.contains(key.midiNote),
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

                ForEach(blackKeys) { key in
                    Rectangle()
                        .fill(highlightedInRange.contains(key.midiNote) ? .orange.opacity(0.95) : .black.opacity(0.88))
                        .overlay {
                            Rectangle()
                                .stroke(.white.opacity(0.28), lineWidth: 0.5)
                        }
                        .overlay(alignment: .bottom) {
                            if highlightedInRange.contains(key.midiNote),
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

    private func isBlackKey(_ midiNote: Int) -> Bool {
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
