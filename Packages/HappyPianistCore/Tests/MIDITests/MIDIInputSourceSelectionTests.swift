@testable import MIDI
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

@Test
func selectedEndpointDisappearanceReportsUnavailable() {
    let selection = MIDIInputSourceSelection.endpointUniqueID(42)

    #expect(selection.availability(
        connectedSourceCount: 0,
        selectedEndpointIsPresent: false
    ) == .selectedEndpointUnavailable(42))
}

@Test
func allCurrentSourcesReportsAnEmptyConnectedSet() {
    let selection = MIDIInputSourceSelection.allCurrentSources

    #expect(selection.availability(
        connectedSourceCount: 0,
        selectedEndpointIsPresent: false
    ) == .connected(selection: selection, sourceCount: 0))
}
