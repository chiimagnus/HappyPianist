import Foundation

@MainActor
protocol PracticeSessionEffectHandlerProtocol: AnyObject {
    func handle(effect: PracticeSessionEffect)
}

