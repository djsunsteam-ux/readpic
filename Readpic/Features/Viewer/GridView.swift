import SwiftUI

struct GridView: View {
    let files: [FileItem]
    let currentIndex: Int
    let selectedIndex: Int?
    let select: (Int) -> Void
    let open: (Int) -> Void

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
            .onAppear {
                scrollToCurrent(proxy: proxy)
            }
            .onChange(of: selectedIndex) { _, _ in
                scrollToCurrent(proxy: proxy)
            }
            .onChange(of: currentIndex) { _, _ in
                scrollToCurrent(proxy: proxy)
            }
        }
        .task(id: files.map(\.url)) {
            thumbnails = [:]
            failedURLs = []
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("\(files.count) image\(files.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
        }
    }

    private func scrollToCurrent(proxy: ScrollViewProxy) {
        let target = selectedIndex ?? currentIndex
        guard files.indices.contains(target) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    @ViewBuilder
    private func gridCell(for index: Int) -> some View {
        let file = files[index]
        let isSelected = selectedIndex == index || (!files.indices.contains(selectedIndex ?? -1) && index == currentIndex)

        VStack(spacing: 6) {
            thumbnailView(for: file)
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .background(Color(nsColor: .darkGray).opacity(0.3))
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
            select(index)
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
