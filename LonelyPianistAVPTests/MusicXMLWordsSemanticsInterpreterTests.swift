import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func wordsSemanticsDerivesPedalEventsFromPedAndAsterisk() {
    let interpreter = MusicXMLWordsSemanticsInterpreter()
    let result = interpreter.interpret(
        wordsEvents: [
            MusicXMLWordsEvent(tick: 0, text: "Ped.", scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil)),
            MusicXMLWordsEvent(tick: 480, text: "*", scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil))
        ],
        tempoEvents: []
    )

    #expect(result.derivedPedalEvents.count == 2)
    #expect(result.derivedPedalEvents[0].tick == 0)
    #expect(result.derivedPedalEvents[0].isDown == true)
    #expect(result.derivedPedalEvents[1].tick == 480)
    #expect(result.derivedPedalEvents[1].isDown == false)
}

@Test
func wordsSemanticsDoesNotDerivePedalEventsFromPedSimile() {
    let interpreter = MusicXMLWordsSemanticsInterpreter()
    let result = interpreter.interpret(
        wordsEvents: [
            MusicXMLWordsEvent(
                tick: 0,
                text: "Ped. simile",
                scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil)
            )
        ],
        tempoEvents: []
    )

    #expect(result.derivedPedalEvents.isEmpty == true)
}

@Test
func wordsSemanticsDerivesTempoRampForRitWhenTargetIsSlower() {
    let interpreter = MusicXMLWordsSemanticsInterpreter()
    let result = interpreter.interpret(
        wordsEvents: [
            MusicXMLWordsEvent(tick: 0, text: "rit.", scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil))
        ],
        tempoEvents: [
            MusicXMLTempoEvent(
                tick: 0,
                quarterBPM: 120,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
            MusicXMLTempoEvent(
                tick: 480,
                quarterBPM: 60,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            )
        ]
    )

    #expect(result.derivedTempoRamps == [
        MusicXMLTempoMap.TempoRamp(
            startTick: 0,
            endTick: 480,
            startQuarterBPM: 120,
            endQuarterBPM: 60,
            curve: .easeInOut
        )
    ])
}

@Test
func wordsSemanticsDoesNotDeriveTempoRampForRitWhenTargetIsFaster() {
    let interpreter = MusicXMLWordsSemanticsInterpreter()
    let result = interpreter.interpret(
        wordsEvents: [
            MusicXMLWordsEvent(tick: 0, text: "rit.", scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil))
        ],
        tempoEvents: [
            MusicXMLTempoEvent(
                tick: 0,
                quarterBPM: 60,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
            MusicXMLTempoEvent(
                tick: 480,
                quarterBPM: 120,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            )
        ]
    )

    #expect(result.derivedTempoRamps.isEmpty == true)
}
