import AudioToolbox
import AVFAudio
import Foundation

nonisolated struct PracticeSequencerSequence {
    let midiData: Data
    let durationSeconds: TimeInterval
}

@MainActor
protocol PracticeSequencerPlaybackServiceProtocol: AnyObject {
    func warmUp() throws
    func stop()
    func load(sequence: PracticeSequencerSequence) throws
    func play(fromSeconds start: TimeInterval) throws
    func currentSeconds() -> TimeInterval
    func playOneShot(midiNotes: [Int], durationSeconds: TimeInterval) throws
    func startLiveNotes(midiNotes: Set<Int>) throws
    func stopLiveNotes(midiNotes: Set<Int>)
    func stopAllLiveNotes()
}

@MainActor
final class AVAudioSequencerPracticePlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private let engine: AVAudioEngine
    private let sampler: AVAudioUnitSampler
    private let sequencer: AVAudioSequencer

    private let soundFontResourceName: String
    private let program: UInt8
    private let velocity: UInt8
    private let channel: UInt8

    private var isReady = false
    private var playingOneShotNotes: Set<UInt8> = []
    private var oneShotStopTask: Task<Void, Never>?
    private var liveNotes: Set<UInt8> = []

    init(
        soundFontResourceName: String,
        program: UInt8 = 0,
        velocity: UInt8 = 96,
        channel: UInt8 = 0
    ) {
        engine = AVAudioEngine()
        sampler = AVAudioUnitSampler()
        sequencer = AVAudioSequencer(audioEngine: engine)

        self.soundFontResourceName = soundFontResourceName
        self.program = program
        self.velocity = velocity
        self.channel = channel

        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
    }

    func warmUp() throws {
        try ensureReady()
    }

    func stop() {
        oneShotStopTask?.cancel()
        oneShotStopTask = nil

        sequencer.stop()
        allNotesOff()
        stopOneShotNotes()
        stopAllLiveNotes()
    }

    func load(sequence: PracticeSequencerSequence) throws {
        try ensureReady()

        stop()

        try sequencer.load(from: sequence.midiData, options: [])
        sequencer.currentPositionInSeconds = 0

        for track in sequencer.tracks {
            track.destinationAudioUnit = sampler
        }

        sequencer.tempoTrack.destinationAudioUnit = sampler
        sequencer.prepareToPlay()
    }

    func play(fromSeconds start: TimeInterval) throws {
        try ensureReady()

        sequencer.currentPositionInSeconds = max(0, start)
        try sequencer.start()
    }

    func currentSeconds() -> TimeInterval {
        sequencer.currentPositionInSeconds
    }

    func playOneShot(midiNotes: [Int], durationSeconds: TimeInterval) throws {
        let notes = midiNotes.compactMap { UInt8(exactly: $0) }
        guard notes.isEmpty == false else { return }

        try ensureReady()

        oneShotStopTask?.cancel()
        oneShotStopTask = nil

        stopOneShotNotes()

        for note in notes {
            sampler.startNote(note, withVelocity: velocity, onChannel: channel)
            playingOneShotNotes.insert(note)
        }

        oneShotStopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(max(0, durationSeconds)))
            guard Task.isCancelled == false else { return }
            stopOneShotNotes()
        }
    }

    func startLiveNotes(midiNotes: Set<Int>) throws {
        try ensureReady()
        for midiNote in midiNotes {
            guard let note = UInt8(exactly: midiNote), liveNotes.contains(note) == false else { continue }
            sampler.startNote(note, withVelocity: velocity, onChannel: channel)
            liveNotes.insert(note)
        }
    }

    func stopLiveNotes(midiNotes: Set<Int>) {
        guard isReady else { return }
        for midiNote in midiNotes {
            guard let note = UInt8(exactly: midiNote), liveNotes.contains(note) else { continue }
            sampler.stopNote(note, onChannel: channel)
            liveNotes.remove(note)
        }
    }

    func stopAllLiveNotes() {
        guard isReady else { return }
        for note in liveNotes {
            sampler.stopNote(note, onChannel: channel)
        }
        liveNotes.removeAll()
    }

    private func stopOneShotNotes() {
        guard isReady else { return }

        for note in playingOneShotNotes {
            sampler.stopNote(note, onChannel: channel)
        }
        playingOneShotNotes.removeAll()
    }

    private func allNotesOff() {
        guard isReady else { return }
        _ = MusicDeviceMIDIEvent(sampler.audioUnit, UInt32(0xB0 | channel), 123, 0, 0)
    }

    private func ensureReady() throws {
        guard isReady == false else { return }

        guard let url = Bundle.main.url(forResource: soundFontResourceName, withExtension: "sf2") else {
            throw PracticeAudioError.soundFontMissing(resourceName: soundFontResourceName)
        }

        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: program,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: 0
            )
            engine.prepare()
            try engine.start()
            isReady = true
        } catch {
            throw PracticeAudioError.soundFontLoadFailed(
                resourceName: soundFontResourceName,
                detail: error.localizedDescription
            )
        }
    }
}
