import SwiftUI

struct HomeHeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("孤独钢琴家")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("按步骤完成：校准 → 导入谱子 → AR 引导练习。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    HomeHeaderView()
        .padding()
}
