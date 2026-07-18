@testable import HappyPianistAVP
import Testing

@Test
func musicXMLRealisticPlaybackDefaultsAreHardcodedForNoSettingsSwitches() {
    let expressivity = MusicXMLRealisticPlaybackDefaults.expressivityOptions

    #expect(MusicXMLRealisticPlaybackDefaults.practiceScoreOrder == .written)
    #expect(MusicXMLRealisticPlaybackDefaults.referencePlaybackScoreOrder == .performed)
    #expect(PracticePreparationOptions.practice.scoreOrder == .written)
    #expect(PracticePreparationOptions.referencePlayback.scoreOrder == .performed)
    #expect(MusicXMLRealisticPlaybackDefaults.performanceTimingEnabled == true)
    #expect(expressivity.wedgeEnabled == true)
    #expect(expressivity.graceEnabled == true)
    #expect(expressivity.fermataEnabled == true)
    #expect(expressivity.arpeggiateEnabled == true)
    #expect(expressivity.wordsSemanticsEnabled == true)

    let profile = MusicXMLInterpretationProfile.generic
    #expect(profile.id == "generic-score-v1")
    #expect(profile.staccatissimoDurationMultiplier == 0.25)
    #expect(profile.staccatoDurationMultiplier == 0.5)
    #expect(profile.detachedLegatoDurationMultiplier == 0.75)
    #expect(profile.marcatoDurationMultiplier == 0.75)
    #expect(profile.breathGapTicks == 60)
    #expect(profile.caesuraPauseTicks == 240)
    #expect(profile.ornamentSubdivisionTicks == 60)
    #expect(profile.unmeasuredTremoloSubdivisionTicks == 60)
    #expect(profile.glissandoPitchPolicy == .chromatic)
    #expect(profile.fermataExtraDurationMultiplier == 0.5)
}

// Grep gate for local/CI regression checks:
// rg -n 'UserDefaults\.standard\.bool\(forKey:
