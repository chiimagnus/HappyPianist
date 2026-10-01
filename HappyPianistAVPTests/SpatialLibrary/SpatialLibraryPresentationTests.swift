import Foundation
@testable import HappyPianistAVP
import Library
import Notation
import RealityKit
import Testing

struct SpatialLibraryPresentationTests {
    @Test(arguments: [0, 1, 3, 50, 98, 99])
    func visibleSliceIsBoundedAndUsesStableOrderedIdentities(selectedIndex: Int) {
        let identities = (0 ..< 100).map { _ in UUID() }
        let items = SpatialLibraryVisibleSlice.items(orderedEntryIDs: identities, selectedEntryID: identities[selectedIndex])
        #expect(items.count <= 7)
        #expect(Set(items.map(\.id)).count == items.count)
        #expect(items.first?.absoluteIndex == max(0, selectedIndex - 3))
        #expect(items.last?.absoluteIndex == min(99, selectedIndex + 3))
        #expect(items.first(where: { $0.relativeIndex == 0 })?.id == identities[selectedIndex])
        for item in items {
            #expect(item.id == identities[item.absoluteIndex])
            #expect(item.relativeIndex == item.absoluteIndex - selectedIndex)
        }
    }

    @Test func emptyAndReplacedSelectionHaveNoPhantomFolios() {
        #expect(SpatialLibraryVisibleSlice.items(orderedEntryIDs: [], selectedEntryID: UUID()).isEmpty)
        let identities = [UUID(), UUID()]
        let items = SpatialLibraryVisibleSlice.items(orderedEntryIDs: identities, selectedEntryID: UUID())
        #expect(items.map(\.id) == identities)
        #expect(items.map(\.relativeIndex) == [0, 1])
    }

    @Test @MainActor func largeLibraryBrowsingCommitsThroughExistingSelectionOwner() {
        let entries = (0 ..< 30).map { index in
            SongLibraryEntry(id: UUID(), displayName: "Score \(index)", musicXMLFileName: "\(index).musicxml", scoreFileVersionID: UUID(), importedAt: .now, audioFileName: nil)
        }
        let library = SongLibraryViewModelTestHarness.make(index: SongLibraryIndex(entries: entries, lastSelectedEntryID: entries[0].id))
        for _ in 0 ..< 15 {
            if let target = SpatialLibraryBrowseDecision.targetEntryID(orderedEntryIDs: library.entries.map(\.id), selectedEntryID: library.selectedEntryID, direction: .next) {
                library.selectEntry(target)
            }
        }
        #expect(library.selectedEntryID == entries[15].id)
        let visible = SpatialLibraryVisibleSlice.items(orderedEntryIDs: library.entries.map(\.id), selectedEntryID: library.selectedEntryID)
        #expect(visible.contains { $0.id == entries[18].id })
        library.confirmFolio(entries[18].id)
        #expect(library.selectedEntryID == entries[18].id)
        #expect(!library.scorePreview.isOpen)
        #expect(SpatialLibraryBrowseDecision.targetEntryID(orderedEntryIDs: entries.map(\.id), selectedEntryID: entries.last?.id, direction: .next) == nil)
        #expect(SpatialLibraryBrowseDecision.targetEntryID(orderedEntryIDs: entries.map(\.id), selectedEntryID: entries.first?.id, direction: .previous) == nil)
    }

    @Test func tapDoesNotCommitBrowseAndInvalidTranslationIsRejected() {
        #expect(SpatialLibraryBrowseDecision.direction(horizontalTranslation: 0) == nil)
        #expect(SpatialLibraryBrowseDecision.direction(horizontalTranslation: 47) == nil)
        #expect(SpatialLibraryBrowseDecision.direction(horizontalTranslation: -48) == .next)
        #expect(SpatialLibraryBrowseDecision.direction(horizontalTranslation: 48) == .previous)
        #expect(SpatialLibraryBrowseDecision.direction(horizontalTranslation: .nan) == nil)
        #expect(SpatialLibraryBrowseDecision.direction(horizontalTranslation: 100, threshold: 0) == nil)
        #expect(SpatialLibraryBrowseDecision.progress(horizontalTranslation: 400) == 1)
        #expect(SpatialLibraryBrowseDecision.progress(horizontalTranslation: -.infinity) == 0)
    }

