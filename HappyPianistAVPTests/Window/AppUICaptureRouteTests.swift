import Foundation
@testable import HappyPianistAVP
import Testing

#if DEBUG
    @Test
    func appUICaptureRouteParsesRealWindowDestinations() {
        let songID = UUID(uuid: (17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17))

        #expect(AppUICaptureRoute(arguments: ["app", "--ui-capture", "library"]) == .library)
        #expect(AppUICaptureRoute(arguments: ["app", "--ui-capture", "spatial-library"]) == .spatialLibrary)
        #expect(AppUICaptureRoute(arguments: ["app", "--ui-capture", "spatial-spread"]) == .spatialSpread)
        #expect(AppUICaptureRoute(arguments: [
            "app", "--ui-capture", "practice", "--song-id", songID.uuidString,
        ]) == .practice(songID: songID))
    }

    @Test
    func appUICaptureRouteRejectsIncompleteOrUnknownDestinations() {
        #expect(AppUICaptureRoute(arguments: ["app"]) == nil)
        #expect(AppUICaptureRoute(arguments: ["app", "--ui-capture", "unknown"]) == nil)
        #expect(AppUICaptureRoute(arguments: ["app", "--ui-capture", "practice"]) == nil)
        #expect(AppUICaptureRoute(arguments: [
            "app", "--ui-capture", "practice", "--song-id", "invalid",
        ]) == nil)
    }
#endif
