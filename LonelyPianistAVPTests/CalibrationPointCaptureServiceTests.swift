import Testing
import simd
@testable import LonelyPianistAVP

@Test
@MainActor
func reticleBecomesReadyAfterStayingStable() {
    let service = CalibrationPointCaptureService()
    let point = SIMD3<Float>(0.1, 0.8, -1.2)

    service.updateReticleFromHandTracking(point, nowUptime: 10.0)
    #expect(service.isReticleReadyToConfirm == false)

    service.updateReticleFromHandTracking(point, nowUptime: 10.05)
    #expect(service.isReticleReadyToConfirm == false)

    service.updateReticleFromHandTracking(point, nowUptime: 10.60)
    #expect(service.isReticleReadyToConfirm)
}

@Test
@MainActor
func reticleReadinessResetsWhenPointMovesTooMuch() {
    let service = CalibrationPointCaptureService()
    let point = SIMD3<Float>(0.1, 0.8, -1.2)
    let movedPoint = point + SIMD3<Float>(0.003, 0, 0)

    service.updateReticleFromHandTracking(point, nowUptime: 1.0)
    service.updateReticleFromHandTracking(point, nowUptime: 1.05)
    service.updateReticleFromHandTracking(point, nowUptime: 1.60)
    #expect(service.isReticleReadyToConfirm)

    service.updateReticleFromHandTracking(movedPoint, nowUptime: 1.62)
    #expect(service.isReticleReadyToConfirm == false)

    service.updateReticleFromHandTracking(movedPoint, nowUptime: 2.20)
    #expect(service.isReticleReadyToConfirm == false)

    service.updateReticleFromHandTracking(movedPoint, nowUptime: 2.80)
    #expect(service.isReticleReadyToConfirm)
}
