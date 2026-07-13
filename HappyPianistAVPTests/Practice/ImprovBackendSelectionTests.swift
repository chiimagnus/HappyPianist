import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func invalidBackendPreferenceFallsBackWithoutMutatingStoredValue() throws {
    let suiteName = "ImprovBackendSelectionTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set("removed_backend", forKey: ImprovBackendSelection.userDefaultsKey)
    let selection = ImprovBackendSelection(userDefaults: defaults)

    #expect(selection.selectedKind() == ImprovBackendSelection.defaultKind)
    #expect(defaults.string(forKey: ImprovBackendSelection.userDefaultsKey) == "removed_backend")
}
