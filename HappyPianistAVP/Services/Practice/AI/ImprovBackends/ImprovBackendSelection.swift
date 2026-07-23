import Foundation

struct ImprovBackendSelection {
    static var userDefaultsKey: String {
        PracticeSessionSettingsKeys.improvBackendKind
    }

    static var defaultKind: ImprovBackendKind {
        .localCoreMLDuet
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func selectedKind() -> ImprovBackendKind? {
        guard let rawValue = userDefaults.string(forKey: Self.userDefaultsKey) else {
            return Self.defaultKind
        }

        return ImprovBackendKind(rawValue: rawValue)
    }
}
