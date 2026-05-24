import ImprovProtocol
@testable import LonelyPianistAVP
import Testing

@Test
func performanceRNNEventCodec_velocityBinMapping() {
    #expect(PerformanceRNNEventCodec.velocityToBin(1) == 1)
    #expect(PerformanceRNNEventCodec.velocityToBin(4) == 1)
    #expect(PerformanceRNNEventCodec.velocityToBin(5) == 2)
    #expect(PerformanceRNNEventCodec.velocityToBin(80) == 20)
    #expect(PerformanceRNNEventCodec.velocityToBin(127) == 32)

    #expect(PerformanceRNNEventCodec.binToVelocity(1) == 1)
    #expect(PerformanceRNNEventCodec.binToVelocity(20) == 77)
    #expect(PerformanceRNNEventCodec.binToVelocity(32) == 125)
}

@Test
func performanceRNNEventCodec_encodesArpeggioAsGoldenEventIDs() {
    let notes = [
        ImprovDialogueNote(note: 60, velocity: 80, time: 0.0, duration: 0.5),
        ImprovDialogueNote(note: 64, velocity: 80, time: 0.5, duration: 0.5),
        ImprovDialogueNote(note: 67, velocity: 80, time: 1.0, duration: 0.5),
    ]

    let codec = PerformanceRNNEventCodec()
    let eventIDs = codec.encode(notes: notes)

    #expect(eventIDs == [375, 60, 305, 188, 64, 305, 192, 67, 305, 195])
}

@Test
func performanceRNNEventCodec_encodesChordAsGoldenEventIDs() {
    let notes = [
        ImprovDialogueNote(note: 60, velocity: 80, time: 0.0, duration: 0.75),
        ImprovDialogueNote(note: 64, velocity: 80, time: 0.0, duration: 0.75),
        ImprovDialogueNote(note: 67, velocity: 80, time: 0.0, duration: 0.75),
    ]

    let codec = PerformanceRNNEventCodec()
    let eventIDs = codec.encode(notes: notes)

    #expect(eventIDs == [375, 60, 64, 67, 330, 188, 192, 195])
}

