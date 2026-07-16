@testable import HappyPianistAVP
import Testing

@Test
func improvSeedResolver_explicitSeedTakesPrecedence() {
    let resolver = ImprovSeedResolver()
    #expect(resolver.resolveSeed(explicitSeed: 42, sessionID: "session-123") == 42)
}

@Test
func improvSeedResolver_sessionIDDerivesStableSeed() {
    let resolver = ImprovSeedResolver()
    #expect(resolver.resolveSeed(explicitSeed: nil, sessionID: "session-123") == 13_387_023_709_829_870_795)
}

@Test
func improvSeedResolver_missingInputsReturnsZero() {
    let resolver = ImprovSeedResolver()
    #expect(resolver.resolveSeed(explicitSeed: nil, sessionID: nil) == 0)
}
