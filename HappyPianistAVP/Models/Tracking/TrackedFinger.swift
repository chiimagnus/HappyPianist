enum TrackedHandSide: UInt8, CaseIterable {
    case left
    case right
}

enum TrackedFinger: UInt8, CaseIterable {
    case thumb
    case index
    case middle
    case ring
    case little
}

struct TrackedFingerID: Hashable {
    let hand: TrackedHandSide
    let finger: TrackedFinger
}
