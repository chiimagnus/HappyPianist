import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
@MainActor
func routerRendersAllPreparationRoutes() {
    let appState = AppState()
    let practiceSetupState = PracticeSetupState()
    let arGuideViewModel = ARGuideViewModel(appState: appState, practiceSetupState: practiceSetupState)

    for route in [PianoModePreparationRoute.realPiano, .bluetoothMIDI, .virtualPiano] {
        let router = PianoModePreparationRouterView(route: route, arGuideViewModel: arGuideViewModel)
        _ = router.body
    }

    #expect(true)
}

@Test
@MainActor
func defaultPianoModesExposeExpectedPreparationRoutes() {
    let makeViewModel: @MainActor () -> PracticeSessionViewModel = {
        PracticeSessionViewModel(
            pressDetectionService: PressDetectionService(),
            chordAttemptAccumulator: ChordAttemptAccumulator(),
            sleeper: TaskSleeper()
        )
    }

    #expect(RealAudioPianoMode().preparationRoute == .realPiano)
    #expect(BluetoothMIDIPianoMode().preparationRoute == .bluetoothMIDI)
    #expect(VirtualPianoMode().preparationRoute == .virtualPiano)
}

