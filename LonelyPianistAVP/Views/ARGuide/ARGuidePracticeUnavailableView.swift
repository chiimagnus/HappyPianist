import SwiftUI

struct ARGuidePracticeUnavailableView: View {
    var body: some View {
        GroupBox("练习") {
            Text("请先在主窗口导入 MusicXML，然后再回来开始练习。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    ARGuidePracticeUnavailableView()
        .padding()
}
