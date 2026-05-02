import Foundation

struct AIPerformanceClipSelector {
    func tickRange(
        currentTick: Int,
        measureSpans: [MusicXMLMeasureSpan],
        maxMeasures: Int = 2
    ) -> (startTick: Int, endTick: Int)? {
        guard maxMeasures >= 1 else { return nil }

        let sortedMeasureSpans = measureSpans.sorted { $0.startTick < $1.startTick }
        guard let currentMeasureIndex = sortedMeasureSpans.firstIndex(where: { span in
            currentTick >= span.startTick && currentTick < span.endTick
        }) else { return nil }

        let startMeasureIndex = currentMeasureIndex + 1
        guard sortedMeasureSpans.indices.contains(startMeasureIndex) else { return nil }

        let startTick = sortedMeasureSpans[startMeasureIndex].startTick
        let endMeasureIndex = min(startMeasureIndex + maxMeasures - 1, sortedMeasureSpans.count - 1)
        let endTick = sortedMeasureSpans[endMeasureIndex].endTick
        guard startTick < endTick else { return nil }
        return (startTick, endTick)
    }
}

