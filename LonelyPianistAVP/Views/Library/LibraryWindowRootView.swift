import SwiftUI

struct LibraryWindowRootView: View {
    var body: some View {
        ContentUnavailableView("乐曲库窗口", systemImage: "music.note.list", description: Text("该窗口将在后续 task 中接入乐曲库流程。"))
            .frame(minWidth: 700, idealWidth: 900, minHeight: 520, idealHeight: 700)
    }
}

