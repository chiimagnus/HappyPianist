import SwiftUI

struct SheetMusicPreviewView: View {
    let svg: String

    var body: some View {
        SVGWebView(svg: svg)
            .frame(minWidth: 720, minHeight: 520)
    }
}

