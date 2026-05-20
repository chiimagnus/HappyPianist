import Foundation

struct ImprovBackendSelection {
    static let userDefaultsKey = "practiceImprovBackendKind"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func selectedKind() -> ImprovBackendKind {
        guard let rawValue = userDefaults.string(forKey: Self.userDefaultsKey),
              let kind = ImprovBackendKind(rawValue: rawValue)
        else {
            return .networkBonjourHTTP
        }
        return kind
    }
}
