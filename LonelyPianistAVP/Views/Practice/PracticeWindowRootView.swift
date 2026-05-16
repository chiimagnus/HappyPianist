import SwiftUI

struct PracticeWindowRootView: View {
    var body: some View {
        ContentUnavailableView("练习窗口", systemImage: "pianokeys", description: Text("该窗口将在后续 task 中接入练习流程。"))
            .frame(minWidth: 1200, idealWidth: 1600, minHeight: 520, idealHeight: 620)
    }
}

