import AudioToolbox
import AVFAudio
import Foundation

struct PracticeSequencerSequence {
    let midiData: Data
    let durationSeconds: TimeInterval
    let events: [PracticeSequencerMIDIEvent]
    let outputApproximations: [PerformanceOutputApproximation]

    init(
        midiData: Data,
        durationSeconds: TimeInterval,
        events: [PracticeSequencerMIDIEvent],
        outputApproximations: [PerformanceOutputApproximation] = []
    ) {
        self.midiData = midiData
        self.durationSeconds = durationSeconds
        self.events = events
        self.outputApproximations = outputApproximations
    }
}

struct PracticeOneShotNoteOn: Hashable {
    let midiNote: Int
    let velocity: UInt8
}

@MainActor
protocol PracticeSequencerPlaybackServiceProtocol: AnyObject {
    func warmUp() throws
    func stop(resetCommands: [PerformanceTransportCommand])
    func load(sequence: PracticeSequencerSequence) throws
    func play(fromSeconds start: TimeInterval) throws
    func currentSeconds() -> TimeInterval
    func playOneShot(noteOns: [PracticeOneShotNoteOn], durationSeconds: TimeInterval) throws
    func startLiveNotes(midiNotes: Set<Int>) throws
    func stopLiveNotes(midiNotes: Set<Int>)
    func stopAllLiveNotes()
}

