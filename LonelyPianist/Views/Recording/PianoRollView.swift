import SwiftUI

struct PianoRollView: View {
    let take: RecordingTake?
    let playheadSec: TimeInterval?

    private let leftInset: CGFloat = 52
    private let topInset: CGFloat = 16
    private let rowHeight: CGFloat = 14
    private let secondWidth: CGFloat = 90

    var body: some View {
        if let take {
            ScrollView([.horizontal, .vertical]) {
                Canvas { context, size in
                    drawGrid(in: &context, size: size, take: take)
                    drawNotes(in: &context, take: take)
                    drawPlayhead(in: &context, size: size, take: take)
                }
                .frame(width: canvasWidth(for: take), height: canvasHeight(for: take))
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            VStack(spacing: 10) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("No take selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func drawPlayhead(in context: inout GraphicsContext, size: CGSize, take: RecordingTake) {
        guard let playheadSec else { return }
        guard take.durationSec > 0 else { return }

        let clamped = max(0, min(playheadSec, take.durationSec))
        let x = leftInset + (CGFloat(clamped) * secondWidth)
        guard x.isFinite else { return }

        var line = Path()
        line.move(to: CGPoint(x: x, y: topInset))
        line.addLine(to: CGPoint(x: x, y: size.height - 8))
        context.stroke(
            line,
            with: .color(.orange.opacity(0.9)),
            style: StrokeStyle(lineWidth: 2)
        )
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize, take: RecordingTake) {
        let range = noteRange(for: take)
        let background = Path(CGRect(origin: .zero, size: size))
        context.fill(background, with: .color(Color(nsColor: .textBackgroundColor)))

        for second in 0...Int(ceil(max(1, take.durationSec))) {
            let x = leftInset + (CGFloat(second) * secondWidth)
            var line = Path()
            line.move(to: CGPoint(x: x, y: topInset))
            line.addLine(to: CGPoint(x: x, y: size.height - 8))
            context.stroke(line, with: .color(.gray.opacity(second % 4 == 0 ? 0.35 : 0.18)))
        }

        for note in range.lowerBound...range.upperBound {
            let y = yPosition(for: note, range: range)
            var line = Path()
            line.move(to: CGPoint(x: leftInset, y: y))
            line.addLine(to: CGPoint(x: size.width - 8, y: y))
            context.stroke(line, with: .color(.gray.opacity(0.12)))

            if note % 12 == 0 {
                context.draw(
                    Text(MIDINote(note).name)
                        .font(.caption2)
                        .foregroundStyle(.secondary),
                    at: CGPoint(x: 24, y: y - (rowHeight * 0.35))
                )
            }
        }
    }

    private func drawNotes(in context: inout GraphicsContext, take: RecordingTake) {
        let range = noteRange(for: take)
        for recordedNote in take.notes {
            let y = yPosition(for: recordedNote.note, range: range) + 1
            let x = leftInset + (CGFloat(recordedNote.startOffsetSec) * secondWidth)
            let width = max(2, CGFloat(recordedNote.durationSec) * secondWidth)
            let rect = CGRect(x: x, y: y, width: width, height: rowHeight - 2)
            let path = Path(roundedRect: rect, cornerRadius: 3)
            let color: Color = recordedNote.channel == 4 ? .orange : .accentColor
            context.fill(path, with: .color(color.opacity(0.85)))
        }
    }

    private func noteRange(for take: RecordingTake) -> ClosedRange<Int> {
        guard let minNote = take.notes.map(\.note).min(),
              let maxNote = take.notes.map(\.note).max() else {
            return 48...72
        }

        let lower = max(0, minNote - 2)
        let upper = min(127, maxNote + 2)
        return lower...upper
    }

    private func canvasWidth(for take: RecordingTake) -> CGFloat {
        max(860, leftInset + (CGFloat(max(1, take.durationSec)) * secondWidth) + 40)
    }

    private func canvasHeight(for take: RecordingTake) -> CGFloat {
        let range = noteRange(for: take)
        let rows = CGFloat((range.upperBound - range.lowerBound) + 1)
        return max(420, topInset + (rows * rowHeight) + 28)
    }

    private func yPosition(for note: Int, range: ClosedRange<Int>) -> CGFloat {
        let topIndex = range.upperBound - note
        return topInset + (CGFloat(topIndex) * rowHeight)
    }
}
