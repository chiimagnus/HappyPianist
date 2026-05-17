import SwiftUI

struct PreparationNavigationActions {
    var backToTypePicker: @MainActor () -> Void
    var nextToLibrary: @MainActor () -> Void

    static let noop = PreparationNavigationActions(
        backToTypePicker: {},
        nextToLibrary: {}
    )
}

private struct PreparationNavigationActionsKey: EnvironmentKey {
    static let defaultValue = PreparationNavigationActions.noop
}

extension EnvironmentValues {
    var preparationNavigationActions: PreparationNavigationActions {
        get { self[PreparationNavigationActionsKey.self] }
        set { self[PreparationNavigationActionsKey.self] = newValue }
    }
}
