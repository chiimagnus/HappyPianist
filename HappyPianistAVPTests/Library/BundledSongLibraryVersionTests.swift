import Foundation
import Library
@testable import HappyPianistAVP
import Testing

@Test
func bundledScoreVersionIsStableForSameBuildAndFile() {
    let first = BundledSongLibraryProvider.scoreFileVersionID(
        fileName: "song.musicxml",
        bundleIdentifier: "com.example.app",
        shortVersion: "1.2",
        buildVersion: "34"
    )
    let second = BundledSongLibraryProvider.scoreFileVersionID(
        fileName: "song.musicxml",
        bundleIdentifier: "com.example.app",
        shortVersion: "1.2",
        buildVersion: "34"
    )

    #expect(first == second)
}

@Test
func bundledScoreVersionChangesWithBuildOrFile() {
    let baseline = BundledSongLibraryProvider.scoreFileVersionID(
        fileName: "song.musicxml",
        bundleIdentifier: "com.example.app",
        shortVersion: "1.2",
        buildVersion: "34"
    )
    let nextBuild = BundledSongLibraryProvider.scoreFileVersionID(
        fileName: "song.musicxml",
        bundleIdentifier: "com.example.app",
        shortVersion: "1.2",
        buildVersion: "35"
    )
    let otherFile = BundledSongLibraryProvider.scoreFileVersionID(
        fileName: "other.musicxml",
        bundleIdentifier: "com.example.app",
        shortVersion: "1.2",
        buildVersion: "34"
    )

    #expect(baseline != nextBuild)
    #expect(baseline != otherFile)
}

@Test
func bundledScoreVersionUsesStableSentinelsForMissingBundleValues() {
    let first = BundledSongLibraryProvider.scoreFileVersionID(
        fileName: "song.musicxml",
        bundleIdentifier: nil,
        shortVersion: nil,
        buildVersion: nil
    )
    let second = BundledSongLibraryProvider.scoreFileVersionID(
        fileName: "song.musicxml",
        bundleIdentifier: nil,
        shortVersion: nil,
        buildVersion: nil
    )

    #expect(first == second)
}
