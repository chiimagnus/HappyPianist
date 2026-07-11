import Foundation
@testable import HappyPianistAVP
import Testing

@Test
@MainActor
func enterPracticeStepCallsOpenImmersive() async {
    let appState = AppState()
    let practiceSetupState = PracticeSetupState()
    let viewModel = ARGuideViewModel(appState: appState, practiceSetupState: practiceSetupState)

    viewModel.setPracticeVirtualPianoEnabled(true)
    practiceSetupState.setImportedSteps(from: PreparedPractice(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "test"),
        steps: [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
        file: ImportedMusicXMLFile(fileName: "Test", storedURL: URL(fileURLWithPath: "/dev/null"), importedAt: Date()),
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        pedalTimeline: nil,
        fermataTimeline: nil,
        attributeTimeline: nil,
        slurTimeline: nil,
        highlightGuides: [],
        measureSpans: [],
        unsupportedNoteCount: 0
    ))

    var openedIDs: [String] = []
    await viewModel.enterPracticeStep(
        openImmersiveSpace: { id in
            openedIDs.append(id)
            return .opened
        },
        dismissImmersiveSpace: {}
    )

    #expect(openedIDs.count == 1)
}

@Test
@MainActor
func closeImmersiveForStepCallsDismissWhenNotClosed() async {
    let appState = AppState()
    let practiceSetupState = PracticeSetupState()
    let viewModel = ARGuideViewModel(appState: appState, practiceSetupState: practiceSetupState)
    appState.immersiveSpaceState = .open

    var dismissCount = 0
    await viewModel.closeImmersiveForStep(dismissImmersiveSpace: { dismissCount += 1 })
    #expect(dismissCount == 1)
}
