import SwiftUI

struct GridView: View {
    let files: [FileItem]
    let currentIndex: Int
    let selectedIndices: Set<Int>
    let handleClick: (Int, _ isCommand: Bool, _ isShift: Bool) -> Void
    let open: (Int) -> Void
    let topInset: CGFloat
    let bottomInset: CGFloat
    let infoPanelVisible: Bool

    @State private var thumbnails: [URL: CGImage] = [:]
    @State private var failedURLs: Set<URL> = []

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(files.indices, id: \.self) { index in
                        gridCell(for: index)
                            .id(index)
                    }
                }
                .padding(16)
            }
            .contentMargins(.top, topInset, for: .scrollContent)
            .contentMargins(.bottom, bottomInset, for: .scrollContent)

            .onAppear {
                scrollToCurrent(proxy: proxy)
            }
            .onChange(of: selectedIndices) { _, _ in
                scrollToCurrent(proxy: proxy)
            }
            .onChange(of: currentIndex) { _, _ in
                scrollToCurrent(proxy: proxy)
            }
            .onChange(of: infoPanelVisible) { _, _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    scrollToCurrent(proxy: proxy)
                }
            }
        }
        .task(id: files.map(\.url)) {
            thumbnails = [:]
            failedURLs = []
        }
    }

    private func scrollToCurrent(proxy: ScrollViewProxy) {
        let target = selectedIndices.sorted().first ?? currentIndex
        guard files.indices.contains(target) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    @ViewBuilder
    private func gridCell(for index: Int) -> some View {
        let file = files[index]
        let isSelected = selectedIndices.contains(index)
            || (selectedIndices.isEmpty && index == currentIndex)

        VStack(spacing: 6) {
            thumbnailView(for: file)
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .background(Color.clear)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )

            Text(file.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            handleClick(index, flags.contains(.command), flags.contains(.shift))
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                open(index)
            }
        )
        .task {
            await loadThumbnail(for: file.url)
        }
    }

    @ViewBuilder
    private func thumbnailView(for file: FileItem) -> some View {
        ZStack(alignment: .topTrailing) {
            if let cgImage = thumbnails[file.url] {
                Image(cgImage, scale: 1, label: Text(file.name))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 120)
            } else if failedURLs.contains(file.url) {
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("Failed to load")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxHeight: 120)
            }

            if FavoritesManager.shared.isFavorite(file.url) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .padding(4)
            }
        }
    }

    private func loadThumbnail(for url: URL) async {
        guard thumbnails[url] == nil, !failedURLs.contains(url) else { return }
        guard let image = await ThumbnailLoader.load(url: url) else {
            failedURLs.insert(url)
            return
        }
        thumbnails[url] = image
    }
}
