import Practice

struct GrandStaffNotationPageTurnIdentity: Equatable, Sendable {
    let song: PracticeSongIdentity
    let pageIDs: [String]
    var spreadCount: Int { (pageIDs.count + 1) / 2 }
}

struct GrandStaffNotationPageTurnState: Equatable, Sendable {
    struct Transition: Equatable, Sendable {
        let identity: GrandStaffNotationPageTurnIdentity
        let generation: Int
        let source: Int
        let target: Int
        var isForward: Bool { target > source }
        var frontPage: Int { source * 2 + (isForward ? 1 : 0) }
        var backPage: Int { target * 2 + (isForward ? 0 : 1) }
        var underneathLeft: Int { (isForward ? source : target) * 2 }
        var underneathRight: Int { (isForward ? target : source) * 2 + 1 }
    }

    private(set) var identity: GrandStaffNotationPageTurnIdentity?
    private(set) var target: Int?
    private(set) var generation = 0
    private(set) var transition: Transition?

    mutating func request(identity: GrandStaffNotationPageTurnIdentity, target: Int, animated: Bool) {
        guard (0..<identity.spreadCount).contains(target) else { clear(); return }
        if self.identity == identity, self.target == target {
            if !animated, transition != nil { generation += 1; transition = nil }
            return
        }
        generation += 1
        let source = self.target
        let canTurn = animated && self.identity == identity && transition == nil
        self.identity = identity
        self.target = target
        transition = if canTurn, let source, abs(target - source) == 1 {
            Transition(identity: identity, generation: generation, source: source, target: target)
        } else { nil }
    }

    mutating func complete(_ completed: Transition) {
        guard identity == completed.identity, generation == completed.generation, transition == completed else { return }
        transition = nil
    }

    mutating func clear() {
        generation += 1
        identity = nil
        target = nil
        transition = nil
    }
}

extension GrandStaffNotationPagePlan {
    var turnIdentity: GrandStaffNotationPageTurnIdentity {
        .init(song: input.identity, pageIDs: pages.map(\.id))
    }
}
