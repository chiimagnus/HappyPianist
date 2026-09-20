import Foundation
import Practice

struct CompanionDecisionBackendSelection {
    static var userDefaultsKey: String {
        PracticeSessionSettingsKeys.companionDecisionBackendKind
    }

    static var defaultKind: CompanionDecisionBackendKind {
        .ruleBased
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func selectedKind() -> CompanionDecisionBackendKind? {
        guard let rawValue = userDefaults.string(forKey: Self.userDefaultsKey) else {
            return Self.defaultKind
        }
        return CompanionDecisionBackendKind(rawValue: rawValue)
    }
}
