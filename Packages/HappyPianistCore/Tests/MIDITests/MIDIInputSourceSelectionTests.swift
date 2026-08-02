import MIDI
import Testing

@Test
func allCurrentSourcesSelectionAcceptsEveryEndpoint() {
    #expect(MIDIInputSourceSelection.allCurrentSources.accepts(endpointUniqueID: 1))
    #expect(MIDIInputSourceSelection.allCurrentSources.accepts(endpointUniqueID: -42))
}

@Test
func explicitInputSelectionMatchesOnlyItsStableEndpointID() {
    let selection = MIDIInputSourceSelection.endpointUniqueID(42)

    #expect(selection.accepts(endpointUniqueID: 42))
    #expect(selection.accepts(endpointUniqueID: 7) == false)
}
