import AVFAudio
import AudioToolbox
import Foundation

protocol PracticeNoteAudioPlayerProtocol: AnyObject {
    func play(midiNotes: [Int])
}

final class SoundFontPracticeNoteAudioPlayer: PracticeNoteAudioPlayerProtocol {
    private let engine: AVAudioEngine
    private let sampler: AVAudioUnitSampler
    private let fallback: PracticeNoteAudioPlayerProtocol

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
        channel: UInt8 = 0,
        fallback: PracticeNoteAudioPlayerProtocol = SinePracticeNoteAudioPlayer()
    ) {
        engine = AVAudioEngine()
        sampler = AVAudioUnitSampler()
        self.fallback = fallback
        self.soundFontResourceName = soundFontResourceName
        self.program = program
        self.velocity = velocity
        self.channel = channel

        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
    }

    func play(midiNotes: [Int]) {
        let notes = midiNotes.compactMap { UInt8(exactly: $0) }
        guard notes.isEmpty == false else { return }

        guard ensureReady() else {
            fallback.play(midiNotes: midiNotes)
            return
        }

        stopTask?.cancel()
        stopTask = nil

        for note in playingNotes {
            sampler.stopNote(note, onChannel: channel)
        }
        playingNotes.removeAll()

        for note in notes {
            sampler.startNote(note, withVelocity: velocity, onChannel: channel)
            playingNotes.insert(note)
        }

        stopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard Task.isCancelled == false else { return }
            for note in playingNotes {
                sampler.stopNote(note, onChannel: channel)
            }
            playingNotes.removeAll()
        }
    }

    private func ensureReady() -> Bool {
        guard isReady == false else { return true }

        guard let url = Bundle.main.url(forResource: soundFontResourceName, withExtension: "sf2") else {
            return false
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
            return true
        } catch {
            print("SoundFontPracticeNoteAudioPlayer init failed: \(error.localizedDescription)")
            return false
        }
    }
}

final class SinePracticeNoteAudioPlayer: PracticeNoteAudioPlayerProtocol {
    private let engine: AVAudioEngine
    private let player: AVAudioPlayerNode
    private let format: AVAudioFormat
    private var hasStarted = false

    init(sampleRate: Double = 44_100, channelCount: AVAudioChannelCount = 1) {
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)!

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(midiNotes: [Int]) {
        let notes = midiNotes.filter { (0 ... 127).contains($0) }
        guard notes.isEmpty == false else { return }
        ensureStarted()

        let buffer = makeChordBuffer(midiNotes: notes, durationSeconds: 0.35)
        player.stop()
        player.reset()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        player.play()
    }

    private func ensureStarted() {
        guard hasStarted == false else { return }
        do {
            try engine.start()
            player.play()
            hasStarted = true
        } catch {
            print("SinePracticeNoteAudioPlayer engine start failed: \(error.localizedDescription)")
        }
    }

    private func makeChordBuffer(midiNotes: [Int], durationSeconds: Double) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(max(1, Int(sampleRate * durationSeconds)))
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let frequencies = midiNotes.map(midiToFrequencyHz)
        let fadeSeconds = min(0.02, durationSeconds * 0.15)
        let fadeFrames = max(1, Int(sampleRate * fadeSeconds))
        let totalFrames = Int(frameCount)

        let baseAmplitude = 0.16 / sqrt(Double(max(1, frequencies.count)))

        guard let channel = buffer.floatChannelData?[0] else { return buffer }
        for frame in 0 ..< totalFrames {
            let t = Double(frame) / sampleRate
            var sample = 0.0
            for f in frequencies {
                sample += sin(2.0 * Double.pi * f * t)
            }

            var amp = baseAmplitude
            if frame < fadeFrames {
                amp *= Double(frame) / Double(fadeFrames)
            } else if totalFrames - frame < fadeFrames {
                amp *= Double(totalFrames - frame) / Double(fadeFrames)
            }

            channel[frame] = Float(sample * amp)
        }

        return buffer
    }

    private func midiToFrequencyHz(_ midi: Int) -> Double {
        440.0 * pow(2.0, Double(midi - 69) / 12.0)
    }
}
