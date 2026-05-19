import Foundation

extension PracticeSessionViewModel: AIPerformancePracticeSessionProtocol {}

extension PracticeSessionViewModel {
    var autoplayTimeline: AutoplayPerformanceTimeline {
        get { stateStore.autoplayTimeline }
        set { stateStore.autoplayTimeline = newValue }
    }

    var tempoMap: MusicXMLTempoMap {
        get { stateStore.tempoMap }
        set { stateStore.tempoMap = newValue }
    }

    var pedalTimeline: MusicXMLPedalTimeline? {
        get { stateStore.pedalTimeline }
        set { stateStore.pedalTimeline = newValue }
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
