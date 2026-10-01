import SwiftUI

struct LibraryScoreFolioView: View {
    let presentation: SongLibraryTrackPresentation
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(presentation.accentColor.opacity(0.8))
                .frame(width: 8)
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: isPlaying ? "waveform" : "music.note")
                    .font(.title)
                Spacer(minLength: 0)
                Text(presentation.title)
                    .font(.headline)
                    .lineLimit(4)
                Text(presentation.subtitle)
                    .font(.caption)
                    .lineLimit(2)
                Text("乐谱")
                    .font(.caption2)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(presentation.accentColor.gradient)
            Rectangle()
                .fill(Color(red: 0.94, green: 0.91, blue: 0.84))
                .frame(width: 4)
        }
        .foregroundStyle(.white)
        .clipShape(.rect(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.3), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 6)
    }
}
