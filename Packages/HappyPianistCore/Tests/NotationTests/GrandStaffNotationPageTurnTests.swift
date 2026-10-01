import Foundation
@testable import Notation
import Practice
import Testing

@Test
func pageTurnMapsBothFacesAndKeepsOnlyOneFiniteTransition() throws {
    let identity = GrandStaffNotationPageTurnIdentity(song: .init(songID: UUID(), scoreRevision: "turn"), pageIDs: ["a", "b", "c", "d", "e"])
    var state = GrandStaffNotationPageTurnState()
    state.request(identity: identity, target: 0, animated: true)
    #expect(state.transition == nil)
    state.request(identity: identity, target: 1, animated: true)
    let forward = try #require(state.transition)
    #expect(forward.frontPage == 1 && forward.backPage == 2)
    #expect(forward.underneathLeft == 0 && forward.underneathRight == 3)
    state.request(identity: identity, target: 1, animated: true)
    #expect(state.transition == forward)
    state.complete(forward)
    state.request(identity: identity, target: 0, animated: true)
    let backward = try #require(state.transition)
    #expect(backward.frontPage == 2 && backward.backPage == 1)
    #expect(backward.underneathLeft == 0 && backward.underneathRight == 3)
    state.complete(backward)
    state.request(identity: identity, target: 2, animated: true)
    #expect(state.transition == nil)
    state.request(identity: identity, target: 1, animated: true)
    let fromOddLast = try #require(state.transition)
    #expect(fromOddLast.frontPage == 4 && fromOddLast.backPage == 3)
    state.request(identity: identity, target: 2, animated: true)
    #expect(state.transition == nil)
    state.complete(fromOddLast)
    #expect(state.target == 2 && state.transition == nil)
}

@Test
func pageTurnRejectsOldCompletionAfterReplacementResetAndDirectDisplay() throws {
    let identity = GrandStaffNotationPageTurnIdentity(song: .init(songID: UUID(), scoreRevision: "turn"), pageIDs: ["a", "b", "c", "d", "e"])
    var state = GrandStaffNotationPageTurnState()
    state.request(identity: identity, target: 0, animated: true)
    state.request(identity: identity, target: 1, animated: true)
    let old = try #require(state.transition)
    let replacement = GrandStaffNotationPageTurnIdentity(song: .init(songID: identity.song.songID, scoreRevision: "new"), pageIDs: identity.pageIDs)
    state.request(identity: replacement, target: 1, animated: true)
    state.complete(old)
    #expect(state.identity == replacement && state.transition == nil)
    state.request(identity: replacement, target: 0, animated: true)
    let current = try #require(state.transition)
    state.complete(old)
    #expect(state.transition == current)
    state.request(identity: replacement, target: 0, animated: false)
    #expect(state.transition == nil)
    state.complete(current)
    state.clear()
    state.request(identity: replacement, target: 0, animated: true)
    state.complete(current)
    #expect(state.target == 0 && state.transition == nil)
    let generation = state.generation
    for index in 0..<500 {
        state.request(identity: replacement, target: index % 3, animated: true)
        #expect(state.transition.map { abs($0.target - $0.source) == 1 } ?? true)
    }
    #expect(state.generation > generation)
    state.request(identity: replacement, target: -1, animated: true)
    #expect(state.target == nil)
    state.request(identity: replacement, target: 3, animated: true)
    #expect(state.identity == nil)
}

@Test
func pageTurnPlanReplacementAndOddLastPageNeverReusePreviousSheets() throws {
    let song = PracticeSongIdentity(songID: UUID(), scoreRevision: "same-score")
    let identity = GrandStaffNotationPageTurnIdentity(song: song, pageIDs: ["a", "b", "c", "d", "e"])
    var state = GrandStaffNotationPageTurnState()
    state.request(identity: identity, target: 1, animated: true)
    state.request(identity: identity, target: 2, animated: true)
    let last = try #require(state.transition)
    #expect(last.frontPage == 3 && last.backPage == 4 && last.underneathRight == 5)
    #expect(!identity.pageIDs.indices.contains(last.underneathRight))
    let replacement = GrandStaffNotationPageTurnIdentity(song: song, pageIDs: ["new-a", "new-b", "new-c", "new-d", "new-e"])
    state.request(identity: replacement, target: 2, animated: true)
    state.complete(last)
    #expect(state.identity == replacement && state.target == 2 && state.transition == nil)
    state.request(identity: .init(song: song, pageIDs: []), target: 0, animated: true)
    #expect(state.identity == nil && state.target == nil && state.transition == nil)
}
