import SwiftUI

struct LibraryTopBarView: View {
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button("重新选择钢琴", action: onBack)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)

            Spacer()
        }
        .frame(height: 70)
        .padding(.horizontal, 28)
    }
}
