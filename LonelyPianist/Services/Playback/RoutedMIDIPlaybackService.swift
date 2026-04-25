import Foundation

@MainActor
final class RoutedMIDIPlaybackService: RoutableMIDIPlaybackServiceProtocol {
    private let samplerPlayback: AVSamplerMIDIPlaybackService
    private let midiOutPlayback: CoreMIDIOutputMIDIPlaybackService
    private let outputService: MIDIOutputServiceProtocol

    private(set) var availableOutputs: [MIDIPlaybackOutputOption] = []
    var selectedOutputID: String = MIDIPlaybackOutputOption.builtInSamplerID {
        didSet {
            applySelectedOutput()
        }
    }

    var onPlaybackFinished: (@Sendable () -> Void)? {
        didSet {
            samplerPlayback.onPlaybackFinished = onPlaybackFinished
            midiOutPlayback.onPlaybackFinished = onPlaybackFinished
        }
    }

    var isPlaying: Bool {
        samplerPlayback.isPlaying || midiOutPlayback.isPlaying
    }

    init(
        samplerPlayback: AVSamplerMIDIPlaybackService,
        midiOutPlayback: CoreMIDIOutputMIDIPlaybackService,
        outputService: MIDIOutputServiceProtocol
    ) {
        self.samplerPlayback = samplerPlayback
        self.midiOutPlayback = midiOutPlayback
        self.outputService = outputService
        refreshAvailableOutputs()
        applySelectedOutput()
    }

    func refreshAvailableOutputs() {
        let destinations = outputService.listDestinations()
        var outputs: [MIDIPlaybackOutputOption] = [
            MIDIPlaybackOutputOption(
                id: MIDIPlaybackOutputOption.builtInSamplerID,
                title: "Built-in Sampler",
                kind: .builtInSampler
            ),
        ]

        outputs.append(
            contentsOf: destinations.map {
                MIDIPlaybackOutputOption(
                    id: MIDIPlaybackOutputOption.destinationID(uniqueID: $0.id),
                    title: $0.name,
                    kind: .midiDestination(uniqueID: $0.id)
                )
            }
        )

        availableOutputs = outputs

        if !availableOutputs.contains(where: { $0.id == selectedOutputID }) {
            selectedOutputID = MIDIPlaybackOutputOption.builtInSamplerID
        }
    }

    func play(take: RecordingTake) throws {
        try play(take: take, fromOffsetSec: 0)
    }

    func play(take: RecordingTake, fromOffsetSec offsetSec: TimeInterval) throws {
        stop()

        switch selectedOutputKind {
            case .builtInSampler:
                try samplerPlayback.play(take: take, fromOffsetSec: offsetSec)
            case .midiDestination:
                try midiOutPlayback.play(take: take, fromOffsetSec: offsetSec)
        }
    }

    func stop() {
        samplerPlayback.stop()
        midiOutPlayback.stop()
    }

    private var selectedOutputKind: MIDIPlaybackOutputOption.Kind {
        availableOutputs.first(where: { $0.id == selectedOutputID })?.kind ?? .builtInSampler
    }

    private func applySelectedOutput() {
        switch selectedOutputKind {
            case .builtInSampler:
                midiOutPlayback.destinationUniqueID = nil
            case let .midiDestination(uniqueID):
                midiOutPlayback.destinationUniqueID = uniqueID
        }
    }
}
