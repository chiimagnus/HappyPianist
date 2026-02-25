import Foundation
import MenuBarDockKit
import Observation

@MainActor
@Observable
final class MenuBarExtraVisibilityStore {
    var isInserted = AppIconDisplayMode.current.showsMenuBarIcon

    @ObservationIgnored private var iconModeObserver: NSObjectProtocol?

    init(notificationCenter: NotificationCenter = .default) {
        iconModeObserver = notificationCenter.addObserver(
            forName: .appIconDisplayModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let isInserted = ((notification.object as? AppIconDisplayMode) ?? AppIconDisplayMode.current).showsMenuBarIcon
            Task { @MainActor [weak self, isInserted] in
                self?.isInserted = isInserted
            }
        }
    }

}
