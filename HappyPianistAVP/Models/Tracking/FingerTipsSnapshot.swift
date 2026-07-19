import simd

struct HandTips: Equatable {
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

    subscript(_ finger: TrackedFinger) -> SIMD3<Float>? {
        get {
            switch finger {
            case .thumb: thumb
            case .index: index
            case .middle: middle
            case .ring: ring
            case .little: little
            }
        }
        set {
            switch finger {
            case .thumb: thumb = newValue
            case .index: index = newValue
            case .middle: middle = newValue
            case .ring: ring = newValue
            case .little: little = newValue
            }
        }
    }

    func forEachFinger(
        hand: TrackedHandSide,
        _ body: (TrackedFingerID, SIMD3<Float>) -> Void
    ) {
        if let thumb { body(TrackedFingerID(hand: hand, finger: .thumb), thumb) }
        if let index { body(TrackedFingerID(hand: hand, finger: .index), index) }
        if let middle { body(TrackedFingerID(hand: hand, finger: .middle), middle) }
        if let ring { body(TrackedFingerID(hand: hand, finger: .ring), ring) }
        if let little { body(TrackedFingerID(hand: hand, finger: .little), little) }
    }
}

struct FingerTipsSnapshot: Equatable {
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

    func position(for id: TrackedFingerID) -> SIMD3<Float>? {
        self[id.hand][id.finger]
    }

    func forEachFinger(_ body: (TrackedFingerID, SIMD3<Float>) -> Void) {
        left.forEachFinger(hand: .left, body)
        right.forEachFinger(hand: .right, body)
    }

    init(
        left: HandTips = HandTips(),
        right: HandTips = HandTips()
    ) {
        self.left = left
        self.right = right
    }
}
