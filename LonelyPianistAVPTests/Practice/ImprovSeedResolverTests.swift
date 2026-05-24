@testable import LonelyPianistAVP
import Testing

@Test
func improvSeedResolver_explicitSeedTakesPrecedence() {
    let resolver = ImprovSeedResolver()
    #expect(resolver.resolveSeed(explicitSeed: 42, sessionID: "session-123") == 42)
}

@Test
func improvSeedResolver_sessionIDDerivesStableSeed() {
    let resolver = ImprovSeedResolver()
    #expect(resolver.resolveSeed(explicitSeed: nil, sessionID: "session-123") == 13387023709829870795)
}

@Test
func improvSeedResolver_missingInputsReturnsZero() {
    let resolver = ImprovSeedResolver()
    #expect(resolver.resolveSeed(explicitSeed: nil, sessionID: nil) == 0)
}

