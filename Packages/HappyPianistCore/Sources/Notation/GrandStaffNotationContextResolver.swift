import CoreGraphics
import CoreText
import Foundation
import MusicXML

struct GrandStaffNotationContextResolver {
    func context(input: GrandStaffNotationScoreInput, tick: Int) -> GrandStaffNotationContext {
        func staff(_ displayed: Int) -> GrandStaffNotationContext.Staff {
            let source = input.facts.sourceStaff(forDisplayedStaff: displayed)
            let clef = source.flatMap { input.attributeTimeline?.clef(atTick: tick, partID: $0.partID, staffNumber: $0.staff) }
            let key = source.flatMap { input.attributeTimeline?.keySignature(atTick: tick, partID: $0.partID, staffNumber: $0.staff) }
            let meter = source.flatMap { input.attributeTimeline?.timeSignature(atTick: tick, partID: $0.partID, staffNumber: $0.staff) }
            return .init(clefSign: clef?.signToken ?? (displayed == 1 ? "G" : "F"), clefLine: clef?.line ?? (displayed == 1 ? 2 : 4), fifths: key?.fifths ?? 0, meter: meter?.meter.displayText)
        }
        return .init(treble: staff(1), bass: staff(2))
    }
}

struct GrandStaffNotationSignatureLayout: Equatable, Sendable {
    struct Glyph: Equatable, Sendable {
        let token: GrandStaffGlyphToken
        let point: CGPoint
        let scale: Double
    }
    let glyphs: [Glyph]
    let bounds: CGRect
    let width: Double
    var labels: [Label] = []

    struct Label: Equatable, Sendable {
        let text: String
        let point: CGPoint
        let size: Double
        var bounds: CGRect {
            let font = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font]))
            var ascent = CGFloat.zero
            var descent = CGFloat.zero
            var leading = CGFloat.zero
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            return CGRect(x: point.x, y: point.y - (ascent + descent + leading) / 2, width: width, height: ascent + descent + leading)
        }
    }

    static func keySteps(fifths: Int, clef: GrandStaffNotationContext.Staff) -> [Int] {
        let reference = switch clef.clefSign.uppercased() { case "F": 24; case "C": 28; default: 32 }
        let bottom = reference - (clef.clefLine - 1) * 2
        let pitches = fifths > 0 ? [38, 35, 39, 36, 33, 37, 34] : [34, 37, 33, 36, 32, 35, 31]
        return pitches.prefix(abs(max(-7, min(7, fifths)))).map { pitch in
            var step = pitch - bottom
            while step > 9 { step -= 7 }
            while step < -1 { step += 7 }
            return step
        }
    }

    static func make(staff: GrandStaffNotationContext.Staff, staffNumber: Int, x: Double = 0, scale: Double = 1, previousFifths: Int? = nil, includeClef: Bool = true) -> Self {
        let metrics = GrandStaffEngravingMetrics()
        let bottom = staffNumber == 2 ? 8.0 : 0
        var glyphs: [Glyph] = []
        var labels: [Label] = []
        var position = x
        func append(_ token: GrandStaffGlyphToken, y: Double) {
            glyphs.append(.init(token: token, point: CGPoint(x: position, y: y), scale: scale))
        }
        if includeClef {
            if let token = staff.clefGlyph {
                append(token, y: bottom - Double(staff.clefLine - 1))
                position += ((metrics.bounds(for: token)?.width ?? 3) + 0.7) * scale
            } else {
                let label = Label(text: "谱号?", point: CGPoint(x: position, y: bottom - 2), size: scale)
                labels.append(label)
                position = label.bounds.maxX + scale
            }
        }
        func key(_ fifths: Int, token: GrandStaffGlyphToken) {
            for step in keySteps(fifths: fifths, clef: staff) {
                append(token, y: bottom - Double(step) / 2)
                position += 0.78 * scale
            }
        }
        if let previousFifths, previousFifths != 0, previousFifths != staff.fifths {
            key(previousFifths, token: .accidentalNatural)
            position += 0.3 * scale
        }
        key(staff.fifths, token: staff.fifths > 0 ? .accidentalSharp : .accidentalFlat)
        position += 0.8 * scale
        if let meter = staff.meter {
            let parts = meter.split(separator: "/")
            let meterStart = position
            if parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) {
                for (row, digits) in parts.enumerated() {
                    var digitX = meterStart
                    for digit in digits {
                        guard let number = digit.wholeNumberValue, let token = GrandStaffGlyphToken.timeSignatureDigit(number), let bounds = metrics.bounds(for: token) else { continue }
                        let center = bottom - 2 + (row == 0 ? -1 : 1)
                        glyphs.append(.init(token: token, point: CGPoint(x: digitX, y: center + (bounds.minY + bounds.maxY) * scale / 2), scale: scale))
                        digitX += (bounds.width + 0.12) * scale
                    }
                    position = max(position, digitX)
                }
            } else {
                let label = Label(text: meter, point: CGPoint(x: position, y: bottom - 2), size: scale)
                labels.append(label)
                position = label.bounds.maxX
            }
        }
        var bounds = glyphs.reduce(CGRect.null) { result, glyph in
            guard let native = metrics.bounds(for: glyph.token) else { return result }
            return result.union(CGRect(x: glyph.point.x + native.minX * glyph.scale, y: glyph.point.y - native.maxY * glyph.scale, width: native.width * glyph.scale, height: native.height * glyph.scale))
        }
        for label in labels { bounds = bounds.union(label.bounds) }
        return .init(glyphs: glyphs, bounds: bounds, width: max(position, bounds.isNull ? x : bounds.maxX) - x + 1, labels: labels)
    }

    static func inline(_ change: GrandStaffNotationAttributeChange, notation: GrandStaffNotationLayout, musicWidth: Double) -> Self {
        var staff = notation.context?.staff(change.staffNumber) ?? .init(clefSign: change.staffNumber == 1 ? "G" : "F", clefLine: change.staffNumber == 1 ? 2 : 4)
        for previous in notation.attributeChanges.filter({ $0.staffNumber == change.staffNumber && $0.tick <= change.tick }).sorted(by: { $0.tick < $1.tick }) {
            staff = .init(clefSign: previous.clefSignToken ?? staff.clefSign, clefLine: previous.clefLine ?? staff.clefLine, fifths: previous.keySignatureFifths ?? staff.fifths, meter: previous.timeSignatureText ?? staff.meter)
        }
        let signature = GrandStaffNotationContext.Staff(clefSign: staff.clefSign, clefLine: staff.clefLine, fifths: change.keySignatureFifths ?? 0, meter: change.timeSignatureText)
        return make(staff: signature, staffNumber: change.staffNumber, x: change.xPosition * musicWidth - 1, scale: 0.82, previousFifths: change.previousKeySignatureFifths, includeClef: change.clefSignToken != nil)
    }
}
