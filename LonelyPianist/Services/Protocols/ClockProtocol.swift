import Foundation

protocol ClockProtocol {
    func now() -> Date
}

struct SystemClock: ClockProtocol {
    func now() -> Date {
        Date()
    }
}
