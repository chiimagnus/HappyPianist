import Foundation
@testable import LonelyPianistAVP
import simd
import Testing

@Test
func pressDetectionReturnsEmptyWhenKeyboardGeometryIsNil() {
    let service = PressDetectionService(cooldownSeconds: 0.0)
    let pressed = service.detectPressedNotes(
        fingerTips: ["index": SIMD3<Float>(0.0, 0.0, 0.0)],
        keyboardGeometry: nil,
        at: Date(timeIntervalSince1970: 0)
    )
    #expect(pressed.isEmpty)
}

@Test
func pressDetectionTriggersWhenFingerCrossesWhiteKeySurfaceUsingKeyboardGeometry() throws {
    let service = PressDetectionService(cooldownSeconds: 0.0)

    let frame = try #require(KeyboardFrame(
        a0World: SIMD3<Float>(0.0, 0.5, 0.0),
        c8World: SIMD3<Float>(1.0, 0.5, 0.0),
        planeHeight: 0.5
    ))

    let whiteKey = PianoKeyGeometry(
        midiNote: 60,
        kind: .white,
        localCenter: SIMD3<Float>(0.0, -0.015, -0.07),
        localSize: SIMD3<Float>(0.02, 0.03, 0.14),
        surfaceLocalY: 0.0,
        hitCenterLocal: SIMD3<Float>(0.0, -0.015, -0.07),
        hitSizeLocal: SIMD3<Float>(0.02, 0.03, 0.14),
        beamFootprintCenterLocal: SIMD3<Float>(0.0, 0.0, -0.07),
        beamFootprintSizeLocal: SIMD2<Float>(0.018, 0.11)
    )

    let geometry = PianoKeyboardGeometry(frame: frame, keys: [whiteKey])

    let prevLocal = SIMD3<Float>(0.0, 0.05, -0.07)
    let currLocal = SIMD3<Float>(0.0, -0.01, -0.07)
    let prevWorld = PressDetectionService.transformPoint(frame.worldFromKeyboard, prevLocal)
    let currWorld = PressDetectionService.transformPoint(frame.worldFromKeyboard, currLocal)

    _ = service.detectPressedNotes(
        fingerTips: ["index": prevWorld],
        keyboardGeometry: geometry,
        at: Date(timeIntervalSince1970: 0)
    )

    let pressed = service.detectPressedNotes(
        fingerTips: ["index": currWorld],
        keyboardGeometry: geometry,
        at: Date(timeIntervalSince1970: 1)
    )

    #expect(pressed == [60])
}

@Test
func pressDetectionTriggersWhenFingerCrossesBlackKeySurfaceUsingKeyboardGeometry() throws {
    let service = PressDetectionService(cooldownSeconds: 0.0)

    let frame = try #require(KeyboardFrame(
        a0World: SIMD3<Float>(0.0, 0.5, 0.0),
        c8World: SIMD3<Float>(1.0, 0.5, 0.0),
        planeHeight: 0.5
    ))

    let blackKey = PianoKeyGeometry(
        midiNote: 61,
        kind: .black,
        localCenter: SIMD3<Float>(0.0, 0.0, -0.09),
        localSize: SIMD3<Float>(0.012, 0.03, 0.086),
        surfaceLocalY: 0.015,
        hitCenterLocal: SIMD3<Float>(0.0, 0.0, -0.09),
        hitSizeLocal: SIMD3<Float>(0.012, 0.03, 0.086),
        beamFootprintCenterLocal: SIMD3<Float>(0.0, 0.015, -0.09),
        beamFootprintSizeLocal: SIMD2<Float>(0.011, 0.07)
    )

    let geometry = PianoKeyboardGeometry(frame: frame, keys: [blackKey])

    let prevLocal = SIMD3<Float>(0.0, 0.03, -0.09)
    let currLocal = SIMD3<Float>(0.0, 0.01, -0.09)
    let prevWorld = PressDetectionService.transformPoint(frame.worldFromKeyboard, prevLocal)
    let currWorld = PressDetectionService.transformPoint(frame.worldFromKeyboard, currLocal)

    _ = service.detectPressedNotes(
        fingerTips: ["index": prevWorld],
        keyboardGeometry: geometry,
        at: Date(timeIntervalSince1970: 0)
    )

    let pressed = service.detectPressedNotes(
        fingerTips: ["index": currWorld],
        keyboardGeometry: geometry,
        at: Date(timeIntervalSince1970: 1)
    )

    #expect(pressed == [61])
}

