import CoreGraphics
import Foundation

enum SpatialLibraryAttachmentID: Hashable {
    case folio(UUID)
    case spread
    case management
}

struct SpatialLibraryVisibleItem: Equatable, Identifiable {
    let id: UUID
    let absoluteIndex: Int
    let relativeIndex: Int
}

enum SpatialLibraryVisibleSlice {
    static let radius = 3

    static func items(
        orderedEntryIDs: [UUID],
        selectedEntryID: UUID?
    ) -> [SpatialLibraryVisibleItem] {
        guard orderedEntryIDs.isEmpty == false else { return [] }

        let selectedIndex = selectedEntryID
            .flatMap { orderedEntryIDs.firstIndex(of: $0) }
            ?? 0
        let lowerBound = max(0, selectedIndex - radius)
        let upperBound = min(orderedEntryIDs.count - 1, selectedIndex + radius)

        return (lowerBound ... upperBound).map { index in
            SpatialLibraryVisibleItem(
                id: orderedEntryIDs[index],
                absoluteIndex: index,
                relativeIndex: index - selectedIndex
            )
        }
    }
}

enum SpatialLibraryBrowseDirection: Equatable {
    case previous
    case next
}

enum SpatialLibraryBrowseDecision {
    static let commitThreshold: CGFloat = 48

    static func direction(
        horizontalTranslation: CGFloat,
        threshold: CGFloat = commitThreshold
    ) -> SpatialLibraryBrowseDirection? {
        guard horizontalTranslation.isFinite, threshold.isFinite, threshold > 0,
              abs(horizontalTranslation) >= threshold else { return nil }
        return horizontalTranslation < 0 ? .next : .previous
    }

    static func progress(
        horizontalTranslation: CGFloat,
        threshold: CGFloat = commitThreshold
    ) -> CGFloat {
        guard horizontalTranslation.isFinite, threshold.isFinite, threshold > 0 else { return 0 }
        return min(max(horizontalTranslation / threshold, -1), 1)
    }

    static func targetEntryID(
        orderedEntryIDs: [UUID], selectedEntryID: UUID?, direction: SpatialLibraryBrowseDirection
    ) -> UUID? {
        guard !orderedEntryIDs.isEmpty else { return nil }
        let selectedIndex = selectedEntryID.flatMap { orderedEntryIDs.firstIndex(of: $0) } ?? 0
        let targetIndex = direction == .next ? selectedIndex + 1 : selectedIndex - 1
        guard orderedEntryIDs.indices.contains(targetIndex) else { return nil }
        return orderedEntryIDs[targetIndex]
    }
}

enum SpatialLibraryLaunchRoute: Equatable {
    case unavailable
    case enterSpatialLibrary
    case alreadyOpen
    case returnToPractice
    case returnToPreparation

    static func resolve(
        hasEntries: Bool,
        practiceOwnsLifecycle: Bool,
        immersiveSpaceState: AppState.ImmersiveSpaceState,
        immersiveMode: AppState.ImmersiveMode
    ) -> Self {
        guard hasEntries else { return .unavailable }
        if practiceOwnsLifecycle {
            return .returnToPractice
        }
        if immersiveSpaceState == .open {
            return immersiveMode == .library ? .alreadyOpen : .returnToPreparation
        }
        return .enterSpatialLibrary
    }
}
