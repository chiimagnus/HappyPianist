import Foundation
import MusicXML
@testable import Notation
import Practice
import SwiftUI
import Testing
import UIKit
@testable import HappyPianistAVP

@Test
@MainActor
func nativeBookSpreadKeepsPaperAndInkInAccessibleScrollingAndIncreasedContrast() async throws {
    let source = try MusicXMLParser().parse(fileURL: testFixtureURL("NotationFidelityPiano.musicxml"))
    let projection = ScoreNotationProjection(plan: makeTestScorePerformancePlan(from: source), sourceScore: source)
    let timeline = MusicXMLAttributeTimeline(timeSignatureEvents: source.timeSignatureEvents, keySignatureEvents: source.keySignatureEvents, clefEvents: source.clefEvents)
    let plan = try GrandStaffNotationPaginationService().makePlan(score: makeNotationScoreFixture(projection: projection, measureSpans: source.measures, attributeTimeline: timeline))
    let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = try #require(scene.windows.first { $0.isKeyWindow })
    let original = window.rootViewController
    let size = window.bounds.size
    let minimum = scene.sizeRestrictions?.minimumSize
    let maximum = scene.sizeRestrictions?.maximumSize
    defer {
        window.rootViewController = original
        scene.requestGeometryUpdate(.Vision(size: size, minimumSize: minimum, maximumSize: maximum))
    }
    scene.requestGeometryUpdate(.Vision(size: CGSize(width: 1240, height: 1000), minimumSize: CGSize(width: 1240, height: 1000), maximumSize: CGSize(width: 1240, height: 1000)))
    await TestAsyncWait.until("native book window geometry") { window.bounds.width >= 1239 && window.bounds.height >= 999 }
    for textSize in [DynamicTypeSize.large, .accessibility3] {
        let controller = UIHostingController(rootView: GrandStaffNotationSpreadView(plan: plan, targetIndex: 0).padding(30).environment(\.dynamicTypeSize, textSize))
        controller.traitOverrides.accessibilityContrast = .high
        controller.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .seconds(1))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            #expect(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let rendered = try #require(image.cgImage)
        let bitmap = try #require(CGContext(data: nil, width: rendered.width, height: rendered.height, bitsPerComponent: 8, bytesPerRow: rendered.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.draw(rendered, in: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
        let pixels = UnsafeRawBufferPointer(start: try #require(bitmap.data), count: rendered.width * rendered.height * 4)
        var paper = 0
        var ink = 0
        for offset in stride(from: 0, to: pixels.count, by: 64) {
            if pixels[offset] > 235 && pixels[offset + 1] > 230 && pixels[offset + 2] > 215 { paper += 1 }
            let pixelIndex = offset / 4
            let column = pixelIndex % rendered.width
            let row = pixelIndex / rendered.width
            if column > rendered.width / 10, column < rendered.width * 2 / 5,
               row > rendered.height / 10, row < rendered.height * 7 / 10,
               pixels[offset] < 160 && pixels[offset + 1] < 160 && pixels[offset + 2] < 160 { ink += 1 }
        }
        #expect(paper > rendered.width * rendered.height / 32)
        #expect(ink > 100)
    }
}
