import SwiftUI

struct PreparationNavigationActions {
    var backToTypePicker: @MainActor () -> Void
    var nextToLibrary: @MainActor () -> Void

    static let noop = PreparationNavigationActions(
        backToTypePicker: {},
        nextToLibrary: {}
    )
}

extension EnvironmentValues {
    @Entry var preparationNavigationActions: PreparationNavigationActions = .noop
}
