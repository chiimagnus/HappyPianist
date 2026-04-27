import Foundation

enum SyntheticAudioFixtures {
    static func sine(midiNote: Int, sampleRate: Double = 48_000, sampleCount: Int = 4096, amplitude: Float = 0.3, attack: Bool = true) -> [Float] {
        let frequency = 440.0 * pow(2.0, Double(midiNote - 69) / 12.0)
        return (0..<sampleCount).map { index in
            let envelope = attackEnvelope(index: index, sampleCount: sampleCount, enabled: attack)
            return envelope * amplitude * Float(sin(2.0 * Double.pi * frequency * Double(index) / sampleRate))
        }
    }

    static func harmonic(midiNote: Int, sampleRate: Double = 48_000, sampleCount: Int = 4096, amplitude: Float = 0.45, attack: Bool = true) -> [Float] {
        let base = 440.0 * pow(2.0, Double(midiNote - 69) / 12.0)
        return (0..<sampleCount).map { index in
            let t = Double(index) / sampleRate
            let envelope = attackEnvelope(index: index, sampleCount: sampleCount, enabled: attack)
            let value = sin(2 * .pi * base * t) * 0.25 + sin(2 * .pi * base * 2 * t) * 0.18 + sin(2 * .pi * base * 3 * t) * 0.12
            return envelope * amplitude * Float(value)
        }
    }

    static func chord(_ notes: [Int], sampleRate: Double = 48_000, sampleCount: Int = 4096, amplitude: Float = 0.45, attack: Bool = true) -> [Float] {
        guard notes.isEmpty == false else { return Array(repeating: 0, count: sampleCount) }
        let signals = notes.map { harmonic(midiNote: $0, sampleRate: sampleRate, sampleCount: sampleCount, amplitude: amplitude, attack: attack) }
        return (0..<sampleCount).map { index in
            signals.reduce(Float.zero) { $0 + $1[index] } / Float(notes.count)
        }
    }

    static func mixed(_ parts: [[Float]]) -> [Float] {
        guard let first = parts.first else { return [] }
        return first.indices.map { index in
            parts.reduce(Float.zero) { $0 + ($1.indices.contains(index) ? $1[index] : 0) } / Float(max(parts.count, 1))
        }
    }

    static func broadbandNoise(sampleCount: Int = 4096, amplitude: Float = 0.04) -> [Float] {
        (0..<sampleCount).map { index in
            let value = sin(Double(index) * 12.9898 + 78.233).truncatingRemainder(dividingBy: 1.0)
            return Float(value) * amplitude
        }
    }

    static func click(sampleCount: Int = 4096, amplitude: Float = 0.8) -> [Float] {
        (0..<sampleCount).map { index in
            index < 8 ? amplitude * (index.isMultiple(of: 2) ? 1 : -1) : 0
        }
    }

    private static func attackEnvelope(index: Int, sampleCount: Int, enabled: Bool) -> Float {
        guard enabled else { return 1 }
        let attackStart = sampleCount / 2
        let attackLength = max(32, sampleCount / 8)
        if index < attackStart { return 0.02 }
        if index >= attackStart + attackLength { return 1 }
        return Float(index - attackStart) / Float(attackLength)
    }
}
