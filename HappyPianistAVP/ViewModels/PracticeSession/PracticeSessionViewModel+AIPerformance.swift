import Foundation

extension PracticeSessionViewModel: AIPerformancePracticeSessionProtocol {}

extension PracticeSessionViewModel {
    var autoplayTimeline: AutoplayPerformanceTimeline {
        get { stateStore.autoplayTimeline }
        set { stateStore.autoplayTimeline = newValue }
    }

    var tempoMap: MusicXMLTempoMap {
        stateStore.tempoMap
    }

    var autoplayState: PracticeSessionAutoplayState {
        get { stateStore.autoplayState }
        set { stateStore.autoplayState = newValue }
    }

    var isManualReplayPlaying: Bool {
        get { stateStore.isManualReplayPlaying }
        set { stateStore.isManualReplayPlaying = newValue }
    }
}
