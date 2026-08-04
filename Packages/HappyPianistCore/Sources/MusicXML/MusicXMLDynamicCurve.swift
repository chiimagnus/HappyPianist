import Foundation


public enum MusicXMLDynamicCurveProvenance: Equatable {
    case explicitWedge(
        startSourceID: MusicXMLDirectionSourceID?,
        stopSourceID: MusicXMLDirectionSourceID?,
        targetSourceID: MusicXMLDirectionSourceID?
    )
    case approximation(reason: String)
}

public struct MusicXMLDynamicCurve: Equatable {
    public let startTick: Int
    public let endTick: Int
    public let startVelocity: Int
    public let endVelocity: Int
    public let scope: MusicXMLEventScope
    public let numberToken: String
    public let kind: MusicXMLWedgeKind
    public let provenance: MusicXMLDynamicCurveProvenance

    public func interpolatedVelocity(at tick: Int) -> Double? {
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

public struct MusicXMLVelocityResolution: Equatable {
    public let baseVelocity: Int
    public let curveVelocity: Double?
    public let articulationDelta: Int
    public let unclampedVelocity: Int
    public let velocity: UInt8
    public let curve: MusicXMLDynamicCurve?
    public let usesGenericDynamicBaseline: Bool
}
