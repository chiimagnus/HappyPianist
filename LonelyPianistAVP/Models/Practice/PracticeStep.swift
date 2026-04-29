import Foundation

nonisolated struct PracticeStepNote: Equatable, Hashable, Identifiable, Sendable {
    var id: String {
        "\(midiNote)-\(staff ?? -1)-\(voice ?? -1)-\(onTickOffset)"
    }

    let midiNote: Int
    let staff: Int?
    let voice: Int?
    let velocity: UInt8
    let onTickOffset: Int
    let fingeringText: String?

    init(
        midiNote: Int,
        staff: Int?,
        voice: Int? = nil,
        velocity: UInt8 = 96,
        onTickOffset: Int = 0,
        fingeringText: String? = nil
    ) {
        self.midiNote = midiNote
        self.staff = staff
        self.voice = voice
        self.velocity = velocity
        self.onTickOffset = onTickOffset
        self.fingeringText = fingeringText
    }
}

nonisolated struct PracticeStep: Equatable, Identifiable, Sendable {
    var id: Int {
        tick
    }

    let tick: Int
    let notes: [PracticeStepNote]
}

nonisolated struct PracticeStepBuildResult: Equatable, Sendable {
    let steps: [PracticeStep]
    let unsupportedNoteCount: Int
}
