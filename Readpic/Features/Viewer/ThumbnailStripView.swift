import SwiftUI

struct ThumbnailStripView: View {
    let files: [FileItem]
    let currentIndex: Int
    let select: (Int) -> Void
    var onScrollStart: (() -> Void)?
    var onScrollEnd: (() -> Void)?

    @State private var thumbnails: [URL: CGImage] = [:]

    var body: some View {
        NativeHScroll(scrollToIndex: currentIndex) {
            LazyHStack(spacing: 4) {
                ForEach(Array(files.enumerated()), id: \.element.url) { index, file in
                    let isSelected = index == currentIndex

                    Button {
                        select(index)
                    } label: {
                        thumbnailView(for: file, isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 80, height: 56)
                    .background(isSelected ? Color.accentColor.opacity(0.3) : Color.clear)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
                    .task {
                        await loadThumbnail(for: file.url)
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 64)
        }
        .onScrollStart { onScrollStart?() }
        .onScrollEnd { onScrollEnd?() }
        .frame(height: 64)
        .background(.ultraThinMaterial)
        .task(id: files.map(\.url)) {
            let currentURLs = Set(files.map(\.url))
            thumbnails = thumbnails.filter { currentURLs.contains($0.key) }
        }
    }

    @ViewBuilder
    private func thumbnailView(for file: FileItem, isSelected: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            if let cgImage = thumbnails[file.url] {
                Image(cgImage, scale: 1, label: Text(file.name))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 80, maxHeight: 56)
            } else {
                Color.clear
                    .frame(maxWidth: 80, maxHeight: 56)
            }

            if FavoritesManager.shared.isFavorite(file.url) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0.5)
                    .padding(3)
            }
        }
    }

    private func loadThumbnail(for url: URL) async {
        guard thumbnails[url] == nil else { return }
        guard let image = await ThumbnailLoader.load(url: url) else { return }
        thumbnails[url] = image
    }
}
