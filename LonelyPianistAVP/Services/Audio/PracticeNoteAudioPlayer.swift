import AudioToolbox
import AVFAudio
import Foundation

enum PracticeAudioError: LocalizedError, Equatable {
    case soundFontMissing(resourceName: String)
    case soundFontLoadFailed(resourceName: String, detail: String)

    var errorDescription: String? {
        switch self {
            case let .soundFontMissing(resourceName):
                "未找到音色文件 \(resourceName).sf2。请确认它已被添加到 LonelyPianistAVP 的 App 资源中。"
            case let .soundFontLoadFailed(resourceName, detail):
                "音色文件 \(resourceName).sf2 加载失败：\(detail)"
        }
    }
}

protocol PracticeNoteAudioPlayerProtocol: AnyObject {
    func play(midiNotes: [Int]) throws
}

protocol PracticeMIDINoteOutputProtocol: AnyObject {
    func noteOn(midi: Int, velocity: UInt8) throws
    func noteOff(midi: Int)
    func allNotesOff()
}

enum PracticeMIDINoteOutputConstants {
    static let releaseSeconds: TimeInterval = 0.12
}

final class SoundFontPracticeNoteAudioPlayer: PracticeNoteAudioPlayerProtocol, PracticeMIDINoteOutputProtocol {
    private let engine: AVAudioEngine
    private let sampler: AVAudioUnitSampler

    private let soundFontResourceName: String
    private let program: UInt8
    private let velocity: UInt8
    private let channel: UInt8

    private var isReady = false
    private var playingNotes: Set<UInt8> = []
    private var stopTask: Task<Void, Never>?

    init(
        soundFontResourceName: String,
        program: UInt8 = 0,
        velocity: UInt8 = 96,
        channel: UInt8 = 0
    ) {
        engine = AVAudioEngine()
        sampler = AVAudioUnitSampler()
        self.soundFontResourceName = soundFontResourceName
        self.program = program
        self.velocity = velocity
        self.channel = channel

        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
    }

    func play(midiNotes: [Int]) throws {
        let notes = midiNotes.compactMap { UInt8(exactly: $0) }
        guard notes.isEmpty == false else { return }

        try ensureReady()

        stopTask?.cancel()
        stopTask = nil

        allNotesOff()

        for note in notes {
            sampler.startNote(note, withVelocity: velocity, onChannel: channel)
            playingNotes.insert(note)
        }

        stopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard Task.isCancelled == false else { return }
            allNotesOff()
        }
    }

    func noteOn(midi: Int, velocity: UInt8) throws {
        guard let note = UInt8(exactly: midi) else { return }

        try ensureReady()

        stopTask?.cancel()
        stopTask = nil

        sampler.startNote(note, withVelocity: velocity, onChannel: channel)
        playingNotes.insert(note)
    }

    func noteOff(midi: Int) {
        guard let note = UInt8(exactly: midi) else { return }
        guard isReady else { return }

        sampler.stopNote(note, onChannel: channel)
        playingNotes.remove(note)
    }

    func allNotesOff() {
        guard isReady else { return }

        for note in playingNotes {
            sampler.stopNote(note, onChannel: channel)
        }
        playingNotes.removeAll()
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
