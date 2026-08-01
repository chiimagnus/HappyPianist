import Foundation
import Testing
@testable import HappyPianistShared

@Test
func sharedGraphExposesOnlyNonSpatialInputModes() {
    #expect(Set(SharedPracticeInputMode.allCases) == [.bluetoothMIDI, .targetAudio])
}

@Test
func sharedGraphUsesTheInjectedHostBundle() {
    let resources = SharedAppGraph.resources(hostBundle: .main)

    #expect(resources.url(forResource: "missing", withExtension: "resource") == nil)
}