@MainActor
final class AVAudioSequencerPracticePlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private let engine: AVAudioEngine
    private let sampler: AVAudioUnitSampler
    private let sequencer: AVAudioSequencer
    private let userDefaults: UserDefaults

    private let soundFontResourceName: String
    private let program: UInt8
    private let velocity: UInt8
    private let channel: UInt8

    private var isReady = false
    private var currentAudioOutputVolume: Float?
    private var volumeObservationTask: Task<Void, Never>?
    private var playingOneShotNotes: Set<UInt8> = []
    private var oneShotStopTask: Task<Void, Never>?
    private var liveNotes: Set<UInt8> = []
    private var noteBySourceEventID: [String: UInt8] = [:]
    private var audioSessionEventTasks: [Task<Void, Never>] = []

    init(
        soundFontResourceName: String,
        userDefaults: UserDefaults = .standard,
        program: UInt8 = 0,
        velocity: UInt8 = 96,
        channel: UInt8 = 0
    ) {
        engine = AVAudioEngine()
        sampler = AVAudioUnitSampler()
        sequencer = AVAudioSequencer(audioEngine: engine)
        self.userDefaults = userDefaults

        self.soundFontResourceName = soundFontResourceName
        self.program = program
        self.velocity = velocity
        self.channel = channel

        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)

        applyAudioOutputVolumeIfNeeded()
        volumeObservationTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                guard let self else { return }
                applyAudioOutputVolumeIfNeeded()
            }
        }
        let notificationCenter = NotificationCenter.default
        audioSessionEventTasks = [
            Task { @MainActor [weak self] in
                for await notification in notificationCenter.notifications(named: AVAudioSession.interruptionNotification) {
                    guard let self,
                          let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                          rawType == AVAudioSession.InterruptionType.began.rawValue
                    else { continue }
                    stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
                }
            },
            Task { @MainActor [weak self] in
                for await _ in notificationCenter.notifications(named: AVAudioSession.routeChangeNotification) {
                    guard let self else { return }
                    stop(resetCommands: PerformanceTransportReducer.fullResetCommands)
                }
            },
        ]
    }

    func warmUp() throws {
        try ensureReady()
    }

    func stop(resetCommands: [PerformanceTransportCommand]) {
        haltPlayback()
        execute(resetCommands)
    }

    func load(sequence: PracticeSequencerSequence) throws {
        try ensureReady()
        applyAudioOutputVolumeIfNeeded()

        haltPlayback()

        try sequencer.load(from: sequence.midiData, options: [])
        noteBySourceEventID = Dictionary(
            sequence.events.compactMap { event -> (String, UInt8)? in
                guard let sourceEventID = event.sourceEventID,
                      case let .noteOn(midi, _) = event.kind,
                      let note = UInt8(exactly: midi)
                else { return nil }
                return (sourceEventID, note)
            },
            uniquingKeysWith: { first, _ in first }
        )
        sequencer.currentPositionInSeconds = 0

        for track in sequencer.tracks {
            track.destinationAudioUnit = sampler
        }

        sequencer.tempoTrack.destinationAudioUnit = sampler
        sequencer.prepareToPlay()
    }

    func play(fromSeconds start: TimeInterval) throws {
        try ensureReady()
        applyAudioOutputVolumeIfNeeded()

        sequencer.currentPositionInSeconds = max(0, start)
        try sequencer.start()
    }

    func currentSeconds() -> TimeInterval {
        sequencer.currentPositionInSeconds
    }

    func playOneShot(noteOns: [PracticeOneShotNoteOn], durationSeconds: TimeInterval) throws {
        let notes = noteOns.compactMap { noteOn -> (note: UInt8, velocity: UInt8)? in
            guard let note = UInt8(exactly: noteOn.midiNote) else { return nil }
            return (note, noteOn.velocity)
        }
        guard notes.isEmpty == false else { return }

        try ensureReady()
        applyAudioOutputVolumeIfNeeded()

        oneShotStopTask?.cancel()
        oneShotStopTask = nil

        stopOneShotNotes()

        for (note, velocity) in notes {
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
        applyAudioOutputVolumeIfNeeded()
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

    private func haltPlayback() {
        oneShotStopTask?.cancel()
        oneShotStopTask = nil
        sequencer.stop()
        playingOneShotNotes.removeAll()
        liveNotes.removeAll()
    }

    private func execute(_ commands: [PerformanceTransportCommand]) {
        guard isReady else { return }
        for command in commands {
            switch command {
            case let .noteOff(eventID):
                guard let note = noteBySourceEventID[eventID.description] else { continue }
                _ = MusicDeviceMIDIEvent(sampler.audioUnit, UInt32(0x80 | channel), UInt32(note), 0, 0)
            case let .controlChange(controller, value):
                _ = MusicDeviceMIDIEvent(
                    sampler.audioUnit,
                    UInt32(0xB0 | channel),
                    UInt32(controller),
                    UInt32(value),
                    0
                )
            case .allNotesOff:
                _ = MusicDeviceMIDIEvent(sampler.audioUnit, UInt32(0xB0 | channel), 123, 0, 0)
            case .allSoundOff:
                _ = MusicDeviceMIDIEvent(sampler.audioUnit, UInt32(0xB0 | channel), 120, 0, 0)
            }
        }
    }

    private func ensureReady() throws {
        func configureSessionBestEffort() {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
        }

        if isReady {
            if engine.isRunning == false {
                configureSessionBestEffort()
                do {
                    applyAudioOutputVolumeIfNeeded()
                    engine.prepare()
                    try engine.start()
                } catch {
                    throw PracticeAudioError.soundFontLoadFailed(
                        resourceName: soundFontResourceName,
                        detail: error.localizedDescription
                    )
                }
            }
            return
        }

        guard let url = Bundle.main.url(forResource: soundFontResourceName, withExtension: "sf2") else {
            throw PracticeAudioError.soundFontMissing(resourceName: soundFontResourceName)
        }

        do {
            configureSessionBestEffort()

            try sampler.loadSoundBankInstrument(
                at: url,
                program: program,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: 0
            )
            applyAudioOutputVolumeIfNeeded()
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

    private func applyAudioOutputVolumeIfNeeded() {
        let volume = AudioOutputVolumeSettings.readAudioOutputVolume(from: userDefaults)
        guard currentAudioOutputVolume != volume else { return }
        currentAudioOutputVolume = volume
        engine.mainMixerNode.outputVolume = volume
    }
}