    @Test func physicalMetricsUseCanonicalAspectAndSingleUniformScale() throws {
        let metrics = SpatialBookDisplayMetrics.standard
        let aspect = Float(GrandStaffNotationPageGeometry.canonical.spreadWidth / GrandStaffNotationPageGeometry.canonical.height)
        #expect(abs(metrics.spreadWidthMeters / metrics.effectiveSpreadHeightMeters - aspect) < 0.00001)
        let bounds = SIMD3<Float>(1.2 * aspect, 1.2, 0.001)
        let scale = try #require(metrics.uniformScale(renderedBounds: bounds, targetWidthMeters: metrics.spreadWidthMeters, targetHeightMeters: metrics.effectiveSpreadHeightMeters))
        #expect(abs(bounds.x * scale - metrics.spreadWidthMeters) < 0.00001)
        #expect(abs(bounds.y * scale - metrics.effectiveSpreadHeightMeters) < 0.00001)
        #expect(metrics.uniformScale(renderedBounds: .zero, targetWidthMeters: 1, targetHeightMeters: 1) == nil)
        #expect(metrics.uniformScale(renderedBounds: SIMD3<Float>(.nan, 1, 0), targetWidthMeters: 1, targetHeightMeters: 1) == nil)
        #expect(SpatialBookDisplayMetrics(folioHeightMeters: 0.1).effectiveFolioHeightMeters == metrics.minimumReadableHeightMeters)
    }

    @Test func spatialEntryCannotHijackPracticeOrPreparation() {
        #expect(SpatialLibraryLaunchRoute.resolve(hasEntries: false, practiceOwnsLifecycle: false, immersiveSpaceState: .closed, immersiveMode: .library) == .unavailable)
        #expect(SpatialLibraryLaunchRoute.resolve(hasEntries: true, practiceOwnsLifecycle: true, immersiveSpaceState: .open, immersiveMode: .practice) == .returnToPractice)
        #expect(SpatialLibraryLaunchRoute.resolve(hasEntries: true, practiceOwnsLifecycle: true, immersiveSpaceState: .closed, immersiveMode: .library) == .returnToPractice)
        #expect(SpatialLibraryLaunchRoute.resolve(hasEntries: true, practiceOwnsLifecycle: false, immersiveSpaceState: .open, immersiveMode: .calibration) == .returnToPreparation)
        #expect(SpatialLibraryLaunchRoute.resolve(hasEntries: true, practiceOwnsLifecycle: false, immersiveSpaceState: .open, immersiveMode: .practice) == .returnToPreparation)
        #expect(SpatialLibraryLaunchRoute.resolve(hasEntries: true, practiceOwnsLifecycle: false, immersiveSpaceState: .open, immersiveMode: .library) == .alreadyOpen)
        #expect(SpatialLibraryLaunchRoute.resolve(hasEntries: true, practiceOwnsLifecycle: false, immersiveSpaceState: .closed, immersiveMode: .practice) == .enterSpatialLibrary)
    }

    @Test @MainActor func browseSurfaceIsBehindFoliosAndHasRequiredInputComponents() {
        let controller = SpatialLibrarySceneController()
        #expect(controller.interactionEntity.position.z < -SpatialBookDisplayMetrics.standard.depthStepMeters * 2)
        #expect(controller.interactionEntity.components[CollisionComponent.self] != nil)
        #expect(controller.interactionEntity.components[InputTargetComponent.self] != nil)
        controller.reset()
        #expect(!controller.interactionEntity.isEnabled)
    }
}
