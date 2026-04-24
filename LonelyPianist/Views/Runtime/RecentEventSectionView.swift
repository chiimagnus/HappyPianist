import Observation
import SwiftUI

struct RecentEventSectionView: View {
    @Bindable var viewModel: LonelyPianistViewModel

    var body: some View {
        GroupBox {
            if viewModel.recentLogs.isEmpty {
                Text("No events yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.recentLogs.prefix(12)) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text(timeString(item.timestamp))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 54, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        } label: {
            Text("Recent Events")
        }
    }

    private func timeString(_ date: Date) -> String {
        date.formatted(Self.eventTimeStyle)
    }

    private static let eventTimeStyle = Date.FormatStyle()
        .hour(.twoDigits(amPM: .omitted))
        .minute(.twoDigits)
        .second(.twoDigits)
}
