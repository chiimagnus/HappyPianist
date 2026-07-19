@testable import HappyPianistAVP
import Testing

struct MusicXMLVelocityResolverTests {
    @Test
    func velocityPrefersNoteOverrideThenSoundThenDirection() {
        let events: [MusicXMLDynamicEvent] = [
            MusicXMLDynamicEvent(
                tick: 0,
                velocity: 60,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil),
                source: .directionDynamics
            ),
            MusicXMLDynamicEvent(
                tick: 0,
                velocity: 80,
                scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil),
                source: .soundDynamicsAttribute
            ),
        ]
        let resolver = MusicXMLVelocityResolver(dynamicEvents: events, defaultVelocity: 96)

        let soundNote = MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            midiNote: 60,
            isRest: false,
            isChord: false,
            staff: 1,
            voice: 1
        )
        #expect(resolver.velocity(for: soundNote) == 80)

        let overrideNote = MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            midiNote: 62,
            isRest: false,
            isChord: false,
            staff: 1,
            voice: 1,
            dynamicsOverrideVelocity: 100
        )
        #expect(resolver.velocity(for: overrideNote) == 100)

        let directionFallbackNote = MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            midiNote: 64,
            isRest: false,
            isChord: false,
            staff: 2,
            voice: 1
        )
        #expect(resolver.velocity(for: directionFallbackNote) == 60)
    }

    @Test
    func velocityInterpolatesWithinWedgeSpanWhenEnabled() {
        let dynamicEvents: [MusicXMLDynamicEvent] = [
            MusicXMLDynamicEvent(
                tick: 0,
                velocity: 60,
                scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil),
                source: .directionDynamics
            ),
            MusicXMLDynamicEvent(
                tick: 480,
                velocity: 100,
                scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil),
                source: .directionDynamics
            ),
        ]
        let wedgeEvents: [MusicXMLWedgeEvent] = [
            MusicXMLWedgeEvent(
                tick: 0,
                kind: .crescendoStart,
                numberToken: "1",
                scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil)
            ),
            MusicXMLWedgeEvent(
                tick: 480,
                kind: .stop,
                numberToken: "1",
                scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil)
            ),
        ]

        let resolver = MusicXMLVelocityResolver(
            dynamicEvents: dynamicEvents,
            wedgeEvents: wedgeEvents,
            wedgeEnabled: true,
            defaultVelocity: 96
        )

        let note = MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 240,
            durationTicks: 480,
            midiNote: 60,
            isRest: false,
            isChord: false,
            staff: 1,
            voice: 1
        )

        #expect(resolver.velocity(for: note) == 80)
    }

    @Test
    func velocityAppliesAccentAndMarcatoBoosts() {
        let resolver = MusicXMLVelocityResolver(dynamicEvents: [], defaultVelocity: 96)

        let accented = MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            midiNote: 60,
            isRest: false,
            isChord: false,
            staff: 1,
            voice: 1,
            articulations: [.accent]
        )
        #expect(resolver.velocity(for: accented) == 106)

        let marcato = MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            midiNote: 62,
            isRest: false,
            isChord: false,
            staff: 1,
            voice: 1,
            articulations: [.marcato]
        )
        #expect(resolver.velocity(for: marcato) == 111)
    }

    @Test
    func velocityUsesLatestTickBeforeScopeAndSourcePrecedenceWithoutArrayOrder() {
        let olderStaffSound = MusicXMLDynamicEvent(
            tick: 0,
            velocity: 90,
            scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil),
            source: .soundDynamicsAttribute
        )
        let newerGlobalDirection = MusicXMLDynamicEvent(
            tick: 240,
            velocity: 70,
            scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil),
            source: .directionDynamics
        )
        let sameTickStaffDirection = MusicXMLDynamicEvent(
            tick: 240,
            velocity: 75,
            scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil),
            source: .directionDynamics
        )
        let sameTickStaffSound = MusicXMLDynamicEvent(
            tick: 240,
            velocity: 80,
            scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil),
            source: .soundDynamicsAttribute
        )
        let note = makeNote(tick: 240, staff: 1, voice: 1)

        let forward = MusicXMLVelocityResolver(
            dynamicEvents: [olderStaffSound, newerGlobalDirection, sameTickStaffDirection, sameTickStaffSound]
        )
        let reversed = MusicXMLVelocityResolver(
            dynamicEvents: [sameTickStaffSound, sameTickStaffDirection, newerGlobalDirection, olderStaffSound]
        )

        #expect(forward.velocity(for: note) == 80)
        #expect(reversed.velocity(for: note) == 80)
    }

    @Test
    func velocityPrefersVoiceScopeAtSameTick() {
        let events = [
            MusicXMLDynamicEvent(
                tick: 0,
                velocity: 70,
                scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: nil),
                source: .directionDynamics
            ),
            MusicXMLDynamicEvent(
                tick: 0,
                velocity: 88,
                scope: MusicXMLEventScope(partID: "P1", staff: 1, voice: 2),
                source: .directionDynamics
            ),
        ]
        let resolver = MusicXMLVelocityResolver(dynamicEvents: events)

        #expect(resolver.velocity(for: makeNote(tick: 0, staff: 1, voice: 2)) == 88)
        #expect(resolver.velocity(for: makeNote(tick: 0, staff: 1, voice: 1)) == 70)
    }

    @Test
    func wedgePairingUsesNumberAndReportsUnclosedEvents() {
        let scope = MusicXMLEventScope(partID: "P1", staff: 1, voice: nil)
        let events = [
            MusicXMLWedgeEvent(tick: 0, kind: .crescendoStart, numberToken: "1", scope: scope),
            MusicXMLWedgeEvent(tick: 120, kind: .diminuendoStart, numberToken: "2", scope: scope),
            MusicXMLWedgeEvent(tick: 480, kind: .stop, numberToken: "1", scope: scope),
            MusicXMLWedgeEvent(tick: 600, kind: .stop, numberToken: "3", scope: scope),
        ]

        let resolver = MusicXMLVelocityResolver(dynamicEvents: [], wedgeEvents: events, wedgeEnabled: true)

        #expect(resolver.wedgeApproximations.map(\.reason).sorted() == [
            "wedge-missing-target-dynamic",
            "wedge-start-without-stop",
            "wedge-stop-without-start",
        ])
    }

    private func makeNote(tick: Int, staff: Int, voice: Int) -> MusicXMLNoteEvent {
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: 1,
            tick: tick,
            durationTicks: 480,
            midiNote: 60,
            isRest: false,
            isChord: false,
            staff: staff,
            voice: voice
        )
    }

}
