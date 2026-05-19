import Foundation

@MainActor
protocol PracticeSessionLifecycleProtocol: AnyObject {
    func shutdown()
}

