import CoreGraphics

struct GrandStaffNotationViewportLayoutService {
    struct Layout: Equatable {
        let size: CGSize
        let context: GrandStaffNotationContext?
        let requiredHeight: CGFloat

        let lineSpacing: CGFloat
        let noteWidth: CGFloat
        let noteHeight: CGFloat

        let contextMinX: CGFloat
        let contextWidth: CGFloat
        let contentMinX: CGFloat
        let contentMaxX: CGFloat

        let trebleTopLineY: CGFloat
        let trebleBottomLineY: CGFloat
        let bassTopLineY: CGFloat
        let bassBottomLineY: CGFloat

        let trebleClefY: CGFloat
        let bassClefY: CGFloat
        let trebleClefFontSize: CGFloat
        let bassClefFontSize: CGFloat
        let keySignatureFontSize: CGFloat
        let timeSignatureFontSize: CGFloat

        func xPosition(_ normalized: Double) -> CGFloat {
            let clamped = max(-0.2, min(1.2, normalized))
            return contentMinX + CGFloat(clamped) * (contentMaxX - contentMinX)
        }

        func yPosition(staffStep: Int, staffNumber: Int) -> CGFloat {
            let bottomLineY = (staffNumber >= 2) ? bassBottomLineY : trebleBottomLineY
            return bottomLineY - CGFloat(staffStep) * lineSpacing / 2
        }
    }

    func makeLayout(
        size: CGSize,
        lineSpacing: CGFloat = 14,
        items: [GrandStaffNotationItem],
        chords: [GrandStaffNotationChord] = [],
        beams: [GrandStaffNotationBeam] = [],
        context: GrandStaffNotationContext?
    ) -> Layout {
        let resolvedLineSpacing = max(8, min(22, lineSpacing))

        let trebleSteps = items.filter { $0.staffNumber <= 1 }.map(\.staffStep)
        let bassSteps = items.filter { $0.staffNumber >= 2 }.map(\.staffStep)

        let minTrebleStep = trebleSteps.min() ?? 0
        let maxTrebleStep = trebleSteps.max() ?? 8
        let minBassStep = bassSteps.min() ?? 0
        let maxBassStep = bassSteps.max() ?? 8

        let trebleExtraAboveUnits = CGFloat(max(0, maxTrebleStep - 8)) * 0.5
        let bassExtraBelowUnits = CGFloat(max(0, -minBassStep)) * 0.5

        let trebleExtraBelowUnits = CGFloat(max(0, -minTrebleStep)) * 0.5
        let bassExtraAboveUnits = CGFloat(max(0, maxBassStep - 8)) * 0.5

        let topPaddingUnits: CGFloat = 2.2
        let bottomPaddingUnits: CGFloat = 1.8
        let staffHeightUnits: CGFloat = 4.0
        let baseInterStaffGapUnits: CGFloat = 2.8
        let interStaffCollisionPadUnits: CGFloat = 1.4

        let requiredInterStaffGapUnits = trebleExtraBelowUnits + bassExtraAboveUnits + interStaffCollisionPadUnits
        let interStaffGapUnits = max(baseInterStaffGapUnits, requiredInterStaffGapUnits)

        let totalHeightUnits =
            topPaddingUnits
            + trebleExtraAboveUnits
            + staffHeightUnits
            + interStaffGapUnits
            + staffHeightUnits
            + bassExtraBelowUnits
            + bottomPaddingUnits

        let noteWidth = resolvedLineSpacing * 1.05
        let noteHeight = resolvedLineSpacing * 0.70

        let contextMinX: CGFloat = 4
        let contextWidth: CGFloat = resolvedLineSpacing * 7.0
        let contentMinX: CGFloat = contextMinX + contextWidth
        let contentMaxX: CGFloat = min(size.width - 18, size.width * 0.96)

        let topPadding = topPaddingUnits * resolvedLineSpacing
        let trebleTopLineY = topPadding + trebleExtraAboveUnits * resolvedLineSpacing
        let trebleBottomLineY = trebleTopLineY + resolvedLineSpacing * 4
        let bassTopLineY = trebleBottomLineY + interStaffGapUnits * resolvedLineSpacing
        let bassBottomLineY = bassTopLineY + resolvedLineSpacing * 4

        let requiredHeight = requiredCanvasHeight(
            lineSpacing: resolvedLineSpacing,
            noteWidth: noteWidth,
            noteHeight: noteHeight,
            size: size,
            items: items,
            chords: chords,
            beams: beams,
            trebleBottomLineY: trebleBottomLineY,
            bassBottomLineY: bassBottomLineY,
            contextMinY: 0,
            contextMaxY: totalHeightUnits * resolvedLineSpacing
        )

        let trebleClefStep = clefAnchorStaffStep(
            signToken: context?.trebleClefSignToken,
            line: context?.trebleClefLine
        )
        let bassClefStep = clefAnchorStaffStep(
            signToken: context?.bassClefSignToken,
            line: context?.bassClefLine
        )

        let trebleClefY = (trebleClefStep != nil)
            ? (trebleBottomLineY - CGFloat(trebleClefStep ?? 4) * resolvedLineSpacing / 2)
            : (trebleBottomLineY - 4 * resolvedLineSpacing / 2)

        let bassClefY = (bassClefStep != nil)
            ? (bassBottomLineY - CGFloat(bassClefStep ?? 4) * resolvedLineSpacing / 2)
            : (bassBottomLineY - 4 * resolvedLineSpacing / 2)

        // Clef glyphs are drawn via Unicode music symbols and can appear optically smaller than staff height
        // when rendered by the system fallback font. Scale them based on staff spacing rather than keeping
        // them close to the notehead size.
        let trebleClefFontSize = resolvedLineSpacing * 3.35
        let bassClefFontSize = resolvedLineSpacing * 2.95
        let keySignatureFontSize = resolvedLineSpacing * 1.25
        let timeSignatureFontSize = resolvedLineSpacing * 1.35

        return Layout(
            size: CGSize(width: size.width, height: requiredHeight),
            context: context,
            requiredHeight: requiredHeight,
            lineSpacing: resolvedLineSpacing,
            noteWidth: noteWidth,
            noteHeight: noteHeight,
            contextMinX: contextMinX,
            contextWidth: contextWidth,
            contentMinX: contentMinX,
            contentMaxX: contentMaxX,
            trebleTopLineY: trebleTopLineY,
            trebleBottomLineY: trebleBottomLineY,
            bassTopLineY: bassTopLineY,
            bassBottomLineY: bassBottomLineY,
            trebleClefY: trebleClefY,
            bassClefY: bassClefY,
            trebleClefFontSize: trebleClefFontSize,
            bassClefFontSize: bassClefFontSize,
            keySignatureFontSize: keySignatureFontSize,
            timeSignatureFontSize: timeSignatureFontSize
        )
    }

