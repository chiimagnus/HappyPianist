import CoreMIDI
import Darwin
import Foundation

public struct MIDIHostTimeOrigin: Equatable, Sendable {
    public let transportSeconds: TimeInterval
    public let hostTime: MIDITimeStamp

    public init(transportSeconds: TimeInterval, hostTime: MIDITimeStamp) {
        self.transportSeconds = transportSeconds
        self.hostTime = hostTime
    }
}

public struct MIDIHostTimeConverter: Sendable {
    private let currentHostTime: @Sendable () -> MIDITimeStamp
    private let hostTicksPerSecond: Double

    public init(
        currentHostTime: @escaping @Sendable () -> MIDITimeStamp = { mach_absolute_time() },
        hostTicksPerSecond: Double? = nil
    ) {
        self.currentHostTime = currentHostTime
        self.hostTicksPerSecond = hostTicksPerSecond ?? Self.systemHostTicksPerSecond()
    }

    public func origin(atTransportSeconds transportSeconds: TimeInterval) -> MIDIHostTimeOrigin {
        MIDIHostTimeOrigin(
            transportSeconds: max(0, transportSeconds),
            hostTime: currentHostTime()
        )
    }

    public func hostTime(
        atTransportSeconds transportSeconds: TimeInterval,
        relativeTo origin: MIDIHostTimeOrigin
    ) -> MIDITimeStamp {
        let elapsedSeconds = max(0, transportSeconds - origin.transportSeconds)
        guard elapsedSeconds.isFinite,
              hostTicksPerSecond.isFinite,
              hostTicksPerSecond > 0
        else { return origin.hostTime }

        let elapsedHostTicks = elapsedSeconds * hostTicksPerSecond
        // ponytail: unreachable score durations saturate instead of overflowing CoreMIDI's UInt64 host clock.
        guard elapsedHostTicks.isFinite,
              elapsedHostTicks < Double(UInt64.max)
        else { return .max }

        let (hostTime, overflow) = origin.hostTime.addingReportingOverflow(
            UInt64(elapsedHostTicks.rounded(.down))
        )
        return overflow ? .max : hostTime
    }

    private static func systemHostTicksPerSecond() -> Double {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        guard timebase.numer > 0 else { return 1_000_000_000 }
        return 1_000_000_000 * Double(timebase.denom) / Double(timebase.numer)
    }
}
