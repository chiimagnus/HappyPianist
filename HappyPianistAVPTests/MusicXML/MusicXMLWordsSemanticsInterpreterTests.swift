import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func wordsSemanticsDerivesPedalEventsFromPedAndAsterisk() {
    let interpreter = MusicXMLWordsSemanticsInterpreter()
    let result = interpreter.interpret(
        wordsEvents: [
            MusicXMLWordsEvent(tick: 0, text: "Ped.", scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil)),
            MusicXMLWordsEvent(tick: 480, text: "*", scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil)),
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
            ),
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
            MusicXMLWordsEvent(tick: 0, text: "rit.", scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil)),
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
            ),
        ]
    )

    #expect(result.derivedTempoRamps == [
        MusicXMLTempoMap.TempoRamp(
            startTick: 0,
            endTick: 480,
            startQuarterBPM: 120,
            endQuarterBPM: 60
        ),
    ])
}

@Test
func wordsSemanticsDoesNotDeriveTempoRampForRitWhenTargetIsFaster() {
    let interpreter = MusicXMLWordsSemanticsInterpreter()
    let result = interpreter.interpret(
        wordsEvents: [
            MusicXMLWordsEvent(tick: 0, text: "rit.", scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil)),
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
            ),
        ]
    )

    #expect(result.derivedTempoRamps.isEmpty == true)
}

@Test
func wordsSemanticsRecognizesControlledTempoVocabulary() {
    let scope = MusicXMLEventScope(partID: "P1", staff: 1, voice: nil)
    let result = MusicXMLWordsSemanticsInterpreter().interpret(
        wordsEvents: [
            MusicXMLWordsEvent(tick: 0, text: "rallentando", scope: scope),
            MusicXMLWordsEvent(tick: 480, text: "stringendo", scope: scope),
            MusicXMLWordsEvent(tick: 960, text: "tempo primo", scope: scope),
            MusicXMLWordsEvent(tick: 1_440, text: "doppio movimento", scope: scope),
            MusicXMLWordsEvent(tick: 1_920, text: "meno mosso", scope: scope),
        ],
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: scope),
            MusicXMLTempoEvent(tick: 480, quarterBPM: 90, scope: scope),
            MusicXMLTempoEvent(tick: 960, quarterBPM: 130, scope: scope),
            MusicXMLTempoEvent(tick: 2_400, quarterBPM: 80, scope: scope),
        ]
    )

    #expect(result.tempoAnnotations.map(\.kind) == [
        .rallentando,
        .stringendo,
        .tempoPrimo,
        .doppioMovimento,
        .menoMosso,
    ])
    #expect(result.derivedTempoRamps.count == 3)
    #expect(result.derivedTempoEvents.contains { $0.tick == 1_440 && $0.quarterBPM == 260 })
}

@Test
func wordsSemanticsRetainsApproximationWhenRampHasNoExplicitTarget() {
    let scope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
    let result = MusicXMLWordsSemanticsInterpreter().interpret(
        wordsEvents: [MusicXMLWordsEvent(tick: 0, text: "ritardando", scope: scope)],
        tempoEvents: [MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: scope)]
    )

    #expect(result.derivedTempoRamps.isEmpty)
    #expect(result.tempoAnnotations == [
        MusicXMLTempoWordAnnotation(
            sourceID: nil,
            tick: 0,
            text: "ritardando",
            scope: scope,
            kind: .ritardando,
            resolution: .approximation(reason: "tempo-word-missing-slower-explicit-target")
        ),
    ])
}

@Test
func wordsSemanticsATempoRestoresPreTransitionAnchor() {
    let scope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
    let result = MusicXMLWordsSemanticsInterpreter().interpret(
        wordsEvents: [
            MusicXMLWordsEvent(tick: 240, text: "rit.", scope: scope),
            MusicXMLWordsEvent(tick: 960, text: "a tempo", scope: scope),
        ],
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: scope),
            MusicXMLTempoEvent(tick: 720, quarterBPM: 80, scope: scope),
        ]
    )

    #expect(result.derivedTempoEvents == [
        MusicXMLTempoEvent(tick: 960, quarterBPM: 120, scope: scope),
    ])
}