    private func requiredCanvasHeight(
        lineSpacing: CGFloat,
        noteWidth: CGFloat,
        noteHeight: CGFloat,
        size: CGSize,
        items: [GrandStaffNotationItem],
        chords: [GrandStaffNotationChord],
        beams: [GrandStaffNotationBeam],
        trebleBottomLineY: CGFloat,
        bassBottomLineY: CGFloat,
        contextMinY: CGFloat,
        contextMaxY: CGFloat
    ) -> CGFloat {
        var minY: CGFloat = contextMinY
        var maxY: CGFloat = contextMaxY

        func yPosition(staffStep: Int, staffNumber: Int) -> CGFloat {
            let bottomLineY = (staffNumber >= 2) ? bassBottomLineY : trebleBottomLineY
            return bottomLineY - CGFloat(staffStep) * lineSpacing / 2
        }

        func xPosition(_ normalized: Double, contentMinX: CGFloat, contentMaxX: CGFloat) -> CGFloat {
            let clamped = max(-0.2, min(1.2, normalized))
            return contentMinX + CGFloat(clamped) * (contentMaxX - contentMinX)
        }

        let contextWidth = lineSpacing * 7.0
        let contentMinX = 4 + contextWidth
        let contentMaxX = min(size.width - 18, size.width * 0.96)

        for item in items {
            let y = yPosition(staffStep: item.staffStep, staffNumber: item.staffNumber)
            minY = min(minY, y - noteHeight * 0.6)
            maxY = max(maxY, y + noteHeight * 0.6)
        }

        // Stem + beam extents: mirror current render rules closely enough to avoid clipping.
        let stemLength = lineSpacing * 3.2
        let minStemLength = lineSpacing * 2.6
        let noteheadClearance = lineSpacing * 0.8
        let beamStrokeWidth = max(2, lineSpacing * 0.42)
        let beamGap = max(1.2, lineSpacing * 0.28)
        let beamStackStride = beamStrokeWidth + beamGap

        let chordsByID = Dictionary(uniqueKeysWithValues: chords.map { ($0.id, $0) })
        let itemsByChordID = Dictionary(grouping: items, by: { $0.chordID ?? "" })

        func stemForChord(_ chord: GrandStaffNotationChord, chordItems: [GrandStaffNotationItem]) -> (start: CGPoint, end: CGPoint) {
            let x = xPosition(chord.xPosition, contentMinX: contentMinX, contentMaxX: contentMaxX)
            let steps = chordItems.map(\.staffStep)
            let staffNumber = chordItems.first?.staffNumber ?? 1
            if chord.stemDirection == .up {
                let topStep = steps.max() ?? 4
                let startY = yPosition(staffStep: topStep, staffNumber: staffNumber)
                let startX = x + noteWidth * 0.46
                return (CGPoint(x: startX, y: startY), CGPoint(x: startX, y: startY - stemLength))
            } else {
                let bottomStep = steps.min() ?? 4
                let startY = yPosition(staffStep: bottomStep, staffNumber: staffNumber)
                let startX = x - noteWidth * 0.46
                return (CGPoint(x: startX, y: startY), CGPoint(x: startX, y: startY + stemLength))
            }
        }

        // Non-beamed chord stems
        let beamedChordIDs = Set(beams.flatMap(\.chordIDs))
        for chord in chords {
            if beamedChordIDs.contains(chord.id) { continue }
            guard chord.noteValue != .whole else { continue }
            guard let chordItems = itemsByChordID[chord.id], chordItems.isEmpty == false else { continue }
            let stem = stemForChord(chord, chordItems: chordItems)
            minY = min(minY, min(stem.start.y, stem.end.y) - beamStrokeWidth)
            maxY = max(maxY, max(stem.start.y, stem.end.y) + beamStrokeWidth)
        }

        // Beamed groups: compute primary + secondary beam y at chord x positions.
        for beam in beams {
            let beamChords = beam.chordIDs.compactMap { chordsByID[$0] }.sorted { $0.xPosition < $1.xPosition }
            guard beamChords.count >= 2 else { continue }

            let direction = beamChords.first?.stemDirection ?? .up
            var stemByChordID: [String: (start: CGPoint, end: CGPoint)] = [:]
            for chord in beamChords {
                guard let chordItems = itemsByChordID[chord.id], chordItems.isEmpty == false else { continue }
                stemByChordID[chord.id] = stemForChord(chord, chordItems: chordItems)
            }
            guard
                let firstChord = beamChords.first,
                let lastChord = beamChords.last,
                let firstStem = stemByChordID[firstChord.id],
                let lastStem = stemByChordID[lastChord.id]
            else { continue }

            let x1 = firstStem.end.x
            let xN = lastStem.end.x
            let span = max(1, abs(xN - x1))
            let rawDeltaY = lastStem.end.y - firstStem.end.y
            let maxDeltaY = lineSpacing * 1.5
            let clampedDeltaY = max(-maxDeltaY, min(maxDeltaY, rawDeltaY))
            let slope = clampedDeltaY / span

            func yOnBeam(at x: CGFloat, offset: CGFloat) -> CGFloat {
                firstStem.end.y + slope * (x - x1) + offset
            }

            var requiredOffset: CGFloat = 0
            for chord in beamChords {
                guard let stem = stemByChordID[chord.id] else { continue }
                let chordBeamY = yOnBeam(at: stem.end.x, offset: 0)
                if direction == .up {
                    let allowedMaxY = stem.start.y - minStemLength
                    if chordBeamY > allowedMaxY { requiredOffset = min(requiredOffset, allowedMaxY - chordBeamY) }
                    let clearanceMaxY = stem.start.y - noteheadClearance
                    if chordBeamY > clearanceMaxY { requiredOffset = min(requiredOffset, clearanceMaxY - chordBeamY) }
                } else {
                    let allowedMinY = stem.start.y + minStemLength
                    if chordBeamY < allowedMinY { requiredOffset = max(requiredOffset, allowedMinY - chordBeamY) }
                    let clearanceMinY = stem.start.y + noteheadClearance
                    if chordBeamY < clearanceMinY { requiredOffset = max(requiredOffset, clearanceMinY - chordBeamY) }
                }
            }

            let primaryY1 = yOnBeam(at: x1, offset: requiredOffset)
            let primaryYN = yOnBeam(at: xN, offset: requiredOffset)
            minY = min(minY, min(primaryY1, primaryYN) - beamStrokeWidth)
            maxY = max(maxY, max(primaryY1, primaryYN) + beamStrokeWidth)

            if beam.beamCount >= 2 {
                for level in 2...beam.beamCount {
                    let stride = CGFloat(level - 1) * beamStackStride
                    let secondaryOffset = (direction == .up) ? (requiredOffset + stride) : (requiredOffset - stride)
                    let y1 = yOnBeam(at: x1, offset: secondaryOffset)
                    let yN = yOnBeam(at: xN, offset: secondaryOffset)
                    minY = min(minY, min(y1, yN) - beamStrokeWidth)
                    maxY = max(maxY, max(y1, yN) + beamStrokeWidth)
                }
            }

            for stem in stemByChordID.values {
                let adjustedEndY = yOnBeam(at: stem.end.x, offset: requiredOffset)
                minY = min(minY, min(stem.start.y, adjustedEndY) - beamStrokeWidth)
                maxY = max(maxY, max(stem.start.y, adjustedEndY) + beamStrokeWidth)
            }
        }

        let padding: CGFloat = lineSpacing * 0.8
        return max(1, (maxY - minY) + padding * 2)
    }

    private func beamCountFor(noteValue: GrandStaffNoteValue) -> Int {
        switch noteValue {
            case .eighth:
                return 1
            case .sixteenth:
                return 2
            case .thirtySecond:
                return 3
            default:
                return 0
        }
    }

    private func clefAnchorStaffStep(signToken: String?, line: Int?) -> Int? {
        if let line, (1...5).contains(line) {
            return (line - 1) * 2
        }

        guard let token = signToken?.uppercased(), token.isEmpty == false else { return nil }
        switch token {
            case "G":
                return 2
            case "F":
                return 6
            case "C":
                return 4
            default:
                return nil
        }
    }
}
