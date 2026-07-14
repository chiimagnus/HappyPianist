import simd

enum TrackedHandSide: UInt8, CaseIterable, Sendable {
    case left
    case right
}

enum TrackedFingerTip: UInt8, CaseIterable, Sendable {
    case thumb
    case index
    case middle
    case ring
    case little
    case palm
}

struct FingerTipID: Hashable, Sendable {
    let hand: TrackedHandSide
    let tip: TrackedFingerTip
}

struct HandTips: Equatable, Sendable {
    var thumb: SIMD3<Float>?
    var index: SIMD3<Float>?
    var middle: SIMD3<Float>?
    var ring: SIMD3<Float>?
    var little: SIMD3<Float>?
    var palm: SIMD3<Float>?

    init(
        thumb: SIMD3<Float>? = nil,
        index: SIMD3<Float>? = nil,
        middle: SIMD3<Float>? = nil,
        ring: SIMD3<Float>? = nil,
        little: SIMD3<Float>? = nil,
        palm: SIMD3<Float>? = nil
    ) {
        self.thumb = thumb
        self.index = index
        self.middle = middle
        self.ring = ring
        self.little = little
        self.palm = palm
    }

    subscript(_ tip: TrackedFingerTip) -> SIMD3<Float>? {
        get {
            switch tip {
            case .thumb: thumb
            case .index: index
            case .middle: middle
            case .ring: ring
            case .little: little
            case .palm: palm
            }
        }
        set {
            switch tip {
            case .thumb: thumb = newValue
            case .index: index = newValue
            case .middle: middle = newValue
            case .ring: ring = newValue
            case .little: little = newValue
            case .palm: palm = newValue
            }
        }
    }

    func forEachTrackedTip(
        hand: TrackedHandSide,
        _ body: (FingerTipID, SIMD3<Float>) -> Void
    ) {
        if let thumb { body(FingerTipID(hand: hand, tip: .thumb), thumb) }
        if let index { body(FingerTipID(hand: hand, tip: .index), index) }
        if let middle { body(FingerTipID(hand: hand, tip: .middle), middle) }
        if let ring { body(FingerTipID(hand: hand, tip: .ring), ring) }
        if let little { body(FingerTipID(hand: hand, tip: .little), little) }
        if let palm { body(FingerTipID(hand: hand, tip: .palm), palm) }
    }
}

struct FingerTipsSnapshot: Equatable, Sendable {
    static let empty = FingerTipsSnapshot()

    var left = HandTips()
    var right = HandTips()

    subscript(hand: TrackedHandSide) -> HandTips {
        get {
            switch hand {
            case .left: left
            case .right: right
            }
        }
        set {
            switch hand {
            case .left: left = newValue
            case .right: right = newValue
            }
        }
    }

    func position(for id: FingerTipID) -> SIMD3<Float>? {
        self[id.hand][id.tip]
    }

    func forEachTrackedTip(_ body: (FingerTipID, SIMD3<Float>) -> Void) {
        left.forEachTrackedTip(hand: .left, body)
        right.forEachTrackedTip(hand: .right, body)
    }

    init(
        left: HandTips = HandTips(),
        right: HandTips = HandTips()
    ) {
        self.left = left
        self.right = right
    }
}
