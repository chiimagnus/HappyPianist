import Foundation

protocol HarmonicBandEnergyProvidingProtocol: Sendable {
    var rms: Double { get }

    func bandEnergy(centerFrequency: Double, toleranceCents: Double) -> Double
    func surroundingEnergy(centerFrequency: Double, toleranceCents: Double) -> Double
}

enum HarmonicTemplateCandidateRole: String, Equatable, CaseIterable {
    case expected
    case wrongCandidate
    case octaveDebug

    var priority: Int {
        switch self {
        case .expected: 3
        case .wrongCandidate: 2
        case .octaveDebug: 1
        }
    }
}

struct HarmonicPartialTemplate: Equatable {
    let harmonicIndex: Int
    let centerFrequency: Double
    let toleranceCents: Double
    let weight: Double
}

struct HarmonicTemplate: Equatable {
    let midiNote: Int
    let role: HarmonicTemplateCandidateRole
    let partials: [HarmonicPartialTemplate]
}

struct AudioSampleRollingBuffer: Equatable {
    private(set) var capacity: Int
    private var samples: [Float] = []

    init(capacity: Int = 4096) {
        self.capacity = max(1, capacity)
    }

    mutating func setCapacity(_ capacity: Int) {
        self.capacity = max(1, capacity)
        trimToCapacity()
    }

    mutating func append(_ newSamples: [Float]) {
        guard newSamples.isEmpty == false else { return }
        samples.append(contentsOf: newSamples)
        trimToCapacity()
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    func window(size: Int) -> [Float]? {
        guard size > 0, samples.count >= size else { return nil }
        return Array(samples.suffix(size))
    }

    var count: Int {
        samples.count
    }

    private mutating func trimToCapacity() {
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}

struct HarmonicTemplateTuningProfile: Equatable {
    let partialWeights: [Int: Double]
    let partialToleranceCents: [Int: Double]
    let minimumConfidence: Double
    let minimumTonalRatio: Double
    let minimumDominance: Double
    let minimumRMS: Double
    let onsetThreshold: Double
    let lowRegisterMIDINoteCutoff: Int
    let lowRegisterWindowSize: Int
    let defaultWindowSize: Int
    let slowProcessingThresholdMs: Double

    static let lowLatencyDefault = HarmonicTemplateTuningProfile(
        partialWeights: [1: 1.0, 2: 0.70, 3: 0.50, 4: 0.35, 5: 0.25],
        partialToleranceCents: [1: 20, 2: 25, 3: 30, 4: 35, 5: 40],
        minimumConfidence: 0.52,
        minimumTonalRatio: 1.20,
        minimumDominance: 1.05,
        minimumRMS: 0.006,
        onsetThreshold: 0.28,
        lowRegisterMIDINoteCutoff: 48,
        lowRegisterWindowSize: 4096,
        defaultWindowSize: 2048,
        slowProcessingThresholdMs: 30
    )

    func weight(for harmonicIndex: Int) -> Double {
        max(0, partialWeights[harmonicIndex] ?? 0)
    }

    func toleranceCents(for harmonicIndex: Int) -> Double {
        max(1, partialToleranceCents[harmonicIndex] ?? 25)
    }

    var harmonicIndices: [Int] {
        partialWeights.keys.sorted().filter { weight(for: $0) > 0 }
    }

    func preferredWindowSize(for expectedMIDINotes: [Int]) -> Int {
        guard let lowest = expectedMIDINotes.min() else { return defaultWindowSize }
        return lowest <= lowRegisterMIDINoteCutoff ? lowRegisterWindowSize : defaultWindowSize
    }
}

struct HarmonicTemplateProvider {
    func makeTemplates(
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: [Int],
        profile: HarmonicTemplateTuningProfile
    ) -> [HarmonicTemplate] {
        var rolesByNote: [Int: HarmonicTemplateCandidateRole] = [:]
        for note in expectedMIDINotes {
            rolesByNote[note] = .expected
        }
        for note in wrongCandidateMIDINotes {
            if let existingRole = rolesByNote[note],
                existingRole.priority >= HarmonicTemplateCandidateRole.wrongCandidate.priority
            {
                continue
            }
            rolesByNote[note] = .wrongCandidate
        }
        for note in expectedMIDINotes {
            for octaveNote in [note - 12, note + 12] where (21...108).contains(octaveNote) {
                if rolesByNote[octaveNote] == nil {
                    rolesByNote[octaveNote] = .octaveDebug
                }
            }
        }

        return
            rolesByNote
            .map { midiNote, role in
                HarmonicTemplate(
                    midiNote: midiNote,
                    role: role,
                    partials: makePartials(midiNote: midiNote, profile: profile)
                )
            }
            .sorted { lhs, rhs in
                if lhs.role.priority != rhs.role.priority { return lhs.role.priority > rhs.role.priority }
                return lhs.midiNote < rhs.midiNote
            }
    }

    func midiFrequency(midiNote: Int) -> Double {
        440.0 * pow(2.0, Double(midiNote - 69) / 12.0)
    }

    private func makePartials(midiNote: Int, profile: HarmonicTemplateTuningProfile)
        -> [HarmonicPartialTemplate]
    {
        let baseFrequency = midiFrequency(midiNote: midiNote)
        return profile.harmonicIndices.map { harmonicIndex in
            HarmonicPartialTemplate(
                harmonicIndex: harmonicIndex,
                centerFrequency: baseFrequency * Double(harmonicIndex),
                toleranceCents: profile.toleranceCents(for: harmonicIndex),
                weight: profile.weight(for: harmonicIndex)
            )
        }
    }
}
