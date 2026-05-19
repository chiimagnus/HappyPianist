import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
@MainActor
func routerRendersAllPreparationRoutes() {
    let appState = AppState()
    let flowState = FlowState()
    let arGuideViewModel = ARGuideViewModel(appState: appState, flowState: flowState)

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

    #expect(RealAudioPianoMode(makePracticeSessionViewModel: makeViewModel).preparationRoute == .realPiano)
    #expect(BluetoothMIDIPianoMode(makePracticeSessionViewModel: makeViewModel).preparationRoute == .bluetoothMIDI)
    #expect(VirtualPianoMode(makePracticeSessionViewModel: makeViewModel).preparationRoute == .virtualPiano)
}

