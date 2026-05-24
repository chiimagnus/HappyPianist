import Foundation

struct ImprovBackendSelection {
    static var userDefaultsKey: String {
        PracticeSessionSettingsKeys.improvBackendKind
    }

    static var defaultKind: ImprovBackendKind {
        .networkBonjourHTTPDuet
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func selectedKind() -> ImprovBackendKind {
        guard let rawValue = userDefaults.string(forKey: Self.userDefaultsKey) else {
            return Self.defaultKind
        }

        if let kind = ImprovBackendKind(rawValue: rawValue) {
            return kind
        }
        userDefaults.set(Self.defaultKind.rawValue, forKey: Self.userDefaultsKey)
        return Self.defaultKind
    }
}
