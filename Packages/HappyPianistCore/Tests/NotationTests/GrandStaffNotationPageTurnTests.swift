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

@Test(arguments: [0.0, 0.05, 0.25, 0.5, 0.75, 0.95, 1.0])
func pageCurlKeepsSpineFixedAndMirrorsDirectionWithoutFlatMidTurn(progress: Double) {
    let forward = GrandStaffNotationPageCurlGeometry(width: 520, height: 735, gutter: 20, progress: progress, forward: true)
    let backward = GrandStaffNotationPageCurlGeometry(width: 520, height: 735, gutter: 20, progress: progress, forward: false)
    let stable = GrandStaffNotationPageCurlGeometry(width: 520, height: 735, gutter: 20, progress: 0, forward: true)
    #expect(forward.maximumScale == stable.maximumScale)
    #expect(Double(forward.projectedPoint(distance: 0, vertical: 0).x) == forward.spreadWidth / 2)
    #expect(forward.projectedPoint(distance: 0, vertical: 0).y == 0)
    for fraction in [0.0, 0.1, 0.3, 0.6, 0.9, 1.0] {
        let front = forward.projectedPoint(distance: fraction * forward.sheetWidth, vertical: 0)
        let back = backward.projectedPoint(distance: fraction * backward.sheetWidth, vertical: 0)
        #expect(front.x.isFinite && front.y.isFinite)
        #expect(abs(Double(front.x) - forward.spreadWidth / 2) <= forward.sheetWidth * forward.maximumScale)
        #expect(abs(Double(front.y) - forward.height / 2) <= forward.height / 2 * forward.maximumScale)
        #expect(abs(front.x + back.x - forward.spreadWidth) < 0.000001)
        #expect(front.y == back.y)
        let distance = fraction * forward.sheetWidth
        for sourceX in [forward.sheetWidth - distance, forward.sheetWidth + distance] {
            #expect(abs(Double(front.x) - sourceX) <= forward.maximumSampleOffset.width)
        }
        #expect(abs(Double(front.y)) <= forward.maximumSampleOffset.height)
    }
    if progress == 0 || progress == 1 {
        let edge = forward.projectedPoint(distance: forward.sheetWidth, vertical: 0)
        #expect(abs(edge.x - (progress == 0 ? forward.spreadWidth : 0)) < 0.000001)
        #expect(abs(edge.y) < 0.000001)
    } else {
        let middle = forward.projectedPoint(distance: forward.sheetWidth / 2, vertical: 0)
        let edge = forward.projectedPoint(distance: forward.sheetWidth, vertical: 0)
        #expect(abs((middle.x - forward.spreadWidth / 2) - (edge.x - middle.x)) > 0.1)
    }
}

@Test(arguments: [0.05, 0.25, 0.5, 0.75, 0.95])
func pageCurlShaderInverseRecoversBothLivePaperFaces(progress: Double) {
    let curl = GrandStaffNotationPageCurlGeometry(width: 520, height: 735, gutter: 20, progress: progress, forward: true)
    let radius = curl.sheetWidth / curl.curvature
    for fraction in [0.1, 0.3, 0.6, 0.9] {
        let distance = curl.sheetWidth * fraction
        let projected = curl.projectedPoint(distance: distance, vertical: 140)
        let horizontal = projected.x - curl.spreadWidth / 2
        let slope = horizontal / curl.cameraDistance
        let root = (sin(curl.rotation) + horizontal / radius - slope * cos(curl.rotation)) / sqrt(1 + slope * slope)
        #expect(abs(root) <= 1.000001)
        let inverse = asin(min(1, max(-1, root)))
        let candidates = [atan(slope) + inverse, atan(slope) + .pi - inverse]
        let recovered = candidates.contains { angle in
            let recoveredDistance = (angle - curl.rotation) * radius
            let depth = radius * (cos(curl.rotation) - cos(angle))
            let scale = curl.cameraDistance / (curl.cameraDistance - depth)
            let vertical = curl.height / 2 + (projected.y - curl.height / 2) / scale
            return abs(recoveredDistance - distance) < 0.000001 && abs(vertical - 140) < 0.000001
        }
        #expect(recovered)
    }
}
