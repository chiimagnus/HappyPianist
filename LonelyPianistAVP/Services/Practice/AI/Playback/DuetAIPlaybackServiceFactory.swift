import Foundation

@MainActor
final class DuetAIPlaybackServiceFactory {
    private let makeLocalSamplerPlaybackService: @MainActor () -> any PracticeSequencerPlaybackServiceProtocol
    private let makeExternalMIDIPlaybackService: @MainActor (Int32) -> any PracticeSequencerPlaybackServiceProtocol

    private var cachedLocalSampler: (any PracticeSequencerPlaybackServiceProtocol)?
    private var cachedExternalMIDI: [Int32: any PracticeSequencerPlaybackServiceProtocol] = [:]

    init(
        makeLocalSamplerPlaybackService: @escaping @MainActor () -> any PracticeSequencerPlaybackServiceProtocol,
        makeExternalMIDIPlaybackService: @escaping @MainActor (Int32) -> any PracticeSequencerPlaybackServiceProtocol
    ) {
        self.makeLocalSamplerPlaybackService = makeLocalSamplerPlaybackService
        self.makeExternalMIDIPlaybackService = makeExternalMIDIPlaybackService
    }

    func playbackService(for routing: PracticeSoundRoutingSettings) -> any PracticeSequencerPlaybackServiceProtocol {
        switch routing.outputRoute {
        case .localSampler:
            if let cachedLocalSampler { return cachedLocalSampler }
            let service = makeLocalSamplerPlaybackService()
            cachedLocalSampler = service
            return service

        case .externalMIDIDestination:
            guard let destinationUniqueID = routing.midiDestinationUniqueID else {
                if let cachedLocalSampler { return cachedLocalSampler }
                let service = makeLocalSamplerPlaybackService()
                cachedLocalSampler = service
                return service
            }

            if let cached = cachedExternalMIDI[destinationUniqueID] { return cached }
            let service = makeExternalMIDIPlaybackService(destinationUniqueID)
            cachedExternalMIDI[destinationUniqueID] = service
            return service
        }
    }

    func stopAll() {
        cachedLocalSampler?.stop()
        for service in cachedExternalMIDI.values {
            service.stop()
        }
    }
}