@Test
func pressDetectionPrefersBlackKeyOverWhiteKeyWhenBothWouldBeHit() throws {
    let service = PressDetectionService(cooldownSeconds: 0.0)

    let frame = try #require(KeyboardFrame(
        a0World: SIMD3<Float>(0.0, 0.5, 0.0),
        c8World: SIMD3<Float>(1.0, 0.5, 0.0),
        planeHeight: 0.5
    ))

    let whiteKey = PianoKeyGeometry(
        midiNote: 60,
        kind: .white,
        localCenter: SIMD3<Float>(0.0, -0.015, -0.07),
        localSize: SIMD3<Float>(0.02, 0.03, 0.14),
        surfaceLocalY: 0.0,
        hitCenterLocal: SIMD3<Float>(0.0, -0.015, -0.07),
        hitSizeLocal: SIMD3<Float>(0.02, 0.03, 0.14),
        beamFootprintCenterLocal: SIMD3<Float>(0.0, 0.0, -0.07),
        beamFootprintSizeLocal: SIMD2<Float>(0.018, 0.11)
    )
    let blackKey = PianoKeyGeometry(
        midiNote: 61,
        kind: .black,
        localCenter: SIMD3<Float>(0.0, 0.0, -0.09),
        localSize: SIMD3<Float>(0.012, 0.03, 0.086),
        surfaceLocalY: 0.015,
        hitCenterLocal: SIMD3<Float>(0.0, 0.0, -0.09),
        hitSizeLocal: SIMD3<Float>(0.012, 0.03, 0.086),
        beamFootprintCenterLocal: SIMD3<Float>(0.0, 0.015, -0.09),
        beamFootprintSizeLocal: SIMD2<Float>(0.011, 0.07)
    )

    let geometry = PianoKeyboardGeometry(frame: frame, keys: [whiteKey, blackKey])

    let prevLocal = SIMD3<Float>(0.0, 0.03, -0.09)
    let currLocal = SIMD3<Float>(0.0, -0.01, -0.09)
    let prevWorld = PressDetectionService.transformPoint(frame.worldFromKeyboard, prevLocal)
    let currWorld = PressDetectionService.transformPoint(frame.worldFromKeyboard, currLocal)

    _ = service.detectPressedNotes(
        fingerTips: ["index": prevWorld],
        keyboardGeometry: geometry,
        at: Date(timeIntervalSince1970: 0)
    )

    let pressed = service.detectPressedNotes(
        fingerTips: ["index": currWorld],
        keyboardGeometry: geometry,
        at: Date(timeIntervalSince1970: 1)
    )

    #expect(pressed == [61])
}

@Test
func pressDetectionUsesKeyboardLocalHitBoundsUnderYawUsingKeyboardGeometry() throws {
    let service = PressDetectionService(cooldownSeconds: 0.0)

    // xAxis points along world +Z, so zAxis becomes world +X.
    let frame = try #require(KeyboardFrame(
        a0World: SIMD3<Float>(0.0, 0.5, 0.0),
        c8World: SIMD3<Float>(0.0, 0.5, 1.0),
        planeHeight: 0.5
    ))

    let key = PianoKeyGeometry(
        midiNote: 61,
        kind: .white,
        localCenter: SIMD3<Float>(0.0, -0.015, 0.0),
        localSize: SIMD3<Float>(0.02, 0.03, 0.14),
        surfaceLocalY: 0.0,
        hitCenterLocal: SIMD3<Float>(0.0, -0.015, 0.0),
        hitSizeLocal: SIMD3<Float>(0.02, 0.03, 0.14),
        beamFootprintCenterLocal: SIMD3<Float>(0.0, 0.0, 0.0),
        beamFootprintSizeLocal: SIMD2<Float>(0.018, 0.11)
    )

    let geometry = PianoKeyboardGeometry(frame: frame, keys: [key])

    let prevLocal = SIMD3<Float>(0.0, 0.05, 0.06)
    let currLocal = SIMD3<Float>(0.0, -0.01, 0.06)
    let prevWorld = PressDetectionService.transformPoint(frame.worldFromKeyboard, prevLocal)
    let currWorld = PressDetectionService.transformPoint(frame.worldFromKeyboard, currLocal)

    _ = service.detectPressedNotes(
        fingerTips: ["index": prevWorld],
        keyboardGeometry: geometry,
        at: Date(timeIntervalSince1970: 0)
    )

    let pressed = service.detectPressedNotes(
        fingerTips: ["index": currWorld],
        keyboardGeometry: geometry,
        at: Date(timeIntervalSince1970: 1)
    )

    #expect(pressed == [61])
}
