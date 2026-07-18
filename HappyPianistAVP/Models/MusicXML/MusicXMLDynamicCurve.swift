import Foundation

enum MusicXMLDynamicCurveProvenance: Equatable, Sendable {
    case explicitWedge(
        startSourceID: MusicXMLDirectionSourceID?,
        stopSourceID: MusicXMLDirectionSourceID?,
        targetSourceID: MusicXMLDirectionSourceID?
    )
    case approximation(reason: String)
}

struct MusicXMLDynamicCurve: Equatable, Sendable {
    let startTick: Int
    let endTick: Int
    let startVelocity: Int
    let endVelocity: Int
    let scope: MusicXMLEventScope
    let numberToken: String
    let kind: MusicXMLWedgeKind
    let provenance: MusicXMLDynamicCurveProvenance

    func interpolatedVelocity(at tick: Int) -> Double? {
        guard endTick > startTick,
              startTick <= tick,
              tick <= endTick
        else {
            return nil
        }
        let progress = Double(tick - startTick) / Double(endTick - startTick)
        return Double(startVelocity) + Double(endVelocity - startVelocity) * progress
    }
}

struct MusicXMLVelocityResolution: Equatable, Sendable {
    let baseVelocity: Int
    let curveVelocity: Double?
    let articulationDelta: Int
    let unclampedVelocity: Int
    let velocity: UInt8
    let curve: MusicXMLDynamicCurve?
}
