enum TrackedHandSide: UInt8, CaseIterable, Sendable {
    case left
    case right
}

enum TrackedFinger: UInt8, CaseIterable, Sendable {
    case thumb
    case index
    case middle
    case ring
    case little
}

struct TrackedFingerID: Hashable, Sendable {
    let hand: TrackedHandSide
    let finger: TrackedFinger
}
