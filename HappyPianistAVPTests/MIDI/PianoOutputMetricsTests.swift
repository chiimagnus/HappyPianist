import Diagnostics
import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func pianoOutputMetricsAggregateTimingFailuresAndPrivacySafeFields() {
    var metrics = PianoOutputMetricsAccumulator()
    metrics.record(PianoOutputTimestampObservation(scheduledAtSeconds: 1, submittedAtSeconds: 0.95, acknowledgedAtSeconds: 1.02))
    metrics.record(PianoOutputTimestampObservation(scheduledAtSeconds: 2, submittedAtSeconds: 2.015, acknowledgedAtSeconds: nil))
    metrics.recordDropped(count: 2)
    metrics.recordCancelled(count: 1)
    metrics.recordReset(succeeded: false, preventsStuckNotes: true)
    let snapshot = metrics.snapshot(
        capability: .externalMIDI,
        measurementMetadata: PianoOutputMeasurementMetadata(
            calibrationID: UUID(uuidString: "00000000-0000-0000-0000-000000000010"),
            calibrationVersion: 2,
            sampleCount: 48,
            deviceModel: "Apple Vision Pro",
            operatingSystemVersion: "visionOS 26.4",
            audioRoute: .usb
        )
    )
    #expect(snapshot.scheduledCount == 5)
    #expect(snapshot.submittedCount == 2)
    #expect(snapshot.acknowledgedCount == 1)
    #expect(snapshot.lateCount == 1)
    #expect(snapshot.droppedCount == 2)
    #expect(snapshot.cancelledCount == 1)
    #expect(snapshot.resetFailedCount == 1)
    #expect(snapshot.stuckNotePreventionCount == 0)
    #expect(snapshot.submissionLatencyBuckets[.underTenMilliseconds] == 1)
    #expect(snapshot.submissionLatencyBuckets[.underFiftyMilliseconds] == 1)
    #expect(snapshot.acknowledgementLatencyBuckets[.underFiftyMilliseconds] == 1)
    #expect(snapshot.jitterBuckets[.underTwoHundredMilliseconds] == 1)
    #expect(snapshot.diagnosticEvent.persistence == .exportable)
    #expect(snapshot.diagnosticEvent.reason.contains("audioRoute=usb"))
    #expect(snapshot.diagnosticEvent.reason.contains("/Users/") == false)
    #expect(PianoOutputMeasurementMetadata(deviceModel: "/Users/test", operatingSystemVersion: "visionOS 26.4").deviceModel == nil)
    metrics.recordReset(succeeded: true, preventsStuckNotes: true)
    #expect(metrics.snapshot(capability: .externalMIDI).stuckNotePreventionCount == 1)
}
